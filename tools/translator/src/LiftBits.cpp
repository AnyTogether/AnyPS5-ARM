#include "LifterImpl.hpp"

// BMI1/BMI2 and the other general-register bit instructions compilers emit for Zen 2 (the PS5 CPU).

namespace Translator {

bool Lifter::Impl::EmitBits(const Instruction& instruction) {
    const auto& op = instruction.mnemonic;
    const unsigned bits = instruction.x86.op_count != 0 ? instruction.Bits(0) : 64;
    auto zero = [&](llvm::Value* value) { return llvm::ConstantInt::get(value->getType(), 0); };
    // ZF and SF from the result, OF cleared; CF as given.
    auto resultFlags = [&](llvm::Value* result, llvm::Value* carry) {
        SetFlag(Zf, builder.CreateICmpEQ(result, zero(result)));
        SetFlag(Sf, SignBit(result));
        SetFlag(Of, builder.getFalse());
        SetFlag(Cf, carry);
    };

    if (op == "andn") {
        auto* result = builder.CreateAnd(builder.CreateNot(Read(instruction, 1)), Read(instruction, 2, bits));
        resultFlags(result, builder.getFalse());
        Write(instruction, 0, result);
        return true;
    }
    if (op == "bextr") {
        auto* source = Read(instruction, 1, bits);
        auto* control = Resize(Read(instruction, 2), bits);
        auto* start = builder.CreateAnd(control, llvm::ConstantInt::get(control->getType(), 0xff));
        auto* length = builder.CreateAnd(builder.CreateLShr(control, 8), llvm::ConstantInt::get(control->getType(), 0xff));
        auto* width = llvm::ConstantInt::get(control->getType(), bits);
        // Shifts of the full width or more are poison in LLVM, so clamp and select.
        auto* shifted = builder.CreateSelect(builder.CreateICmpUGE(start, width), zero(source), builder.CreateLShr(source, builder.CreateSelect(builder.CreateICmpUGE(start, width), zero(start), start)));
        auto* mask = builder.CreateSelect(builder.CreateICmpUGE(length, width), llvm::ConstantInt::get(source->getType(), ~0ull),
                                          builder.CreateSub(builder.CreateShl(llvm::ConstantInt::get(source->getType(), 1), builder.CreateSelect(builder.CreateICmpUGE(length, width), zero(length), length)), llvm::ConstantInt::get(source->getType(), 1)));
        auto* result = builder.CreateAnd(shifted, mask);
        SetFlag(Zf, builder.CreateICmpEQ(result, zero(result)));
        SetFlag(Cf, builder.getFalse());
        SetFlag(Of, builder.getFalse());
        Write(instruction, 0, result);
        return true;
    }
    if (op == "bzhi") {
        auto* source = Read(instruction, 1, bits);
        auto* index = builder.CreateAnd(Resize(Read(instruction, 2), bits), llvm::ConstantInt::get(source->getType(), 0xff));
        auto* width = llvm::ConstantInt::get(source->getType(), bits);
        auto* saturated = builder.CreateICmpUGE(index, width);
        auto* mask = builder.CreateSub(builder.CreateShl(llvm::ConstantInt::get(source->getType(), 1), builder.CreateSelect(saturated, zero(index), index)), llvm::ConstantInt::get(source->getType(), 1));
        auto* result = builder.CreateSelect(saturated, source, builder.CreateAnd(source, mask));
        resultFlags(result, saturated);
        Write(instruction, 0, result);
        return true;
    }
    if (op == "shlx" || op == "shrx" || op == "sarx") {
        auto* source = Read(instruction, 1, bits);
        auto* count = builder.CreateAnd(Resize(Read(instruction, 2), bits), llvm::ConstantInt::get(source->getType(), bits - 1));
        llvm::Value* result = op == "shlx" ? builder.CreateShl(source, count) : op == "shrx" ? builder.CreateLShr(source, count) : builder.CreateAShr(source, count);
        Write(instruction, 0, result);
        return true;
    }
    if (op == "rorx") {
        auto* source = Read(instruction, 1, bits);
        const auto count = Immediate(instruction) & (bits - 1);
        auto* amount = llvm::ConstantInt::get(source->getType(), count);
        Write(instruction, 0, builder.CreateIntrinsic(llvm::Intrinsic::fshr, {source->getType()}, {source, source, amount}));
        return true;
    }
    if (op == "mulx") {
        // mulx high, low, source: rdx (edx) times source, unsigned; no flags.
        auto* source = Read(instruction, 2, bits);
        auto* product = builder.CreateMul(Resize(ReadPart(Rdx, bits), bits * 2), Resize(source, bits * 2));
        Write(instruction, 1, Resize(product, bits));
        Write(instruction, 0, Resize(builder.CreateLShr(product, bits), bits));
        return true;
    }
    if (op == "blsi" || op == "blsr" || op == "blsmsk") {
        auto* source = Read(instruction, 1, bits);
        auto* one = llvm::ConstantInt::get(source->getType(), 1);
        llvm::Value* result = nullptr;
        llvm::Value* carry = nullptr;
        if (op == "blsi") {
            result = builder.CreateAnd(source, builder.CreateNeg(source));
            carry = builder.CreateICmpNE(source, zero(source));
        } else {
            auto* less = builder.CreateSub(source, one);
            result = op == "blsr" ? builder.CreateAnd(source, less) : builder.CreateXor(source, less);
            carry = builder.CreateICmpEQ(source, zero(source));
        }
        resultFlags(result, carry);
        if (op == "blsmsk") SetFlag(Zf, builder.getFalse());
        Write(instruction, 0, result);
        return true;
    }
    if (op == "pdep" || op == "pext") {
        // Bit by bit over the mask; rare enough that a loop-free unrolled form is fine.
        auto* source = Read(instruction, 1, bits);
        auto* mask = Read(instruction, 2, bits);
        auto* type = source->getType();
        llvm::Value* result = zero(source);
        llvm::Value* cursor = llvm::ConstantInt::get(type, 1); // pdep: next source bit; pext: next result bit
        for (unsigned i = 0; i < bits; ++i) {
            auto* bit = llvm::ConstantInt::get(type, 1ull << i);
            auto* selected = builder.CreateICmpNE(builder.CreateAnd(mask, bit), zero(source));
            llvm::Value* taken = nullptr;
            if (op == "pdep") taken = builder.CreateSelect(builder.CreateICmpNE(builder.CreateAnd(source, cursor), zero(source)), bit, zero(source));
            else taken = builder.CreateSelect(builder.CreateICmpNE(builder.CreateAnd(source, bit), zero(source)), cursor, zero(source));
            result = builder.CreateSelect(selected, builder.CreateOr(result, taken), result);
            cursor = builder.CreateSelect(selected, builder.CreateShl(cursor, 1), cursor);
        }
        Write(instruction, 0, result);
        return true;
    }
    if (op == "movbe") {
        Write(instruction, 0, builder.CreateUnaryIntrinsic(llvm::Intrinsic::bswap, Read(instruction, 1, bits)));
        return true;
    }
    if (op == "clflush" || op == "clflushopt" || op == "clwb") return true;
    return false;
}

}
