#include "LifterImpl.hpp"

#include <cmath>

// Floating-point SSE/AVX instructions: scalar and packed arithmetic, comparisons, conversions and the
// scalar moves. Scalar forms replace the low lane of the first source and keep its other lanes.
// MXCSR rounding control is not modelled: conversions that round use round-to-nearest-even.

namespace Translator {

namespace {

bool StartsWith(const std::string& text, const char* prefix) {
    return text.rfind(prefix, 0) == 0;
}

// The cmpps/cmpss predicates by immediate, as LLVM floating-point predicates.
llvm::CmpInst::Predicate ComparePredicate(unsigned code) {
    switch (code & 0x1f) {
    case 0x00: case 0x10: return llvm::CmpInst::FCMP_OEQ;
    case 0x01: case 0x11: return llvm::CmpInst::FCMP_OLT;
    case 0x02: case 0x12: return llvm::CmpInst::FCMP_OLE;
    case 0x03: case 0x13: return llvm::CmpInst::FCMP_UNO;
    case 0x04: case 0x14: return llvm::CmpInst::FCMP_UNE;
    case 0x05: case 0x15: return llvm::CmpInst::FCMP_UGE;
    case 0x06: case 0x16: return llvm::CmpInst::FCMP_UGT;
    case 0x07: case 0x17: return llvm::CmpInst::FCMP_ORD;
    case 0x08: case 0x18: return llvm::CmpInst::FCMP_UEQ;
    case 0x09: case 0x19: return llvm::CmpInst::FCMP_ULT;
    case 0x0a: case 0x1a: return llvm::CmpInst::FCMP_ULE;
    case 0x0b: case 0x1b: return llvm::CmpInst::FCMP_FALSE;
    case 0x0c: case 0x1c: return llvm::CmpInst::FCMP_ONE;
    case 0x0d: case 0x1d: return llvm::CmpInst::FCMP_OGE;
    case 0x0e: case 0x1e: return llvm::CmpInst::FCMP_OGT;
    default: return llvm::CmpInst::FCMP_TRUE;
    }
}

// Capstone spells the predicate into the mnemonic (cmpltss, vcmpneq_oqpd); -1 when it does not.
int PredicateFromName(const std::string& name) {
    static const char* const names[] = {"eq", "lt", "le", "unord", "neq", "nlt", "nle", "ord", "eq_uq", "nge", "ngt", "false", "neq_oq", "ge", "gt", "true",
                                        "eq_os", "lt_oq", "le_oq", "unord_s", "neq_us", "nlt_uq", "nle_uq", "ord_s", "eq_us", "nge_uq", "ngt_uq", "false_os", "neq_os", "ge_oq", "gt_oq", "true_us"};
    for (int i = 0; i < 32; ++i) {
        if (name == names[i]) return i;
    }
    return -1;
}

}

bool Lifter::Impl::EmitVectorFloat(const Instruction& instruction) {
    const auto& mnemonic = instruction.mnemonic;
    const bool vex = mnemonic.front() == 'v';
    const std::string op = vex ? mnemonic.substr(1) : mnemonic;
    if (op.size() < 4) return false;
    const std::string suffix = op.substr(op.size() - 2);
    const bool scalar = suffix == "ss" || suffix == "sd";
    const bool packed = suffix == "ps" || suffix == "pd";
    llvm::Type* element = suffix[1] == 's' ? builder.getFloatTy() : builder.getDoubleTy();
    const unsigned elementBits = suffix[1] == 's' ? 32 : 64;
    const std::string stem = op.substr(0, op.size() - 2);
    auto write = [&](llvm::Value* value) { Write(instruction, 0, value, vex); };
    auto first = [&]() { return Read(instruction, vex ? 1 : 0); };
    auto secondIndex = [&]() { return vex ? 2u : 1u; };
    // The low lane of an operand that may be memory of the element size.
    auto scalarOf = [&](unsigned index, unsigned bits, llvm::Type* type) {
        return builder.CreateBitCast(Resize(Read(instruction, index, bits), bits), type);
    };
    auto replaceLow = [&](llvm::Value* base, llvm::Value* low) {
        auto* lanes = Lanes(base, low->getType());
        return Flat(builder.CreateInsertElement(lanes, low, static_cast<std::uint64_t>(0)));
    };
    auto arithmetic = [&](const std::string& name, llvm::Value* a, llvm::Value* b) -> llvm::Value* {
        if (name == "add") return builder.CreateFAdd(a, b);
        if (name == "sub") return builder.CreateFSub(a, b);
        if (name == "mul") return builder.CreateFMul(a, b);
        if (name == "div") return builder.CreateFDiv(a, b);
        // minss/maxss return the second source when either is NaN or both are zero.
        if (name == "min") return builder.CreateSelect(builder.CreateFCmpOLT(a, b), a, b);
        if (name == "max") return builder.CreateSelect(builder.CreateFCmpOGT(a, b), a, b);
        return nullptr;
    };

    if ((scalar || packed) && (stem == "add" || stem == "sub" || stem == "mul" || stem == "div" || stem == "min" || stem == "max")) {
        if (scalar) {
            auto* base = first();
            auto* a = builder.CreateBitCast(Resize(base, elementBits), element);
            auto* b = scalarOf(secondIndex(), elementBits, element);
            write(replaceLow(base, arithmetic(stem, a, b)));
        } else {
            auto* a = Lanes(first(), element);
            auto* b = Lanes(Read(instruction, secondIndex()), element);
            write(Flat(arithmetic(stem, a, b)));
        }
        return true;
    }
    // FMA3: vfmadd132 a, b, c = a*c + b; 213 = b*a + c; 231 = b*c + a. msub subtracts the addend,
    // nmadd negates the product, nmsub both. Fused, like the hardware.
    if ((scalar || packed) && vex && (StartsWith(op, "fmadd") || StartsWith(op, "fmsub") || StartsWith(op, "fnmadd") || StartsWith(op, "fnmsub")) &&
        op.size() >= 10) {
        const bool negateProduct = op[1] == 'n';
        const std::string form = op.substr(negateProduct ? 6 : 5, 3);
        const bool subtract = op.substr(negateProduct ? 2 : 1, 3) == "msu";
        if (form != "132" && form != "213" && form != "231") return false;
        auto operand = [&](unsigned index) -> llvm::Value* {
            if (scalar) return scalarOf(index, elementBits, element);
            return Lanes(Read(instruction, index), element);
        };
        auto* a = operand(0);
        auto* b = operand(1);
        auto* c = operand(2);
        llvm::Value *x = nullptr, *y = nullptr, *z = nullptr;
        if (form == "132") x = a, y = c, z = b;
        else if (form == "213") x = b, y = a, z = c;
        else x = b, y = c, z = a;
        if (negateProduct) x = builder.CreateFNeg(x);
        if (subtract) z = builder.CreateFNeg(z);
        auto* result = builder.CreateIntrinsic(llvm::Intrinsic::fma, {x->getType()}, {x, y, z});
        if (scalar) write(replaceLow(Read(instruction, 0), result));
        else write(Flat(result));
        return true;
    }
    if ((scalar || packed) && (stem == "rcp" || stem == "rsqrt")) {
        // Exact results where x86 gives 12-bit approximations; titles only rely on the approximation bound.
        auto approximate = [&](llvm::Value* value) -> llvm::Value* {
            if (stem == "rsqrt") value = builder.CreateUnaryIntrinsic(llvm::Intrinsic::sqrt, value);
            return builder.CreateFDiv(llvm::ConstantFP::get(value->getType(), 1.0), value);
        };
        if (scalar) {
            auto* base = vex ? Read(instruction, 1) : Read(instruction, 0);
            write(replaceLow(base, approximate(scalarOf(vex ? 2 : 1, elementBits, element))));
        } else {
            write(Flat(approximate(Lanes(Read(instruction, 1), element))));
        }
        return true;
    }
    if ((scalar || packed) && stem == "sqrt") {
        if (scalar) {
            // sqrtsd dst, src (SSE: the other lanes of dst stay) / vsqrtsd dst, src1, src2.
            auto* base = vex ? Read(instruction, 1) : Read(instruction, 0);
            auto* value = scalarOf(vex ? 2 : 1, elementBits, element);
            write(replaceLow(base, builder.CreateUnaryIntrinsic(llvm::Intrinsic::sqrt, value)));
        } else {
            write(Flat(builder.CreateUnaryIntrinsic(llvm::Intrinsic::sqrt, Lanes(Read(instruction, 1), element))));
        }
        return true;
    }
    if ((scalar || packed) && (stem == "round")) {
        // Bit 2 selects the MXCSR rounding mode, which is taken as round-to-nearest-even.
        const auto control = Immediate(instruction);
        const auto mode = (control & 4) != 0 ? 0 : control & 3;
        const auto id = mode == 0 ? llvm::Intrinsic::roundeven : mode == 1 ? llvm::Intrinsic::floor : mode == 2 ? llvm::Intrinsic::ceil : llvm::Intrinsic::trunc;
        if (scalar) {
            auto* base = vex ? Read(instruction, 1) : Read(instruction, 0);
            auto* value = scalarOf(vex ? 2 : 1, elementBits, element);
            write(replaceLow(base, builder.CreateUnaryIntrinsic(id, value)));
        } else {
            write(Flat(builder.CreateUnaryIntrinsic(id, Lanes(Read(instruction, 1), element))));
        }
        return true;
    }
    if (op == "ucomiss" || op == "ucomisd" || op == "comiss" || op == "comisd") {
        llvm::Type* type = op.back() == 's' ? builder.getFloatTy() : builder.getDoubleTy();
        const unsigned bits = op.back() == 's' ? 32 : 64;
        auto* a = scalarOf(0, bits, type);
        auto* b = scalarOf(1, bits, type);
        auto* unordered = builder.CreateFCmpUNO(a, b);
        SetFlag(Zf, builder.CreateFCmpUEQ(a, b));
        SetFlag(Pf, unordered);
        SetFlag(Cf, builder.CreateFCmpULT(a, b));
        for (auto flag : {Of, Sf, Af}) SetFlag(flag, builder.getFalse());
        return true;
    }
    if (StartsWith(op, "cmp") && (scalar || packed)) {
        int code = PredicateFromName(stem.substr(3));
        if (stem == "cmp") code = static_cast<int>(Immediate(instruction) & 0x1f);
        if (code < 0) return false;
        const auto predicate = ComparePredicate(static_cast<unsigned>(code));
        auto compare = [&](llvm::Value* a, llvm::Value* b) {
            auto* result = builder.CreateFCmp(predicate, a, b);
            auto* integer = llvm::isa<llvm::VectorType>(a->getType()) ? llvm::VectorType::getInteger(llvm::cast<llvm::VectorType>(a->getType())) : static_cast<llvm::Type*>(Int(elementBits));
            return builder.CreateSExt(result, integer);
        };
        if (scalar) {
            auto* base = first();
            auto* a = builder.CreateBitCast(Resize(base, elementBits), element);
            auto* b = scalarOf(secondIndex(), elementBits, element);
            auto* lanes = Lanes(base, elementBits);
            write(Flat(builder.CreateInsertElement(lanes, compare(a, b), static_cast<std::uint64_t>(0))));
        } else {
            write(Flat(compare(Lanes(first(), element), Lanes(Read(instruction, secondIndex()), element))));
        }
        return true;
    }

    // Scalar moves: movss/movsd load (zeroing the rest), store, or merge two registers.
    if (op == "movss" || op == "movsd") {
        const unsigned bits = op == "movss" ? 32 : 64;
        if (instruction.Memory(0)) {
            Store(Resize(Read(instruction, 1), bits), Address(instruction, instruction.Op(0).mem));
        } else if (instruction.Memory(1)) {
            Write(instruction, 0, Resize(Read(instruction, 1, bits), 128), vex);
        } else {
            auto* base = first();
            auto* low = Resize(Read(instruction, vex ? 2 : 1), bits);
            auto* lanes = Lanes(base, bits);
            write(Flat(builder.CreateInsertElement(lanes, low, static_cast<std::uint64_t>(0))));
        }
        return true;
    }
    if (op == "movhps" || op == "movhpd" || op == "movlps" || op == "movlpd") {
        const bool high = op[3] == 'h';
        if (instruction.Memory(0)) {
            auto* source = Read(instruction, 1);
            Store(Resize(high ? builder.CreateLShr(source, 64) : source, 64), Address(instruction, instruction.Op(0).mem));
        } else {
            auto* lanes = Lanes(first(), 64);
            auto* value = Resize(Read(instruction, vex ? 2 : 1, 64), 64);
            write(Flat(builder.CreateInsertElement(lanes, value, static_cast<std::uint64_t>(high ? 1 : 0))));
        }
        return true;
    }

    // Conversions.
    if (op == "cvtsi2ss" || op == "cvtsi2sd") {
        llvm::Type* type = op.back() == 's' ? builder.getFloatTy() : builder.getDoubleTy();
        auto* base = first();
        auto* integer = Read(instruction, secondIndex());
        write(replaceLow(base, builder.CreateSIToFP(integer, type)));
        return true;
    }
    if (op == "cvtss2sd" || op == "cvtsd2ss") {
        const bool widen = op == "cvtss2sd";
        llvm::Type* from = widen ? builder.getFloatTy() : builder.getDoubleTy();
        llvm::Type* to = widen ? builder.getDoubleTy() : builder.getFloatTy();
        auto* base = first();
        auto* value = scalarOf(secondIndex(), widen ? 32 : 64, from);
        write(replaceLow(base, widen ? builder.CreateFPExt(value, to) : builder.CreateFPTrunc(value, to)));
        return true;
    }
    if (op == "cvttss2si" || op == "cvttsd2si" || op == "cvtss2si" || op == "cvtsd2si") {
        const bool truncate = op[3] == 't';
        const bool single = op[truncate ? 5 : 4] == 's';
        llvm::Type* type = single ? builder.getFloatTy() : builder.getDoubleTy();
        const unsigned bits = instruction.Bits(0);
        llvm::Value* value = scalarOf(1, single ? 32 : 64, type);
        if (!truncate) value = builder.CreateUnaryIntrinsic(llvm::Intrinsic::roundeven, value);
        // Out of range and NaN give the "integer indefinite" value, INT_MIN.
        auto* converted = builder.CreateIntrinsic(llvm::Intrinsic::fptosi_sat, {Int(bits), type}, {value});
        const double limit = std::ldexp(1.0, static_cast<int>(bits) - 1);
        auto* inRange = builder.CreateAnd(builder.CreateFCmpOGE(value, llvm::ConstantFP::get(type, -limit)), builder.CreateFCmpOLT(value, llvm::ConstantFP::get(type, limit)));
        Write(instruction, 0, builder.CreateSelect(inRange, converted, Const(bits, 1ull << (bits - 1))));
        return true;
    }
    if (op == "cvtdq2ps" || op == "cvtdq2pd" || op == "cvtps2pd" || op == "cvtpd2ps" || op == "cvttps2dq" || op == "cvttpd2dq" || op == "cvtps2dq" || op == "cvtpd2dq") {
        const unsigned bits = instruction.Bits(0);
        const std::string from = op.substr(op.find("cvt") + (op[3] == 't' ? 4 : 3), 2), to = op.substr(op.size() - 2);
        auto typeOf = [&](const std::string& kind) -> llvm::Type* { return kind == "ps" ? builder.getFloatTy() : kind == "pd" ? builder.getDoubleTy() : static_cast<llvm::Type*>(builder.getInt32Ty()); };
        auto widthOf = [](const std::string& kind) { return kind == "pd" ? 64u : 32u; };
        llvm::Type* fromType = typeOf(from);
        llvm::Type* toType = typeOf(to);
        // The lane count follows the wider side: cvtpd2ps ymm -> xmm converts 4 lanes.
        unsigned lanes = bits / widthOf(to);
        if (widthOf(from) > widthOf(to)) lanes = instruction.Bits(1) / widthOf(from);
        auto* source = Lanes(Resize(Read(instruction, 1), lanes * widthOf(from)), fromType);
        auto* target = llvm::FixedVectorType::get(toType, lanes);
        llvm::Value* result = nullptr;
        if (from == "dq") result = builder.CreateSIToFP(source, target);
        else if (to == "dq") {
            llvm::Value* value = source;
            if (op[3] != 't') value = builder.CreateUnaryIntrinsic(llvm::Intrinsic::roundeven, value);
            auto* converted = builder.CreateIntrinsic(llvm::Intrinsic::fptosi_sat, {target, source->getType()}, {value});
            auto* limit = llvm::ConstantFP::get(source->getType(), 2147483648.0);
            auto* inRange = builder.CreateAnd(builder.CreateFCmpOGE(value, llvm::ConstantFP::get(source->getType(), -2147483648.0)), builder.CreateFCmpOLT(value, limit));
            result = builder.CreateSelect(inRange, converted, llvm::ConstantInt::get(target, 0x80000000u));
        } else if (from == "ps") result = builder.CreateFPExt(source, target);
        else result = builder.CreateFPTrunc(source, target);
        Write(instruction, 0, Resize(Flat(result), bits), vex);
        return true;
    }
    return false;
}

}
