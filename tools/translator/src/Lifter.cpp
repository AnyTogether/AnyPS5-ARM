#include "LifterImpl.hpp"

#include <llvm/Transforms/Utils/ModuleUtils.h>

namespace Translator {

Lifter::Impl::Impl(const Elf& elf, llvm::LLVMContext& context) : elf(elf), context(context), builder(context), imageBegin(elf.ImageBegin()) {
    if (cs_open(CS_ARCH_X86, CS_MODE_64, &capstone) != CS_ERR_OK) throw std::runtime_error("cannot open capstone");
    cs_option(capstone, CS_OPT_DETAIL, CS_OPT_ON);
}

const Instruction& Lifter::Impl::Decode(std::uint64_t address) {
    if (const auto found = decoded.find(address); found != decoded.end()) return found->second;
    Instruction instruction;
    instruction.address = address;
    std::size_t available = 15;
    const std::uint8_t* code = nullptr;
    while (available != 0 && (code = elf.At(address, available)) == nullptr) --available;
    if (code != nullptr) {
        cs_insn* insn = cs_malloc(capstone);
        std::uint64_t at = address;
        if (cs_disasm_iter(capstone, &code, &available, &at, insn)) {
            instruction.size = insn->size;
            instruction.id = insn->id;
            instruction.mnemonic = insn->mnemonic;
            instruction.x86 = insn->detail->x86;
        }
        cs_free(insn, 1);
    }
    return decoded.emplace(address, std::move(instruction)).first->second;
}

// Recursive descent from a function entry. Direct call targets become functions of their own; jump
// targets join this function, except entries of known functions, which are lifted as tail calls.
void Lifter::Impl::Explore(std::uint64_t entry, std::deque<std::uint64_t>& pending) {
    auto& addresses = functions[entry];
    std::vector<std::uint64_t> work{entry};
    while (!work.empty()) {
        auto address = work.back();
        work.pop_back();
        std::vector<std::uint64_t> path;
        while (addresses.insert(address).second) {
            const auto& instruction = Decode(address);
            if (instruction.size == 0) break;
            path.push_back(address);
            if (instruction.id == X86_INS_JMP && instruction.x86.op_count == 1 && instruction.Op(0).type == X86_OP_REG) {
                for (const auto target : JumpTable(path, addresses)) {
                    tableTargets[entry].insert(target);
                    work.push_back(target);
                }
            }
            const auto target = instruction.DirectTarget();
            const bool internal = target && elf.InExecutable(*target) && functions.count(*target) == 0;
            if (instruction.id == X86_INS_CALL) {
                if (target && elf.InExecutable(*target)) pending.push_back(*target);
            } else if (instruction.id == X86_INS_LEA && instruction.Op(1).mem.base == X86_REG_RIP) {
                // A code address taken rip-relative (a thread entry, a callback) needs no relocation in
                // position-independent code, so this is the only place it shows.
                const auto taken = instruction.Next() + static_cast<std::uint64_t>(instruction.Op(1).mem.disp);
                if (elf.InExecutable(taken)) pending.push_back(taken);
            } else if (instruction.id == X86_INS_JMP || IsConditionalJump(instruction.id)) {
                if (internal) work.push_back(*target);
            }
            if (EndsPath(instruction.id)) break;
            address = instruction.Next();
        }
    }
}

// The targets of a switch jump table, from the instructions leading to "jmp reg". Clang emits
// position-independent tables as 32-bit offsets from the table:
//     cmp idx, N-1; ja default; lea base, [rip+T]; movsxd t, [base + 4*idx]; add t, base; jmp t
// The lea may be hoisted out of a loop, so it is also looked up in the rest of the function. Without
// the bounds check, entries are taken while they land in executable code near the jump; an extra
// target only costs translated code, it is never jumped to.
std::vector<std::uint64_t> Lifter::Impl::JumpTable(const std::vector<std::uint64_t>& path, const std::set<std::uint64_t>& function) {
    const auto& jump = decoded.at(path.back());
    const auto jumpReg = RegisterOf(jump.Op(0).reg).index;
    std::optional<std::uint64_t> table;
    std::optional<std::uint64_t> count;
    unsigned baseReg = ~0u, indexReg = ~0u;
    auto tableLea = [&](const Instruction& instruction) -> std::optional<std::uint64_t> {
        const auto& x86 = instruction.x86;
        if (instruction.id != X86_INS_LEA || x86.operands[1].mem.base != X86_REG_RIP || RegisterOf(x86.operands[0].reg).index != baseReg) return std::nullopt;
        const auto address = instruction.Next() + static_cast<std::uint64_t>(x86.operands[1].mem.disp);
        if (elf.InExecutable(address) || elf.At(address, 4) == nullptr) return std::nullopt;
        return address;
    };
    const std::size_t first = path.size() > 16 ? path.size() - 16 : 0;
    for (std::size_t i = path.size() - 1; i-- > first;) {
        const auto& instruction = decoded.at(path[i]);
        const auto& x86 = instruction.x86;
        if (baseReg == ~0u) {
            if (instruction.id == X86_INS_MOVSXD && x86.op_count == 2 && x86.operands[1].type == X86_OP_MEM && x86.operands[1].mem.scale == 4 &&
                RegisterOf(x86.operands[0].reg).index == jumpReg) {
                baseReg = RegisterOf(x86.operands[1].mem.base).index;
                indexReg = RegisterOf(x86.operands[1].mem.index).index;
            }
            continue;
        }
        if (!table) {
            if (const auto found = tableLea(instruction); found && (*found & 3) == 0) table = found;
        }
        if (!count && instruction.id == X86_INS_CMP && x86.op_count == 2 && x86.operands[0].type == X86_OP_REG && x86.operands[1].type == X86_OP_IMM &&
            RegisterOf(x86.operands[0].reg).index == indexReg && x86.operands[1].imm >= 0)
            count = static_cast<std::uint64_t>(x86.operands[1].imm) + 1;
    }
    if (baseReg == ~0u) return {};
    if (!table) {
        // Tables are 4-byte aligned; of several candidates, the closest one before the jump.
        std::uint64_t from = 0;
        for (const auto address : function) {
            const auto found = tableLea(decoded.at(address));
            if (!found || (*found & 3) != 0) continue;
            const bool before = address < jump.address, bestBefore = from < jump.address;
            const bool closer = !table || (before && !bestBefore) || (before == bestBefore && (before ? address > from : address < from));
            if (closer) {
                table = found;
                from = address;
            }
        }
    }
    std::vector<std::uint64_t> targets;
    if (std::getenv("APS5_TRANSLATOR_TRACE_TABLES"))
        std::fprintf(stderr, "jump table at %llx: base reg %u index %u table %llx count %lld\n", (unsigned long long)jump.address, baseReg, indexReg,
                     (unsigned long long)table.value_or(0), count ? (long long)*count : -1ll);
    if (!table) return targets;
    const std::uint64_t limit = count.value_or(256);
    for (std::uint64_t i = 0; i < limit && i < 4096; ++i) {
        const auto* slot = elf.At(*table + i * 4, 4);
        if (slot == nullptr) break;
        std::int32_t offset;
        std::memcpy(&offset, slot, 4);
        const auto target = *table + static_cast<std::uint64_t>(static_cast<std::int64_t>(offset));
        if (!elf.InExecutable(target)) break;
        if (!count && (target + 0x10000 < jump.address || target > jump.address + 0x10000)) break;
        targets.push_back(target);
    }
    return targets;
}

llvm::ConstantInt* Lifter::Impl::Const(unsigned bits, std::uint64_t value) {
    return llvm::ConstantInt::get(context, llvm::APInt(bits, bits >= 64 ? value : value & ((1ull << bits) - 1)));
}

llvm::Constant* Lifter::Impl::Host(std::uint64_t vaddr) {
    auto* address = llvm::ConstantExpr::getGetElementPtr(builder.getInt8Ty(), image, builder.getInt64(vaddr - imageBegin));
    return llvm::ConstantExpr::getPtrToInt(address, builder.getInt64Ty());
}

llvm::Value* Lifter::Impl::Resize(llvm::Value* value, unsigned bits, bool isSigned) {
    const auto from = value->getType()->getIntegerBitWidth();
    if (from == bits) return value;
    if (from > bits) return builder.CreateTrunc(value, Int(bits));
    return isSigned ? builder.CreateSExt(value, Int(bits)) : builder.CreateZExt(value, Int(bits));
}

llvm::Value* Lifter::Impl::ReadPart(unsigned index, unsigned bits, unsigned shift) {
    llvm::Value* value = Gpr64(index);
    if (shift != 0) value = builder.CreateLShr(value, shift);
    return Resize(value, bits);
}

// 32-bit writes zero the upper half; 8- and 16-bit writes keep the rest of the register.
void Lifter::Impl::WritePart(unsigned index, unsigned bits, llvm::Value* value, unsigned shift) {
    if (bits >= 32) {
        SetGpr64(index, Resize(value, 64));
        return;
    }
    const auto mask = ~(((1ull << bits) - 1) << shift);
    auto* kept = builder.CreateAnd(Gpr64(index), builder.getInt64(mask));
    auto* placed = builder.CreateShl(Resize(value, 64), shift);
    SetGpr64(index, builder.CreateOr(kept, placed));
}

llvm::Value* Lifter::Impl::ReadRegister(unsigned reg) {
    const auto r = RegisterOf(reg);
    switch (r.kind) {
    case Register::Gpr:
        return ReadPart(r.index, r.bits, r.shift);
    case Register::Vector:
        return builder.CreateLoad(Int(r.bits), Field(StateLayout::Ymm + r.index * 32));
    default:
        throw Unsupported{"register operand"};
    }
}

// Legacy SSE writes keep bits 128-255 of the ymm register; VEX writes zero them.
void Lifter::Impl::WriteRegister(unsigned reg, llvm::Value* value, bool vex) {
    const auto r = RegisterOf(reg);
    switch (r.kind) {
    case Register::Gpr:
        WritePart(r.index, r.bits, value, r.shift);
        return;
    case Register::Vector:
        builder.CreateStore(Resize(value, r.bits), Field(StateLayout::Ymm + r.index * 32));
        if (vex && r.bits == 128) builder.CreateStore(Const(128, 0), Field(StateLayout::Ymm + r.index * 32 + 16));
        return;
    default:
        throw Unsupported{"register operand"};
    }
}

llvm::Value* Lifter::Impl::Address(const Instruction& instruction, const x86_op_mem& memory, bool segment) {
    llvm::Value* address = nullptr;
    if (memory.base == X86_REG_RIP) {
        address = Host(instruction.Next() + static_cast<std::uint64_t>(memory.disp));
    } else {
        address = builder.getInt64(static_cast<std::uint64_t>(memory.disp));
        if (memory.base != X86_REG_INVALID) address = builder.CreateAdd(Resize(ReadRegister(memory.base), 64), address);
        if (memory.index != X86_REG_INVALID) {
            auto* index = builder.CreateMul(Resize(ReadRegister(memory.index), 64), builder.getInt64(static_cast<std::uint64_t>(memory.scale)));
            address = builder.CreateAdd(address, index);
        }
    }
    if (segment && memory.segment == X86_REG_FS) address = builder.CreateAdd(address, builder.CreateLoad(builder.getInt64Ty(), Field(StateLayout::FsBase)));
    if (segment && memory.segment == X86_REG_GS) address = builder.CreateAdd(address, builder.CreateLoad(builder.getInt64Ty(), Field(StateLayout::GsBase)));
    return address;
}

llvm::Value* Lifter::Impl::Read(const Instruction& instruction, unsigned index, unsigned bits) {
    const auto& op = instruction.Op(index);
    if (bits == 0) bits = op.size * 8u;
    switch (op.type) {
    case X86_OP_REG:
        return ReadRegister(op.reg);
    case X86_OP_IMM:
        return Const(bits, static_cast<std::uint64_t>(op.imm));
    case X86_OP_MEM:
        return Load(Int(bits), Address(instruction, op.mem));
    default:
        throw Unsupported{"operand"};
    }
}

void Lifter::Impl::Write(const Instruction& instruction, unsigned index, llvm::Value* value, bool vex) {
    const auto& op = instruction.Op(index);
    switch (op.type) {
    case X86_OP_REG:
        WriteRegister(op.reg, value, vex);
        return;
    case X86_OP_MEM:
        Store(Resize(value, op.size * 8u), Address(instruction, op.mem));
        return;
    default:
        throw Unsupported{"destination operand"};
    }
}

void Lifter::Impl::ResultFlags(llvm::Value* result) {
    SetFlag(Zf, builder.CreateICmpEQ(result, llvm::ConstantInt::get(result->getType(), 0)));
    SetFlag(Sf, SignBit(result));
    auto* parity = builder.CreateUnaryIntrinsic(llvm::Intrinsic::ctpop, Resize(result, 8));
    SetFlag(Pf, builder.CreateICmpEQ(builder.CreateAnd(parity, builder.getInt8(1)), builder.getInt8(0)));
}

void Lifter::Impl::AuxiliaryFlag(llvm::Value* a, llvm::Value* b, llvm::Value* result) {
    auto* mixed = builder.CreateXor(builder.CreateXor(a, b), result);
    SetFlag(Af, builder.CreateTrunc(builder.CreateLShr(Resize(mixed, 8), 4), builder.getInt1Ty()));
}

llvm::Value* Lifter::Impl::Add(llvm::Value* a, llvm::Value* b, llvm::Value* carry) {
    const auto bits = a->getType()->getIntegerBitWidth();
    auto* sum = builder.CreateAdd(builder.CreateAdd(Resize(a, bits * 2), Resize(b, bits * 2)), Resize(carry, bits * 2));
    auto* result = Resize(sum, bits);
    SetFlag(Cf, builder.CreateTrunc(builder.CreateLShr(sum, bits), builder.getInt1Ty()));
    SetFlag(Of, SignBit(builder.CreateAnd(builder.CreateXor(a, result), builder.CreateXor(b, result))));
    AuxiliaryFlag(a, b, result);
    ResultFlags(result);
    return result;
}

llvm::Value* Lifter::Impl::Sub(llvm::Value* a, llvm::Value* b, llvm::Value* borrow) {
    const auto bits = a->getType()->getIntegerBitWidth();
    auto* result = builder.CreateSub(builder.CreateSub(a, b), Resize(borrow, bits));
    SetFlag(Cf, builder.CreateICmpULT(Resize(a, bits * 2), builder.CreateAdd(Resize(b, bits * 2), Resize(borrow, bits * 2))));
    SetFlag(Of, SignBit(builder.CreateAnd(builder.CreateXor(a, b), builder.CreateXor(a, result))));
    AuxiliaryFlag(a, b, result);
    ResultFlags(result);
    return result;
}

llvm::Value* Lifter::Impl::Logic(llvm::Value* result) {
    SetFlag(Cf, builder.getFalse());
    SetFlag(Of, builder.getFalse());
    SetFlag(Af, builder.getFalse());
    ResultFlags(result);
    return result;
}

llvm::Value* Lifter::Impl::Test(Condition condition) {
    switch (condition) {
    case Condition::O: return GetFlag(Of);
    case Condition::No: return builder.CreateNot(GetFlag(Of));
    case Condition::B: return GetFlag(Cf);
    case Condition::Ae: return builder.CreateNot(GetFlag(Cf));
    case Condition::E: return GetFlag(Zf);
    case Condition::Ne: return builder.CreateNot(GetFlag(Zf));
    case Condition::Be: return builder.CreateOr(GetFlag(Cf), GetFlag(Zf));
    case Condition::A: return builder.CreateNot(builder.CreateOr(GetFlag(Cf), GetFlag(Zf)));
    case Condition::S: return GetFlag(Sf);
    case Condition::Ns: return builder.CreateNot(GetFlag(Sf));
    case Condition::P: return GetFlag(Pf);
    case Condition::Np: return builder.CreateNot(GetFlag(Pf));
    case Condition::L: return builder.CreateICmpNE(GetFlag(Sf), GetFlag(Of));
    case Condition::Ge: return builder.CreateICmpEQ(GetFlag(Sf), GetFlag(Of));
    case Condition::Le: return builder.CreateOr(GetFlag(Zf), builder.CreateICmpNE(GetFlag(Sf), GetFlag(Of)));
    case Condition::G: return builder.CreateAnd(builder.CreateNot(GetFlag(Zf)), builder.CreateICmpEQ(GetFlag(Sf), GetFlag(Of)));
    case Condition::RcxZero: return builder.CreateICmpEQ(Gpr64(Rcx), builder.getInt64(0));
    case Condition::EcxZero: return builder.CreateICmpEQ(ReadPart(Rcx, 32), builder.getInt32(0));
    case Condition::None: break;
    }
    throw Unsupported{"condition"};
}

void Lifter::Impl::Push(llvm::Value* value) {
    auto* rsp = builder.CreateSub(Gpr64(Rsp), builder.getInt64(8));
    SetGpr64(Rsp, rsp);
    Store(Resize(value, 64), rsp);
}

llvm::Value* Lifter::Impl::Pop() {
    auto* rsp = Gpr64(Rsp);
    auto* value = Load(builder.getInt64Ty(), rsp);
    SetGpr64(Rsp, builder.CreateAdd(rsp, builder.getInt64(8)));
    return value;
}

// The guest return address goes on the guest stack; the callee's ret pops it. Translated calls nest
// native frames, so guest code that rewrites its return address is not supported.
void Lifter::Impl::CallGuest(std::uint64_t target, std::uint64_t returnAddress) {
    Push(Host(returnAddress));
    if (const auto found = lifted.find(target); found != lifted.end()) builder.CreateCall(found->second, {state});
    else builder.CreateCall(callRuntime, {state, Host(target)});
}

void Lifter::Impl::CallIndirect(llvm::Value* target, std::uint64_t returnAddress) {
    Push(Host(returnAddress));
    builder.CreateCall(callRuntime, {state, target});
}

// A jump out of the function: the callee returns to this function's caller, which is a call
// followed by a return here. LLVM emits it as an arm64 tail branch.
void Lifter::Impl::TailCall(std::uint64_t target) {
    llvm::CallInst* call = nullptr;
    if (const auto found = lifted.find(target); found != lifted.end()) call = builder.CreateCall(found->second, {state});
    else call = builder.CreateCall(callRuntime, {state, Host(target)});
    call->setTailCall();
    builder.CreateRetVoid();
}

void Lifter::Impl::Jump(std::uint64_t target) {
    const bool otherFunction = target != currentEntry && lifted.count(target) != 0;
    if (const auto found = blocks.find(target); found != blocks.end() && !otherFunction) builder.CreateBr(found->second);
    else TailCall(target);
}

// An indirect jump dispatches over the function's direct branch targets; any other target leaves
// the function through the runtime lookup.
void Lifter::Impl::JumpIndirect(llvm::Value* target) {
    auto* outside = NewBlock("indirect");
    auto* offset = builder.CreateSub(target, builder.CreatePtrToInt(image, builder.getInt64Ty()));
    auto* dispatch = builder.CreateSwitch(offset, outside, static_cast<unsigned>(branchTargets.size()));
    for (const auto address : branchTargets) dispatch->addCase(builder.getInt64(address - imageBegin), blocks.at(address));
    builder.SetInsertPoint(outside);
    builder.CreateCall(callRuntime, {state, target})->setTailCall();
    builder.CreateRetVoid();
}

void Lifter::Impl::Trap(llvm::FunctionCallee callee, std::uint64_t address) {
    builder.CreateCall(callee, {state, Host(address)});
    builder.CreateUnreachable();
}

void Lifter::Impl::Arithmetic(const Instruction& instruction) {
    const auto id = instruction.id;
    const auto bits = instruction.Bits(0);
    auto* b = Read(instruction, 1, bits);
    const bool locked = instruction.Prefixed(X86_PREFIX_LOCK) && instruction.Memory(0);
    auto compute = [&](llvm::Value* a) -> llvm::Value* {
        switch (id) {
        case X86_INS_ADD: return Add(a, b, builder.getFalse());
        case X86_INS_ADC: return Add(a, b, GetFlag(Cf));
        case X86_INS_SUB: case X86_INS_CMP: return Sub(a, b, builder.getFalse());
        case X86_INS_SBB: return Sub(a, b, GetFlag(Cf));
        case X86_INS_AND: case X86_INS_TEST: return Logic(builder.CreateAnd(a, b));
        case X86_INS_OR: return Logic(builder.CreateOr(a, b));
        case X86_INS_XOR: return Logic(builder.CreateXor(a, b));
        default: throw Unsupported{instruction.mnemonic};
        }
    };
    if (locked) {
        llvm::AtomicRMWInst::BinOp operation;
        switch (id) {
        case X86_INS_ADD: operation = llvm::AtomicRMWInst::Add; break;
        case X86_INS_SUB: operation = llvm::AtomicRMWInst::Sub; break;
        case X86_INS_AND: operation = llvm::AtomicRMWInst::And; break;
        case X86_INS_OR: operation = llvm::AtomicRMWInst::Or; break;
        case X86_INS_XOR: operation = llvm::AtomicRMWInst::Xor; break;
        default: throw Unsupported{"lock " + instruction.mnemonic};
        }
        auto* pointer = Pointer(Address(instruction, instruction.Op(0).mem));
        auto* old = builder.CreateAtomicRMW(operation, pointer, b, llvm::Align(bits / 8), llvm::AtomicOrdering::SequentiallyConsistent);
        compute(old);
        return;
    }
    auto* result = compute(Read(instruction, 0));
    if (id != X86_INS_CMP && id != X86_INS_TEST) Write(instruction, 0, result);
}

void Lifter::Impl::Unary(const Instruction& instruction) {
    const auto id = instruction.id;
    const auto bits = instruction.Bits(0);
    auto* one = Const(bits, 1);
    auto* minimum = Const(bits, 1ull << (bits - 1));
    auto flags = [&](llvm::Value* a, llvm::Value* result) {
        if (id == X86_INS_INC) SetFlag(Of, builder.CreateICmpEQ(result, minimum));
        else SetFlag(Of, builder.CreateICmpEQ(a, minimum));
        AuxiliaryFlag(a, one, result);
        ResultFlags(result);
    };
    if ((id == X86_INS_INC || id == X86_INS_DEC) && instruction.Prefixed(X86_PREFIX_LOCK) && instruction.Memory(0)) {
        auto* pointer = Pointer(Address(instruction, instruction.Op(0).mem));
        const auto operation = id == X86_INS_INC ? llvm::AtomicRMWInst::Add : llvm::AtomicRMWInst::Sub;
        auto* old = builder.CreateAtomicRMW(operation, pointer, one, llvm::Align(bits / 8), llvm::AtomicOrdering::SequentiallyConsistent);
        flags(old, id == X86_INS_INC ? builder.CreateAdd(old, one) : builder.CreateSub(old, one));
        return;
    }
    auto* a = Read(instruction, 0);
    llvm::Value* result = nullptr;
    switch (id) {
    case X86_INS_INC: result = builder.CreateAdd(a, one); flags(a, result); break;
    case X86_INS_DEC: result = builder.CreateSub(a, one); flags(a, result); break;
    case X86_INS_NOT: result = builder.CreateNot(a); break;
    case X86_INS_NEG:
        result = builder.CreateNeg(a);
        SetFlag(Cf, builder.CreateICmpNE(a, Const(bits, 0)));
        SetFlag(Of, builder.CreateICmpEQ(a, minimum));
        AuxiliaryFlag(Const(bits, 0), a, result);
        ResultFlags(result);
        break;
    default: throw Unsupported{instruction.mnemonic};
    }
    Write(instruction, 0, result);
}

// Shifts and rotates. The count is masked to 5 bits (6 for 64-bit operands) and a zero count leaves
// the flags alone. The work happens in a type wide enough that no shift amount is out of range.
void Lifter::Impl::Shift(const Instruction& instruction) {
    const auto id = instruction.id;
    const auto bits = instruction.Bits(0);
    const unsigned wide = bits == 64 ? 128 : 64;
    auto* a = Read(instruction, 0);
    llvm::Value* count = instruction.x86.op_count == 1 ? Const(bits, 1) : Resize(Read(instruction, 1), bits);
    count = builder.CreateAnd(count, Const(bits, bits == 64 ? 63 : 31));
    auto* nonzero = builder.CreateICmpNE(count, Const(bits, 0));
    auto* wideCount = Resize(count, wide);
    llvm::Value* result = nullptr;
    llvm::Value* carry = nullptr;
    llvm::Value* overflow = nullptr;
    auto bit = [&](llvm::Value* value, llvm::Value* position) { return builder.CreateTrunc(builder.CreateLShr(value, position), builder.getInt1Ty()); };
    switch (id) {
    case X86_INS_SHL: case X86_INS_SAL: {
        auto* shifted = builder.CreateShl(Resize(a, wide), wideCount);
        result = Resize(shifted, bits);
        carry = bit(shifted, llvm::ConstantInt::get(Int(wide), bits));
        overflow = builder.CreateXor(SignBit(result), carry);
        break;
    }
    case X86_INS_SHR: {
        result = Resize(builder.CreateLShr(Resize(a, wide), wideCount), bits);
        carry = bit(Resize(a, wide), builder.CreateSub(wideCount, llvm::ConstantInt::get(Int(wide), 1)));
        overflow = SignBit(a);
        break;
    }
    case X86_INS_SAR: {
        result = Resize(builder.CreateAShr(Resize(a, wide, true), wideCount), bits);
        carry = bit(Resize(a, wide, true), builder.CreateSub(wideCount, llvm::ConstantInt::get(Int(wide), 1)));
        overflow = builder.getFalse();
        break;
    }
    case X86_INS_ROL: case X86_INS_ROR: {
        auto* rotation = builder.CreateURem(count, Const(bits, bits));
        const auto intrinsic = id == X86_INS_ROL ? llvm::Intrinsic::fshl : llvm::Intrinsic::fshr;
        result = builder.CreateIntrinsic(intrinsic, {Int(bits)}, {a, a, rotation});
        if (id == X86_INS_ROL) {
            carry = builder.CreateTrunc(result, builder.getInt1Ty());
            overflow = builder.CreateXor(SignBit(result), carry);
        } else {
            carry = SignBit(result);
            overflow = builder.CreateXor(carry, bit(result, Const(bits, bits - 2)));
        }
        Write(instruction, 0, result);
        SetFlag(Cf, builder.CreateSelect(nonzero, carry, GetFlag(Cf)));
        SetFlag(Of, builder.CreateSelect(nonzero, overflow, GetFlag(Of)));
        return;
    }
    default: throw Unsupported{instruction.mnemonic};
    }
    Write(instruction, 0, result);
    SetFlag(Cf, builder.CreateSelect(nonzero, carry, GetFlag(Cf)));
    SetFlag(Of, builder.CreateSelect(nonzero, overflow, GetFlag(Of)));
    SetFlag(Zf, builder.CreateSelect(nonzero, builder.CreateICmpEQ(result, Const(bits, 0)), GetFlag(Zf)));
    SetFlag(Sf, builder.CreateSelect(nonzero, SignBit(result), GetFlag(Sf)));
    auto* parity = builder.CreateUnaryIntrinsic(llvm::Intrinsic::ctpop, Resize(result, 8));
    auto* even = builder.CreateICmpEQ(builder.CreateAnd(parity, builder.getInt8(1)), builder.getInt8(0));
    SetFlag(Pf, builder.CreateSelect(nonzero, even, GetFlag(Pf)));
}

void Lifter::Impl::Multiply(const Instruction& instruction) {
    const bool isSigned = instruction.id == X86_INS_IMUL;
    const auto count = instruction.x86.op_count;
    if (count >= 2) {
        const auto bits = instruction.Bits(0);
        auto* a = count == 3 ? Read(instruction, 1) : Read(instruction, 0);
        auto* b = count == 3 ? Read(instruction, 2, bits) : Read(instruction, 1, bits);
        auto* product = builder.CreateMul(Resize(a, bits * 2, true), Resize(b, bits * 2, true));
        auto* result = Resize(product, bits);
        auto* overflow = builder.CreateICmpNE(Resize(result, bits * 2, true), product);
        Write(instruction, 0, result);
        SetFlag(Cf, overflow);
        SetFlag(Of, overflow);
        return;
    }
    const auto bits = instruction.Bits(0);
    auto* a = ReadPart(Rax, bits);
    auto* b = Read(instruction, 0);
    auto* product = builder.CreateMul(Resize(a, bits * 2, isSigned), Resize(b, bits * 2, isSigned));
    auto* low = Resize(product, bits);
    auto* high = Resize(builder.CreateLShr(product, bits), bits);
    if (bits == 8) {
        WritePart(Rax, 16, product);
    } else {
        WritePart(Rax, bits, low);
        WritePart(Rdx, bits, high);
    }
    auto* overflow = isSigned ? builder.CreateICmpNE(Resize(low, bits * 2, true), product) : builder.CreateICmpNE(high, Const(bits, 0));
    SetFlag(Cf, overflow);
    SetFlag(Of, overflow);
}

// A zero divisor or a quotient that does not fit is #DE on x86; here it traps through the runtime.
void Lifter::Impl::Divide(const Instruction& instruction) {
    const bool isSigned = instruction.id == X86_INS_IDIV;
    const auto bits = instruction.Bits(0);
    const auto wide = bits * 2;
    llvm::Value* dividend = nullptr;
    if (bits == 8) {
        dividend = ReadPart(Rax, 16);
    } else {
        auto* high = builder.CreateShl(Resize(ReadPart(Rdx, bits), wide), bits);
        dividend = builder.CreateOr(high, Resize(ReadPart(Rax, bits), wide));
    }
    auto* divisor = Resize(Read(instruction, 0), wide, isSigned);
    auto* fault = builder.CreateICmpEQ(divisor, llvm::ConstantInt::get(Int(wide), 0));
    if (isSigned) {
        auto* minimum = llvm::ConstantInt::get(context, llvm::APInt::getSignedMinValue(wide));
        auto* minusOne = llvm::ConstantInt::get(context, llvm::APInt::getAllOnes(wide));
        fault = builder.CreateOr(fault, builder.CreateAnd(builder.CreateICmpEQ(dividend, minimum), builder.CreateICmpEQ(divisor, minusOne)));
    }
    auto* trap = NewBlock("divide-error");
    auto* divide = NewBlock("divide");
    auto* done = NewBlock("divided");
    BranchIf(fault, trap, divide);
    builder.SetInsertPoint(trap);
    Trap(trapRuntime, instruction.address);
    builder.SetInsertPoint(divide);
    auto* quotient = isSigned ? builder.CreateSDiv(dividend, divisor) : builder.CreateUDiv(dividend, divisor);
    auto* remainder = isSigned ? builder.CreateSRem(dividend, divisor) : builder.CreateURem(dividend, divisor);
    auto* narrow = Resize(quotient, bits);
    auto* fits = builder.CreateICmpEQ(Resize(narrow, wide, isSigned), quotient);
    auto* store = NewBlock("divide-store");
    BranchIf(fits, store, trap);
    builder.SetInsertPoint(store);
    if (bits == 8) {
        WritePart(Rax, 8, narrow);
        WritePart(Rax, 8, Resize(remainder, 8), 8);
    } else {
        WritePart(Rax, bits, narrow);
        WritePart(Rdx, bits, Resize(remainder, bits));
    }
    builder.CreateBr(done);
    builder.SetInsertPoint(done);
}

void Lifter::Impl::BitTest(const Instruction& instruction) {
    const auto id = instruction.id;
    const auto bits = instruction.Bits(0);
    llvm::Value* offset = Read(instruction, 1, bits);
    if (instruction.Prefixed(X86_PREFIX_LOCK)) throw Unsupported{"lock " + instruction.mnemonic};
    auto apply = [&](llvm::Value* value, llvm::Value* position) -> llvm::Value* {
        auto* mask = builder.CreateShl(llvm::ConstantInt::get(value->getType(), 1), position);
        SetFlag(Cf, builder.CreateICmpNE(builder.CreateAnd(value, mask), llvm::ConstantInt::get(value->getType(), 0)));
        switch (id) {
        case X86_INS_BTS: return builder.CreateOr(value, mask);
        case X86_INS_BTR: return builder.CreateAnd(value, builder.CreateNot(mask));
        case X86_INS_BTC: return builder.CreateXor(value, mask);
        default: return nullptr;
        }
    };
    if (instruction.Memory(0) && instruction.Op(1).type == X86_OP_REG) {
        // A register bit offset addresses memory beyond the operand: byte (offset >> 3), bit (offset & 7).
        auto* wideOffset = Resize(offset, 64, true);
        auto* address = builder.CreateAdd(Address(instruction, instruction.Op(0).mem), builder.CreateAShr(wideOffset, 3));
        auto* byte = Load(builder.getInt8Ty(), address);
        auto* result = apply(byte, Resize(builder.CreateAnd(wideOffset, builder.getInt64(7)), 8));
        if (result != nullptr) Store(result, address);
        return;
    }
    auto* value = Read(instruction, 0);
    auto* result = apply(value, builder.CreateAnd(offset, Const(bits, bits - 1)));
    if (result != nullptr) Write(instruction, 0, result);
}

void Lifter::Impl::BitScan(const Instruction& instruction) {
    const auto id = instruction.id;
    const auto bits = instruction.Bits(0);
    auto* source = Read(instruction, 1);
    auto* zero = builder.CreateICmpEQ(source, Const(bits, 0));
    switch (id) {
    case X86_INS_BSF: case X86_INS_BSR: {
        // A zero source leaves the destination unchanged (as the hardware does).
        llvm::Value* index = nullptr;
        if (id == X86_INS_BSF) index = builder.CreateBinaryIntrinsic(llvm::Intrinsic::cttz, source, builder.getFalse());
        else index = builder.CreateSub(Const(bits, bits - 1), builder.CreateBinaryIntrinsic(llvm::Intrinsic::ctlz, source, builder.getFalse()));
        Write(instruction, 0, builder.CreateSelect(zero, Read(instruction, 0), index));
        SetFlag(Zf, zero);
        return;
    }
    case X86_INS_TZCNT: case X86_INS_LZCNT: {
        const auto intrinsic = id == X86_INS_TZCNT ? llvm::Intrinsic::cttz : llvm::Intrinsic::ctlz;
        auto* result = builder.CreateBinaryIntrinsic(intrinsic, source, builder.getFalse());
        Write(instruction, 0, result);
        SetFlag(Cf, zero);
        SetFlag(Zf, builder.CreateICmpEQ(result, Const(bits, 0)));
        return;
    }
    case X86_INS_POPCNT: {
        Write(instruction, 0, builder.CreateUnaryIntrinsic(llvm::Intrinsic::ctpop, source));
        for (const auto flag : {Cf, Pf, Af, Sf, Of}) SetFlag(flag, builder.getFalse());
        SetFlag(Zf, zero);
        return;
    }
    default: throw Unsupported{instruction.mnemonic};
    }
}

// xchg with memory is implicitly locked; cmpxchg and xadd on memory are emitted atomic as well.
void Lifter::Impl::Exchange(const Instruction& instruction) {
    const auto id = instruction.id;
    const auto bits = instruction.Bits(0);
    const auto ordering = llvm::AtomicOrdering::SequentiallyConsistent;
    if (id == X86_INS_XCHG) {
        const unsigned memory = instruction.Memory(0) ? 0 : instruction.Memory(1) ? 1 : 2;
        if (memory == 2) {
            auto* a = Read(instruction, 0);
            auto* b = Read(instruction, 1);
            Write(instruction, 0, b);
            Write(instruction, 1, a);
            return;
        }
        const unsigned reg = 1 - memory;
        auto* pointer = Pointer(Address(instruction, instruction.Op(memory).mem));
        auto* old = builder.CreateAtomicRMW(llvm::AtomicRMWInst::Xchg, pointer, Read(instruction, reg), llvm::Align(bits / 8), ordering);
        Write(instruction, reg, old);
        return;
    }
    if (id == X86_INS_XADD) {
        auto* source = Read(instruction, 1);
        if (instruction.Memory(0)) {
            auto* pointer = Pointer(Address(instruction, instruction.Op(0).mem));
            auto* old = builder.CreateAtomicRMW(llvm::AtomicRMWInst::Add, pointer, source, llvm::Align(bits / 8), ordering);
            Add(old, source, builder.getFalse());
            Write(instruction, 1, old);
            return;
        }
        auto* old = Read(instruction, 0);
        auto* sum = Add(old, source, builder.getFalse());
        Write(instruction, 1, old);
        Write(instruction, 0, sum);
        return;
    }
    // cmpxchg: compare the accumulator with the destination; equal stores the source, otherwise the
    // accumulator receives the destination. A 32-bit accumulator is only written (and zero-extended) on failure.
    auto* expected = ReadPart(Rax, bits);
    auto* source = Read(instruction, 1);
    llvm::Value* old = nullptr;
    llvm::Value* equal = nullptr;
    if (instruction.Memory(0)) {
        auto* pointer = Pointer(Address(instruction, instruction.Op(0).mem));
        auto* exchange = builder.CreateAtomicCmpXchg(pointer, expected, source, llvm::Align(bits / 8), ordering, ordering);
        old = builder.CreateExtractValue(exchange, 0);
        equal = builder.CreateExtractValue(exchange, 1);
    } else {
        old = Read(instruction, 0);
        equal = builder.CreateICmpEQ(old, expected);
        Write(instruction, 0, builder.CreateSelect(equal, source, old));
    }
    Sub(expected, old, builder.getFalse());
    if (bits == 32) SetGpr64(Rax, builder.CreateSelect(equal, Gpr64(Rax), Resize(old, 64)));
    else WritePart(Rax, bits, builder.CreateSelect(equal, expected, old));
}

// stos and movs, with or without rep; the direction flag picks the step sign.
void Lifter::Impl::String(const Instruction& instruction) {
    const bool move = instruction.id == X86_INS_MOVSB || instruction.id == X86_INS_MOVSW || instruction.id == X86_INS_MOVSD || instruction.id == X86_INS_MOVSQ;
    const auto bytes = instruction.Op(0).size;
    auto step = [&]() {
        auto* delta = builder.CreateSelect(GetFlag(Df), builder.getInt64(0 - static_cast<std::uint64_t>(bytes)), builder.getInt64(bytes));
        auto* rdi = Gpr64(Rdi);
        if (move) {
            auto* rsi = Gpr64(Rsi);
            Store(Load(Int(bytes * 8), rsi), rdi);
            SetGpr64(Rsi, builder.CreateAdd(rsi, delta));
        } else {
            Store(ReadPart(Rax, bytes * 8), rdi);
        }
        SetGpr64(Rdi, builder.CreateAdd(rdi, delta));
    };
    if (instruction.Prefixed(X86_PREFIX_REPNE)) throw Unsupported{"repne " + instruction.mnemonic};
    if (!instruction.Prefixed(X86_PREFIX_REP)) {
        step();
        return;
    }
    auto* header = NewBlock("rep");
    auto* body = NewBlock("rep-body");
    auto* done = NewBlock("rep-done");
    builder.CreateBr(header);
    builder.SetInsertPoint(header);
    BranchIf(builder.CreateICmpEQ(Gpr64(Rcx), builder.getInt64(0)), done, body);
    builder.SetInsertPoint(body);
    step();
    SetGpr64(Rcx, builder.CreateSub(Gpr64(Rcx), builder.getInt64(1)));
    builder.CreateBr(header);
    builder.SetInsertPoint(done);
}

void Lifter::Impl::VectorMove(const Instruction& instruction) {
    const auto id = instruction.id;
    const bool vex = instruction.mnemonic.front() == 'v';
    if (id == X86_INS_MOVD || id == X86_INS_MOVQ || id == X86_INS_VMOVD || id == X86_INS_VMOVQ) {
        const auto& destination = instruction.Op(0);
        if (destination.type == X86_OP_REG && RegisterOf(destination.reg).kind == Register::Vector) {
            // To xmm: the low 32 or 64 bits, zero-extended to 128.
            const unsigned bits = id == X86_INS_MOVD || id == X86_INS_VMOVD ? 32 : 64;
            WriteRegister(destination.reg, Resize(Resize(Read(instruction, 1, bits), bits), 128), vex);
        } else {
            Write(instruction, 0, Resize(Read(instruction, 1), instruction.Bits(0)));
        }
        return;
    }
    Write(instruction, 0, Read(instruction, 1), vex);
}

void Lifter::Impl::VectorLogic(const Instruction& instruction) {
    const auto id = instruction.id;
    const bool vex = instruction.x86.op_count == 3;
    auto* a = Read(instruction, vex ? 1 : 0);
    auto* b = Read(instruction, vex ? 2 : 1);
    llvm::Value* result = nullptr;
    switch (id) {
    case X86_INS_PXOR: case X86_INS_XORPS: case X86_INS_XORPD: case X86_INS_VPXOR: case X86_INS_VXORPS: case X86_INS_VXORPD:
        result = builder.CreateXor(a, b);
        break;
    case X86_INS_PAND: case X86_INS_ANDPS: case X86_INS_ANDPD: case X86_INS_VPAND: case X86_INS_VANDPS: case X86_INS_VANDPD:
        result = builder.CreateAnd(a, b);
        break;
    case X86_INS_POR: case X86_INS_ORPS: case X86_INS_ORPD: case X86_INS_VPOR: case X86_INS_VORPS: case X86_INS_VORPD:
        result = builder.CreateOr(a, b);
        break;
    case X86_INS_PANDN: case X86_INS_ANDNPS: case X86_INS_ANDNPD: case X86_INS_VPANDN: case X86_INS_VANDNPS: case X86_INS_VANDNPD:
        result = builder.CreateAnd(builder.CreateNot(a), b);
        break;
    default: throw Unsupported{instruction.mnemonic};
    }
    Write(instruction, 0, result, vex);
}

void Lifter::Impl::Emit(const Instruction& instruction) {
    const auto id = instruction.id;
    const auto& x86 = instruction.x86;
    if (const auto condition = ConditionOf(id); condition != Condition::None) {
        if (IsConditionalJump(id)) {
            const auto target = *instruction.DirectTarget();
            auto* fallthrough = NewBlock("fallthrough");
            llvm::BasicBlock* taken = nullptr;
            const bool otherFunction = target != currentEntry && lifted.count(target) != 0;
            if (const auto found = blocks.find(target); found != blocks.end() && !otherFunction) {
                taken = found->second;
            } else {
                taken = NewBlock("tail");
                llvm::IRBuilderBase::InsertPointGuard guard(builder);
                builder.SetInsertPoint(taken);
                TailCall(target);
            }
            BranchIf(Test(condition), taken, fallthrough);
            builder.SetInsertPoint(fallthrough);
            return;
        }
        if (instruction.mnemonic.rfind("set", 0) == 0) {
            Write(instruction, 0, Resize(Test(condition), 8));
            return;
        }
        auto* chosen = builder.CreateSelect(Test(condition), Read(instruction, 1), Read(instruction, 0));
        Write(instruction, 0, chosen);
        return;
    }
    switch (id) {
    case X86_INS_NOP: case X86_INS_ENDBR64: case X86_INS_PAUSE:
    case X86_INS_PREFETCH: case X86_INS_PREFETCHW: case X86_INS_PREFETCHT0: case X86_INS_PREFETCHT1: case X86_INS_PREFETCHT2: case X86_INS_PREFETCHNTA:
        return;
    case X86_INS_LFENCE: case X86_INS_MFENCE: case X86_INS_SFENCE:
        builder.CreateFence(llvm::AtomicOrdering::SequentiallyConsistent);
        return;
    case X86_INS_MOV: case X86_INS_MOVABS: case X86_INS_MOVNTI:
        Write(instruction, 0, Read(instruction, 1, instruction.Bits(0)));
        return;
    case X86_INS_MOVZX:
        Write(instruction, 0, Resize(Read(instruction, 1), instruction.Bits(0)));
        return;
    case X86_INS_MOVSX: case X86_INS_MOVSXD:
        Write(instruction, 0, Resize(Read(instruction, 1), instruction.Bits(0), true));
        return;
    case X86_INS_LEA:
        Write(instruction, 0, Resize(Address(instruction, instruction.Op(1).mem, false), instruction.Bits(0)));
        return;
    case X86_INS_ADD: case X86_INS_ADC: case X86_INS_SUB: case X86_INS_SBB: case X86_INS_CMP:
    case X86_INS_AND: case X86_INS_OR: case X86_INS_XOR: case X86_INS_TEST:
        Arithmetic(instruction);
        return;
    case X86_INS_INC: case X86_INS_DEC: case X86_INS_NEG: case X86_INS_NOT:
        Unary(instruction);
        return;
    case X86_INS_SHL: case X86_INS_SAL: case X86_INS_SHR: case X86_INS_SAR: case X86_INS_ROL: case X86_INS_ROR:
        Shift(instruction);
        return;
    case X86_INS_IMUL: case X86_INS_MUL:
        Multiply(instruction);
        return;
    case X86_INS_DIV: case X86_INS_IDIV:
        Divide(instruction);
        return;
    case X86_INS_BT: case X86_INS_BTS: case X86_INS_BTR: case X86_INS_BTC:
        BitTest(instruction);
        return;
    case X86_INS_BSF: case X86_INS_BSR: case X86_INS_TZCNT: case X86_INS_LZCNT: case X86_INS_POPCNT:
        BitScan(instruction);
        return;
    case X86_INS_BSWAP: {
        auto* value = Read(instruction, 0);
        Write(instruction, 0, builder.CreateUnaryIntrinsic(llvm::Intrinsic::bswap, value));
        return;
    }
    case X86_INS_XCHG: case X86_INS_XADD: case X86_INS_CMPXCHG:
        Exchange(instruction);
        return;
    case X86_INS_CBW: WritePart(Rax, 16, Resize(ReadPart(Rax, 8), 16, true)); return;
    case X86_INS_CWDE: WritePart(Rax, 32, Resize(ReadPart(Rax, 16), 32, true)); return;
    case X86_INS_CDQE: SetGpr64(Rax, Resize(ReadPart(Rax, 32), 64, true)); return;
    case X86_INS_CWD: WritePart(Rdx, 16, builder.CreateAShr(ReadPart(Rax, 16), 15)); return;
    case X86_INS_CDQ: WritePart(Rdx, 32, builder.CreateAShr(ReadPart(Rax, 32), 31)); return;
    case X86_INS_CQO: SetGpr64(Rdx, builder.CreateAShr(Gpr64(Rax), 63)); return;
    case X86_INS_CLC: SetFlag(Cf, builder.getFalse()); return;
    case X86_INS_STC: SetFlag(Cf, builder.getTrue()); return;
    case X86_INS_CMC: SetFlag(Cf, builder.CreateNot(GetFlag(Cf))); return;
    case X86_INS_CLD: SetFlag(Df, builder.getFalse()); return;
    case X86_INS_STD: SetFlag(Df, builder.getTrue()); return;
    case X86_INS_PUSH:
        if (instruction.Op(0).size != 8) throw Unsupported{"16-bit push"};
        Push(Read(instruction, 0, 64));
        return;
    case X86_INS_POP:
        if (instruction.Op(0).size != 8) throw Unsupported{"16-bit pop"};
        Write(instruction, 0, Pop());
        return;
    case X86_INS_LEAVE:
        SetGpr64(Rsp, Gpr64(Rbp));
        SetGpr64(Rbp, Pop());
        return;
    case X86_INS_CALL:
        if (const auto target = instruction.DirectTarget()) CallGuest(*target, instruction.Next());
        else CallIndirect(Read(instruction, 0, 64), instruction.Next());
        return;
    case X86_INS_JMP:
        if (const auto target = instruction.DirectTarget()) Jump(*target);
        else JumpIndirect(Read(instruction, 0, 64));
        return;
    case X86_INS_RET: {
        const std::uint64_t release = 8 + (x86.op_count == 1 ? static_cast<std::uint64_t>(x86.operands[0].imm) : 0);
        SetGpr64(Rsp, builder.CreateAdd(Gpr64(Rsp), builder.getInt64(release)));
        builder.CreateRetVoid();
        return;
    }
    case X86_INS_UD2: case X86_INS_INT3: case X86_INS_HLT:
        Trap(trapRuntime, instruction.address);
        return;
    case X86_INS_STOSB: case X86_INS_STOSW: case X86_INS_STOSD: case X86_INS_STOSQ:
    case X86_INS_MOVSB: case X86_INS_MOVSW: case X86_INS_MOVSQ:
        String(instruction);
        return;
    case X86_INS_MOVSD:
        // movsd is both the string move and the scalar double move; only the string form is lifted.
        if (x86.op_count == 2 && instruction.Memory(0) && instruction.Memory(1)) {
            String(instruction);
            return;
        }
        if (EmitVectorFloat(instruction)) return;
        throw Unsupported{instruction.mnemonic};
    case X86_INS_MOVAPS: case X86_INS_MOVUPS: case X86_INS_MOVAPD: case X86_INS_MOVUPD: case X86_INS_MOVDQA: case X86_INS_MOVDQU:
    case X86_INS_LDDQU: case X86_INS_MOVNTDQ: case X86_INS_MOVNTPS: case X86_INS_MOVNTPD: case X86_INS_MOVD: case X86_INS_MOVQ:
    case X86_INS_VMOVAPS: case X86_INS_VMOVUPS: case X86_INS_VMOVAPD: case X86_INS_VMOVUPD: case X86_INS_VMOVDQA: case X86_INS_VMOVDQU:
    case X86_INS_VMOVD: case X86_INS_VMOVQ:
        VectorMove(instruction);
        return;
    case X86_INS_PXOR: case X86_INS_XORPS: case X86_INS_XORPD: case X86_INS_PAND: case X86_INS_ANDPS: case X86_INS_ANDPD:
    case X86_INS_POR: case X86_INS_ORPS: case X86_INS_ORPD: case X86_INS_PANDN: case X86_INS_ANDNPS: case X86_INS_ANDNPD:
    case X86_INS_VPXOR: case X86_INS_VXORPS: case X86_INS_VXORPD: case X86_INS_VPAND: case X86_INS_VANDPS: case X86_INS_VANDPD:
    case X86_INS_VPOR: case X86_INS_VORPS: case X86_INS_VORPD: case X86_INS_VPANDN: case X86_INS_VANDNPS: case X86_INS_VANDNPD:
        VectorLogic(instruction);
        return;
    case X86_INS_VZEROUPPER: case X86_INS_VZEROALL:
        for (unsigned i = 0; i < 16; ++i) {
            if (id == X86_INS_VZEROALL) builder.CreateStore(Const(256, 0), Field(StateLayout::Ymm + i * 32));
            else builder.CreateStore(Const(128, 0), Field(StateLayout::Ymm + i * 32 + 16));
        }
        return;
    default:
        if (EmitVectorInteger(instruction) || EmitVectorFloat(instruction) || EmitBits(instruction)) return;
        throw Unsupported{instruction.mnemonic};
    }
}

// Removes what a failed instruction emitted: its own block's instructions and the blocks it appended.
void Lifter::Impl::Discard(llvm::BasicBlock* block, std::size_t keepBlocks) {
    std::vector<llvm::BasicBlock*> appended;
    for (auto it = std::next(current->begin(), static_cast<std::ptrdiff_t>(keepBlocks)); it != current->end(); ++it) appended.push_back(&*it);
    for (auto* extra : appended) extra->dropAllReferences();
    while (!block->empty()) block->back().eraseFromParent();
    for (auto* extra : appended) extra->eraseFromParent();
}

void Lifter::Impl::LiftFunction(std::uint64_t entry, const std::set<std::uint64_t>& addresses, Statistics& stats) {
    current = lifted.at(entry);
    currentEntry = entry;
    state = current->getArg(0);
    blocks.clear();
    branchTargets.clear();
    auto* prologue = NewBlock("entry");
    for (const auto address : addresses) blocks[address] = llvm::BasicBlock::Create(context, "x" + Hex(address - imageBegin), current);
    for (const auto address : addresses) {
        const auto& instruction = decoded.at(address);
        const auto target = instruction.DirectTarget();
        if (target && (instruction.id == X86_INS_JMP || IsConditionalJump(instruction.id)) && blocks.count(*target) != 0) branchTargets.insert(*target);
    }
    branchTargets.insert(entry);
    if (const auto found = tableTargets.find(entry); found != tableTargets.end()) {
        for (const auto target : found->second) {
            if (blocks.count(target) != 0) branchTargets.insert(target);
        }
    }
    builder.SetInsertPoint(prologue);
    builder.CreateBr(blocks.at(entry));
    for (const auto address : addresses) {
        const auto& instruction = decoded.at(address);
        auto* block = blocks.at(address);
        builder.SetInsertPoint(block);
        const auto keep = current->size();
        try {
            if (instruction.size == 0) throw Unsupported{"(undecodable)"};
            Emit(instruction);
            ++stats.instructions;
            if (!builder.GetInsertBlock()->hasTerminator()) {
                if (const auto next = blocks.find(instruction.Next()); next != blocks.end()) builder.CreateBr(next->second);
                else Trap(unsupportedRuntime, instruction.Next());
            }
        } catch (const Unsupported& unsupported) {
            Discard(block, keep);
            builder.SetInsertPoint(block);
            ++stats.unsupported[unsupported.what];
            Trap(unsupportedRuntime, address);
        }
    }
}

// The guest image: the loaded segments at their offsets from the lowest one, with each 8-byte slot a
// supported relocation targets replaced by a symbolic pointer the host linker resolves. Imports bind
// to the host libraries by their NID ("<nid>#<library>#<module>" exports as "<nid>").
void Lifter::Impl::EmitImage(Statistics& stats) {
    const auto size = elf.ImageEnd() - imageBegin;
    std::vector<std::uint8_t> bytes(size);
    for (const auto& segment : elf.Loads()) std::memcpy(bytes.data() + (segment.vaddr - imageBegin), elf.Bytes().data() + segment.fileOffset, segment.fileSize);
    std::map<std::uint64_t, const Relocation*> slots;
    for (const auto& relocation : elf.Relocations()) {
        const auto type = relocation.type;
        if (type != RelocationAbsolute64 && type != RelocationGlobDat && type != RelocationJumpSlot && type != RelocationRelative) {
            ++stats.unsupported["relocation type " + std::to_string(type)];
            continue;
        }
        if (relocation.offset < imageBegin || relocation.offset + 8 > imageBegin + size) continue;
        slots[relocation.offset - imageBegin] = &relocation;
    }
    std::vector<llvm::Type*> types;
    std::vector<std::pair<std::uint64_t, std::uint64_t>> pieces; // offset, size; size 0 is a relocated slot
    std::uint64_t at = 0;
    for (const auto& [offset, relocation] : slots) {
        if (offset < at) continue;
        if (offset > at) pieces.emplace_back(at, offset - at);
        pieces.emplace_back(offset, 0);
        at = offset + 8;
    }
    if (at < size) pieces.emplace_back(at, size - at);
    for (const auto& [offset, length] : pieces) types.push_back(length == 0 ? static_cast<llvm::Type*>(builder.getPtrTy()) : llvm::ArrayType::get(builder.getInt8Ty(), length));
    auto* type = llvm::StructType::get(context, types, true);
    image = new llvm::GlobalVariable(*module, type, false, llvm::GlobalValue::ExternalLinkage, nullptr, "aps5_guest_image");
    image->setAlignment(llvm::Align(0x4000));
    std::vector<llvm::Constant*> values;
    for (const auto& [offset, length] : pieces) {
        if (length == 0) {
            values.push_back(SlotValue(*slots.at(offset)));
            continue;
        }
        const auto* begin = bytes.data() + offset;
        if (std::all_of(begin, begin + length, [](std::uint8_t byte) { return byte == 0; })) values.push_back(llvm::ConstantAggregateZero::get(llvm::ArrayType::get(builder.getInt8Ty(), length)));
        else values.push_back(llvm::ConstantDataArray::get(context, llvm::ArrayRef<std::uint8_t>(begin, length)));
    }
    image->setInitializer(llvm::ConstantStruct::get(type, values));
}

llvm::Constant* Lifter::Impl::SlotValue(const Relocation& relocation) {
    auto offsetFrom = [&](llvm::Constant* base, std::int64_t offset) -> llvm::Constant* {
        if (offset == 0) return base;
        return llvm::ConstantExpr::getGetElementPtr(builder.getInt8Ty(), base, builder.getInt64(static_cast<std::uint64_t>(offset)));
    };
    if (relocation.type == RelocationRelative) return offsetFrom(image, relocation.addend - static_cast<std::int64_t>(imageBegin));
    const auto& symbol = elf.Symbols().at(relocation.symbol);
    if (symbol.section != 0) return offsetFrom(image, static_cast<std::int64_t>(symbol.value - imageBegin) + relocation.addend);
    const auto name = symbol.name.substr(0, symbol.name.find('#'));
    llvm::GlobalValue* import = module->getNamedValue(name);
    if (import == nullptr) {
        if ((symbol.info & 0xf) == SymbolTypeFunction) import = llvm::Function::Create(llvm::FunctionType::get(builder.getVoidTy(), false), llvm::GlobalValue::ExternalLinkage, name, module);
        else import = new llvm::GlobalVariable(*module, builder.getInt8Ty(), false, llvm::GlobalValue::ExternalLinkage, nullptr, name);
        if ((symbol.info >> 4) == SymbolBindingWeak) import->setLinkage(llvm::GlobalValue::ExternalWeakLinkage);
    }
    return offsetFrom(import, relocation.addend);
}

void Lifter::Impl::EmitTables() {
    auto* rowType = llvm::StructType::get(context, {builder.getInt64Ty(), builder.getPtrTy()});
    std::vector<llvm::Constant*> rows;
    for (const auto& [entry, function] : lifted) rows.push_back(llvm::ConstantStruct::get(rowType, {builder.getInt64(entry - imageBegin), function}));
    auto* tableType = llvm::ArrayType::get(rowType, rows.size());
    auto constant = [&](llvm::Type* type, llvm::Constant* value, const char* name) {
        new llvm::GlobalVariable(*module, type, true, llvm::GlobalValue::ExternalLinkage, value, name);
    };
    constant(tableType, llvm::ConstantArray::get(tableType, rows), "aps5_guest_functions");
    constant(builder.getInt64Ty(), builder.getInt64(rows.size()), "aps5_guest_function_count");
    constant(builder.getInt64Ty(), builder.getInt64(elf.ImageEnd() - imageBegin), "aps5_guest_image_size");
    constant(builder.getInt64Ty(), builder.getInt64(elf.Entry() - imageBegin), "aps5_guest_entry");
    const auto& tls = elf.Tls();
    auto* tlsType = llvm::ArrayType::get(builder.getInt64Ty(), 4);
    constant(tlsType, llvm::ConstantDataArray::get(context, llvm::ArrayRef<std::uint64_t>{tls.memorySize != 0 ? tls.vaddr - imageBegin : 0, tls.fileSize, tls.memorySize, elf.TlsAlign()}),
             "aps5_guest_tls");
}

// __APS5DATA,__meta, as the relinker writes it for the Rosetta mode (MacOsImage.cpp): libc emulates
// dl_iterate_phdr from the load bias and the original program headers, which is how the guest finds
// its PT_SCE_PROCPARAM. The TLS slots stay zero; the translator runtime sets up guest TLS itself.
void Lifter::Impl::EmitImageMetadata() {
    constexpr std::uint64_t Version = 2, ReservedWords = 9;
    const auto& headers = elf.ProgramHeaders();
    auto* i64 = builder.getInt64Ty();
    auto* headerBytes = llvm::ArrayType::get(builder.getInt8Ty(), headers.size());
    auto* type = llvm::StructType::get(context, {i64, builder.getPtrTy(), llvm::ArrayType::get(i64, ReservedWords), i64, headerBytes}, true);
    auto* loadBias = llvm::ConstantExpr::getGetElementPtr(builder.getInt8Ty(), image, builder.getInt64(0 - imageBegin));
    auto* value = llvm::ConstantStruct::get(type, {builder.getInt64(Version), loadBias, llvm::ConstantAggregateZero::get(llvm::ArrayType::get(i64, ReservedWords)),
                                                   builder.getInt64(headers.size() / 56), llvm::ConstantDataArray::get(context, llvm::ArrayRef<std::uint8_t>(headers))});
    auto* meta = new llvm::GlobalVariable(*module, type, false, llvm::GlobalValue::InternalLinkage, value, "aps5_guest_meta");
    meta->setSection("__APS5DATA,__meta");
    meta->setAlignment(llvm::Align(8));
    llvm::appendToUsed(*module, {meta});
}

Lifter::Lifter(const Elf& elf, llvm::LLVMContext& context) : impl(std::make_unique<Impl>(elf, context)) {}

Lifter::~Lifter() = default;

void Lifter::Discover() {
    auto& lifter = *impl;
    const auto& elf = lifter.elf;
    std::deque<std::uint64_t> pending;
    auto seed = [&](std::uint64_t address) {
        if (elf.InExecutable(address)) pending.push_back(address);
    };
    seed(elf.Entry());
    for (const auto address : elf.InitFunctions()) seed(address);
    for (const auto& symbol : elf.Symbols()) {
        if ((symbol.info & 0xf) == SymbolTypeFunction && symbol.section != 0) seed(symbol.value);
    }
    for (const auto& relocation : elf.Relocations()) {
        if (relocation.type == RelocationRelative) seed(static_cast<std::uint64_t>(relocation.addend));
        if (relocation.type == RelocationAbsolute64 && relocation.symbol < elf.Symbols().size() && elf.Symbols()[relocation.symbol].section != 0)
            seed(elf.Symbols()[relocation.symbol].value + static_cast<std::uint64_t>(relocation.addend));
    }
    while (!pending.empty()) {
        const auto address = pending.front();
        pending.pop_front();
        if (lifter.functions.count(address) == 0) lifter.Explore(address, pending);
    }
    stats.functions = lifter.functions.size();
}

std::unique_ptr<llvm::Module> Lifter::Lift() {
    auto& lifter = *impl;
    if (lifter.functions.empty()) Discover();
    auto module = std::make_unique<llvm::Module>("guest", lifter.context);
    lifter.module = module.get();
    auto& builder = lifter.builder;
    auto* ptr = builder.getPtrTy();
    lifter.callRuntime = module->getOrInsertFunction("aps5_call", llvm::FunctionType::get(builder.getVoidTy(), {ptr, builder.getInt64Ty()}, false));
    for (auto* callee : {&lifter.trapRuntime, &lifter.unsupportedRuntime}) {
        const char* name = callee == &lifter.trapRuntime ? "aps5_trap" : "aps5_unsupported";
        *callee = module->getOrInsertFunction(name, llvm::FunctionType::get(builder.getVoidTy(), {ptr, builder.getInt64Ty()}, false));
        llvm::cast<llvm::Function>(callee->getCallee())->setDoesNotReturn();
    }
    lifter.EmitImage(stats);
    auto* functionType = llvm::FunctionType::get(builder.getVoidTy(), {ptr}, false);
    for (const auto& [entry, addresses] : lifter.functions) {
        auto* function = llvm::Function::Create(functionType, llvm::GlobalValue::InternalLinkage, "g_" + Hex(entry - lifter.imageBegin), module.get());
        // Guest code never holds a pointer to its GuestState, so guest memory accesses cannot alias it.
        function->addParamAttr(0, llvm::Attribute::NoAlias);
        function->setUWTableKind(llvm::UWTableKind::Default);
        function->addFnAttr("frame-pointer", "non-leaf");
        lifter.lifted[entry] = function;
    }
    for (const auto& [entry, addresses] : lifter.functions) lifter.LiftFunction(entry, addresses, stats);
    lifter.EmitTables();
    lifter.EmitImageMetadata();
    lifter.module = nullptr;
    return module;
}

}
