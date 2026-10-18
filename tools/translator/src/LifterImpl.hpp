#ifndef TOOLS_TRANSLATOR_SRC_LIFTERIMPL_HPP
#define TOOLS_TRANSLATOR_SRC_LIFTERIMPL_HPP

// The lifter's internals, shared by the files that lift each instruction group.
#include "Lifter.hpp"

#include "../runtime/GuestState.hpp"

#include <capstone/capstone.h>
#include <llvm/IR/Constants.h>
#include <llvm/IR/DerivedTypes.h>
#include <llvm/IR/Function.h>
#include <llvm/IR/GlobalVariable.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/Intrinsics.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <deque>
#include <functional>
#include <iterator>
#include <optional>
#include <stdexcept>

namespace Translator {

namespace StateLayout = GuestStateLayout;

constexpr std::uint32_t RelocationAbsolute64 = 1, RelocationGlobDat = 6, RelocationJumpSlot = 7, RelocationRelative = 8;
constexpr std::uint8_t SymbolTypeFunction = 2, SymbolBindingWeak = 2;

enum Flag : unsigned { Cf, Pf, Af, Zf, Sf, Of, Df };

enum class Condition { O, No, B, Ae, E, Ne, Be, A, S, Ns, P, Np, L, Ge, Le, G, RcxZero, EcxZero, None };

// An instruction the lifter cannot express. The guest instruction is replaced by a call to aps5_unsupported.
struct Unsupported {
    std::string what;
};

struct Instruction {
    std::uint64_t address = 0;
    std::uint16_t size = 0; // 0: the bytes do not decode
    unsigned id = X86_INS_INVALID;
    std::string mnemonic;
    cs_x86 x86{};

    std::uint64_t Next() const { return address + size; }
    const cs_x86_op& Op(unsigned index) const { return x86.operands[index]; }
    unsigned Bits(unsigned index) const { return x86.operands[index].size * 8u; }
    bool Prefixed(std::uint8_t prefix) const { return std::find(std::begin(x86.prefix), std::end(x86.prefix), prefix) != std::end(x86.prefix); }
    bool Memory(unsigned index) const { return x86.op_count > index && x86.operands[index].type == X86_OP_MEM; }

    std::optional<std::uint64_t> DirectTarget() const {
        if (x86.op_count != 1 || x86.operands[0].type != X86_OP_IMM) return std::nullopt;
        return static_cast<std::uint64_t>(x86.operands[0].imm);
    }
};

struct Register {
    enum Kind { Invalid, Gpr, Vector, Rip } kind = Invalid;
    unsigned index = 0;
    unsigned bits = 0;
    unsigned shift = 0;
};

inline Register RegisterOf(unsigned reg) {
    static const unsigned gpr64[] = {X86_REG_RAX, X86_REG_RCX, X86_REG_RDX, X86_REG_RBX, X86_REG_RSP, X86_REG_RBP, X86_REG_RSI, X86_REG_RDI,
                                     X86_REG_R8,  X86_REG_R9,  X86_REG_R10, X86_REG_R11, X86_REG_R12, X86_REG_R13, X86_REG_R14, X86_REG_R15};
    static const unsigned gpr32[] = {X86_REG_EAX, X86_REG_ECX, X86_REG_EDX,  X86_REG_EBX,  X86_REG_ESP,  X86_REG_EBP,  X86_REG_ESI,  X86_REG_EDI,
                                     X86_REG_R8D, X86_REG_R9D, X86_REG_R10D, X86_REG_R11D, X86_REG_R12D, X86_REG_R13D, X86_REG_R14D, X86_REG_R15D};
    static const unsigned gpr16[] = {X86_REG_AX,  X86_REG_CX,  X86_REG_DX,   X86_REG_BX,   X86_REG_SP,   X86_REG_BP,   X86_REG_SI,   X86_REG_DI,
                                     X86_REG_R8W, X86_REG_R9W, X86_REG_R10W, X86_REG_R11W, X86_REG_R12W, X86_REG_R13W, X86_REG_R14W, X86_REG_R15W};
    static const unsigned gpr8[] = {X86_REG_AL,  X86_REG_CL,  X86_REG_DL,   X86_REG_BL,   X86_REG_SPL,  X86_REG_BPL,  X86_REG_SIL,  X86_REG_DIL,
                                    X86_REG_R8B, X86_REG_R9B, X86_REG_R10B, X86_REG_R11B, X86_REG_R12B, X86_REG_R13B, X86_REG_R14B, X86_REG_R15B};
    static const unsigned high8[] = {X86_REG_AH, X86_REG_CH, X86_REG_DH, X86_REG_BH};
    for (unsigned i = 0; i < 16; ++i) {
        if (reg == gpr64[i]) return {Register::Gpr, i, 64, 0};
        if (reg == gpr32[i]) return {Register::Gpr, i, 32, 0};
        if (reg == gpr16[i]) return {Register::Gpr, i, 16, 0};
        if (reg == gpr8[i]) return {Register::Gpr, i, 8, 0};
    }
    for (unsigned i = 0; i < 4; ++i) {
        if (reg == high8[i]) return {Register::Gpr, i, 8, 8};
    }
    if (reg >= X86_REG_XMM0 && reg <= X86_REG_XMM15) return {Register::Vector, reg - X86_REG_XMM0, 128, 0};
    if (reg >= X86_REG_YMM0 && reg <= X86_REG_YMM15) return {Register::Vector, reg - X86_REG_YMM0, 256, 0};
    if (reg == X86_REG_RIP) return {Register::Rip, 0, 64, 0};
    return {};
}

inline Condition ConditionOf(unsigned id) {
    switch (id) {
    case X86_INS_JO: case X86_INS_SETO: case X86_INS_CMOVO: return Condition::O;
    case X86_INS_JNO: case X86_INS_SETNO: case X86_INS_CMOVNO: return Condition::No;
    case X86_INS_JB: case X86_INS_SETB: case X86_INS_CMOVB: return Condition::B;
    case X86_INS_JAE: case X86_INS_SETAE: case X86_INS_CMOVAE: return Condition::Ae;
    case X86_INS_JE: case X86_INS_SETE: case X86_INS_CMOVE: return Condition::E;
    case X86_INS_JNE: case X86_INS_SETNE: case X86_INS_CMOVNE: return Condition::Ne;
    case X86_INS_JBE: case X86_INS_SETBE: case X86_INS_CMOVBE: return Condition::Be;
    case X86_INS_JA: case X86_INS_SETA: case X86_INS_CMOVA: return Condition::A;
    case X86_INS_JS: case X86_INS_SETS: case X86_INS_CMOVS: return Condition::S;
    case X86_INS_JNS: case X86_INS_SETNS: case X86_INS_CMOVNS: return Condition::Ns;
    case X86_INS_JP: case X86_INS_SETP: case X86_INS_CMOVP: return Condition::P;
    case X86_INS_JNP: case X86_INS_SETNP: case X86_INS_CMOVNP: return Condition::Np;
    case X86_INS_JL: case X86_INS_SETL: case X86_INS_CMOVL: return Condition::L;
    case X86_INS_JGE: case X86_INS_SETGE: case X86_INS_CMOVGE: return Condition::Ge;
    case X86_INS_JLE: case X86_INS_SETLE: case X86_INS_CMOVLE: return Condition::Le;
    case X86_INS_JG: case X86_INS_SETG: case X86_INS_CMOVG: return Condition::G;
    case X86_INS_JRCXZ: return Condition::RcxZero;
    case X86_INS_JECXZ: return Condition::EcxZero;
    default: return Condition::None;
    }
}

inline bool IsConditionalJump(unsigned id) {
    switch (id) {
    case X86_INS_JO: case X86_INS_JNO: case X86_INS_JB: case X86_INS_JAE: case X86_INS_JE: case X86_INS_JNE: case X86_INS_JBE: case X86_INS_JA:
    case X86_INS_JS: case X86_INS_JNS: case X86_INS_JP: case X86_INS_JNP: case X86_INS_JL: case X86_INS_JGE: case X86_INS_JLE: case X86_INS_JG:
    case X86_INS_JRCXZ: case X86_INS_JECXZ:
        return true;
    default:
        return false;
    }
}

// Instructions after which a path through the function does not continue.
inline bool EndsPath(unsigned id) {
    return id == X86_INS_JMP || id == X86_INS_RET || id == X86_INS_UD2 || id == X86_INS_INT3 || id == X86_INS_HLT;
}

inline std::string Hex(std::uint64_t value) {
    char text[24];
    std::snprintf(text, sizeof(text), "%llx", static_cast<unsigned long long>(value));
    return text;
}


struct Lifter::Impl {
    Impl(const Elf& elf, llvm::LLVMContext& context);
    ~Impl() { cs_close(&capstone); }

    const Instruction& Decode(std::uint64_t address);
    void Explore(std::uint64_t entry, std::deque<std::uint64_t>& pending);
    std::vector<std::uint64_t> JumpTable(const std::vector<std::uint64_t>& path, const std::set<std::uint64_t>& function);

    void EmitImage(Statistics& stats);
    llvm::Constant* SlotValue(const Relocation& relocation);
    void EmitTables();
    void EmitImageMetadata();
    void LiftFunction(std::uint64_t entry, const std::set<std::uint64_t>& addresses, Statistics& stats);
    void Emit(const Instruction& instruction);
    void Discard(llvm::BasicBlock* block, std::size_t keepBlocks);

    // Values
    llvm::IntegerType* Int(unsigned bits) { return builder.getIntNTy(bits); }
    llvm::ConstantInt* Const(unsigned bits, std::uint64_t value);
    llvm::Constant* Host(std::uint64_t vaddr);
    llvm::Value* Resize(llvm::Value* value, unsigned bits, bool isSigned = false);
    llvm::Value* Field(unsigned offset) { return builder.CreateConstInBoundsGEP1_64(builder.getInt8Ty(), state, offset); }
    llvm::Value* Gpr64(unsigned index) { return builder.CreateLoad(builder.getInt64Ty(), Field(StateLayout::Gpr + index * 8)); }
    void SetGpr64(unsigned index, llvm::Value* value) { builder.CreateStore(value, Field(StateLayout::Gpr + index * 8)); }
    llvm::Value* ReadPart(unsigned index, unsigned bits, unsigned shift = 0);
    void WritePart(unsigned index, unsigned bits, llvm::Value* value, unsigned shift = 0);
    llvm::Value* ReadRegister(unsigned reg);
    void WriteRegister(unsigned reg, llvm::Value* value, bool vex = false);
    llvm::Value* Pointer(llvm::Value* address) { return builder.CreateIntToPtr(address, builder.getPtrTy()); }
    llvm::Value* Load(llvm::Type* type, llvm::Value* address) { return builder.CreateAlignedLoad(type, Pointer(address), llvm::Align(1)); }
    void Store(llvm::Value* value, llvm::Value* address) { builder.CreateAlignedStore(value, Pointer(address), llvm::Align(1)); }
    llvm::Value* Address(const Instruction& instruction, const x86_op_mem& memory, bool segment = true);
    llvm::Value* Read(const Instruction& instruction, unsigned index, unsigned bits = 0);
    void Write(const Instruction& instruction, unsigned index, llvm::Value* value, bool vex = false);

    // Flags
    llvm::Value* GetFlag(Flag flag) { return builder.CreateICmpNE(builder.CreateLoad(builder.getInt8Ty(), Field(StateLayout::Flags + flag)), builder.getInt8(0)); }
    void SetFlag(Flag flag, llvm::Value* bit) { builder.CreateStore(builder.CreateZExt(bit, builder.getInt8Ty()), Field(StateLayout::Flags + flag)); }
    void ResultFlags(llvm::Value* result);
    void AuxiliaryFlag(llvm::Value* a, llvm::Value* b, llvm::Value* result);
    llvm::Value* Add(llvm::Value* a, llvm::Value* b, llvm::Value* carry);
    llvm::Value* Sub(llvm::Value* a, llvm::Value* b, llvm::Value* borrow);
    llvm::Value* Logic(llvm::Value* result);
    llvm::Value* Test(Condition condition);
    llvm::Value* SignBit(llvm::Value* value) { return builder.CreateICmpSLT(value, llvm::ConstantInt::get(value->getType(), 0)); }

    // Control flow
    void Push(llvm::Value* value);
    llvm::Value* Pop();
    void CallGuest(std::uint64_t target, std::uint64_t returnAddress);
    void CallIndirect(llvm::Value* target, std::uint64_t returnAddress);
    void Jump(std::uint64_t target);
    void JumpIndirect(llvm::Value* target);
    void TailCall(std::uint64_t target);
    void Trap(llvm::FunctionCallee callee, std::uint64_t address);
    llvm::BasicBlock* NewBlock(const char* name) { return llvm::BasicBlock::Create(context, name, current); }
    void BranchIf(llvm::Value* condition, llvm::BasicBlock* taken, llvm::BasicBlock* fallthrough) { builder.CreateCondBr(condition, taken, fallthrough); }

    // Instruction groups
    void Arithmetic(const Instruction& instruction);
    void Unary(const Instruction& instruction);
    void Shift(const Instruction& instruction);
    void Multiply(const Instruction& instruction);
    void Divide(const Instruction& instruction);
    void BitTest(const Instruction& instruction);
    void BitScan(const Instruction& instruction);
    void Exchange(const Instruction& instruction);
    void String(const Instruction& instruction);
    void VectorMove(const Instruction& instruction);
    void VectorLogic(const Instruction& instruction);
    // The SIMD and BMI groups; each returns false for a mnemonic it does not lift.
    bool EmitVectorInteger(const Instruction& instruction); // LiftVector.cpp
    bool EmitVectorFloat(const Instruction& instruction);   // LiftFloat.cpp
    bool EmitBits(const Instruction& instruction);          // LiftBits.cpp

    // Vector helpers (LiftVector.cpp). Registers and memory hold vectors as iN; Lanes views one as
    // N/elementBits lanes of the element type and Flat turns it back.
    llvm::Value* Lanes(llvm::Value* value, llvm::Type* element);
    llvm::Value* Lanes(llvm::Value* value, unsigned elementBits) { return Lanes(value, Int(elementBits)); }
    llvm::Value* Flat(llvm::Value* vector);
    // A shuffle repeated in every 128-bit lane: pick(lane element index, elements per 128 bits)
    // returns the source element within the same 128-bit lane, counting b's elements after a's.
    llvm::Value* LaneShuffle(llvm::Value* a, llvm::Value* b, unsigned elementBits, const std::function<int(unsigned, unsigned)>& pick);
    std::uint64_t Immediate(const Instruction& instruction) const { return static_cast<std::uint64_t>(instruction.Op(instruction.x86.op_count - 1u).imm); }

    const Elf& elf;
    llvm::LLVMContext& context;
    llvm::IRBuilder<> builder;
    csh capstone = 0;
    std::uint64_t imageBegin = 0;
    std::map<std::uint64_t, Instruction> decoded;
    std::map<std::uint64_t, std::set<std::uint64_t>> functions;
    std::map<std::uint64_t, std::set<std::uint64_t>> tableTargets; // per function: its jump table targets

    llvm::Module* module = nullptr;
    llvm::GlobalVariable* image = nullptr;
    std::map<std::uint64_t, llvm::Function*> lifted;
    llvm::FunctionCallee callRuntime, trapRuntime, unsupportedRuntime;

    llvm::Function* current = nullptr;
    std::uint64_t currentEntry = 0;
    llvm::Value* state = nullptr;
    std::map<std::uint64_t, llvm::BasicBlock*> blocks;
    std::set<std::uint64_t> branchTargets;
};

}

#endif
