#include "LifterImpl.hpp"

#include <llvm/IR/IntrinsicsAArch64.h>

// Integer SSE/AVX/AVX2 instructions, plus the shuffles, blends, broadcasts and lane moves that
// treat lanes as plain bits. SSE forms are "dst, src" (dst is also the first source); VEX forms are
// "dst, src1, src2". 128-bit VEX writes zero bits 128-255, SSE writes keep them.

namespace Translator {

namespace {

unsigned Width(char suffix) {
    switch (suffix) {
    case 'b': return 8;
    case 'w': return 16;
    case 'd': return 32;
    case 'q': return 64;
    default: throw Unsupported{std::string("element suffix ") + suffix};
    }
}

bool StartsWith(const std::string& text, const char* prefix) {
    return text.rfind(prefix, 0) == 0;
}

}

llvm::Value* Lifter::Impl::Lanes(llvm::Value* value, llvm::Type* element) {
    const auto bits = value->getType()->getPrimitiveSizeInBits().getFixedValue();
    const auto elementBits = element->getPrimitiveSizeInBits().getFixedValue();
    return builder.CreateBitCast(value, llvm::FixedVectorType::get(element, static_cast<unsigned>(bits / elementBits)));
}

llvm::Value* Lifter::Impl::Flat(llvm::Value* vector) {
    return builder.CreateBitCast(vector, Int(static_cast<unsigned>(vector->getType()->getPrimitiveSizeInBits().getFixedValue())));
}

// pick returns -1 for a zero element.
llvm::Value* Lifter::Impl::LaneShuffle(llvm::Value* a, llvm::Value* b, unsigned elementBits, const std::function<int(unsigned, unsigned)>& pick) {
    const auto bits = static_cast<unsigned>(a->getType()->getPrimitiveSizeInBits().getFixedValue());
    const unsigned count = bits / elementBits, perLane = 128 / elementBits;
    std::vector<int> mask;
    std::vector<llvm::Constant*> keep;
    bool zeroes = false;
    for (unsigned i = 0; i < count; ++i) {
        const unsigned base = i / perLane * perLane;
        const int chosen = pick(i % perLane, perLane);
        zeroes |= chosen < 0;
        keep.push_back(builder.getInt1(chosen >= 0));
        if (chosen < 0) mask.push_back(0);
        else if (static_cast<unsigned>(chosen) < perLane) mask.push_back(static_cast<int>(base) + chosen);
        else mask.push_back(static_cast<int>(count + base) + chosen - static_cast<int>(perLane));
    }
    llvm::Value* result = builder.CreateShuffleVector(Lanes(a, elementBits), Lanes(b, elementBits), mask);
    if (zeroes) result = builder.CreateSelect(llvm::ConstantVector::get(keep), result, llvm::Constant::getNullValue(result->getType()));
    return Flat(result);
}

bool Lifter::Impl::EmitVectorInteger(const Instruction& instruction) {
    const auto& mnemonic = instruction.mnemonic;
    const bool vex = mnemonic.front() == 'v';
    const std::string op = vex ? mnemonic.substr(1) : mnemonic;
    const unsigned operands = instruction.x86.op_count;
    const bool immediate = operands != 0 && instruction.Op(operands - 1).type == X86_OP_IMM;
    auto first = [&]() { return Read(instruction, vex ? 1 : 0); };
    auto second = [&]() { return Read(instruction, vex ? 2 : 1); };
    auto write = [&](llvm::Value* value) { Write(instruction, 0, value, vex); };
    auto lanewise = [&](unsigned bits, const std::function<llvm::Value*(llvm::Value*, llvm::Value*)>& compute) {
        auto* a = Lanes(first(), bits);
        auto* b = Lanes(second(), bits);
        write(Flat(compute(a, b)));
    };
    auto intrinsic = [&](llvm::Intrinsic::ID id) { return [this, id](llvm::Value* a, llvm::Value* b) { return builder.CreateBinaryIntrinsic(id, a, b); }; };
    auto splat = [&](llvm::Value* vector, std::uint64_t value) {
        return llvm::ConstantInt::get(vector->getType(), value);
    };

    // Lane arithmetic.
    if (op.size() == 5 && (StartsWith(op, "padd") || StartsWith(op, "psub"))) {
        const bool add = op[1] == 'a';
        lanewise(Width(op[4]), [&](llvm::Value* a, llvm::Value* b) { return add ? builder.CreateAdd(a, b) : builder.CreateSub(a, b); });
        return true;
    }
    if (op == "paddsb" || op == "paddsw" || op == "paddusb" || op == "paddusw" || op == "psubsb" || op == "psubsw" || op == "psubusb" || op == "psubusw") {
        const bool add = op[1] == 'a', unsignedSat = op[4] == 'u';
        const auto id = add ? (unsignedSat ? llvm::Intrinsic::uadd_sat : llvm::Intrinsic::sadd_sat) : (unsignedSat ? llvm::Intrinsic::usub_sat : llvm::Intrinsic::ssub_sat);
        lanewise(Width(op.back()), intrinsic(id));
        return true;
    }
    if (op == "pmulld" || op == "pmullw") {
        lanewise(Width(op.back()), [&](llvm::Value* a, llvm::Value* b) { return builder.CreateMul(a, b); });
        return true;
    }
    if (op == "pmulhw" || op == "pmulhuw") {
        const bool isSigned = op == "pmulhw";
        lanewise(16, [&](llvm::Value* a, llvm::Value* b) {
            auto* wide = llvm::FixedVectorType::get(Int(32), llvm::cast<llvm::FixedVectorType>(a->getType())->getNumElements());
            auto* product = builder.CreateMul(isSigned ? builder.CreateSExt(a, wide) : builder.CreateZExt(a, wide), isSigned ? builder.CreateSExt(b, wide) : builder.CreateZExt(b, wide));
            return builder.CreateTrunc(builder.CreateLShr(product, 16), a->getType());
        });
        return true;
    }
    if (op == "pmaddwd") {
        lanewise(16, [&](llvm::Value* a, llvm::Value* b) {
            const unsigned count = llvm::cast<llvm::FixedVectorType>(a->getType())->getNumElements();
            auto* wide = llvm::FixedVectorType::get(Int(32), count);
            auto* product = builder.CreateMul(builder.CreateSExt(a, wide), builder.CreateSExt(b, wide));
            std::vector<int> evens, odds;
            for (unsigned i = 0; i < count / 2; ++i) {
                evens.push_back(static_cast<int>(2 * i));
                odds.push_back(static_cast<int>(2 * i + 1));
            }
            return builder.CreateAdd(builder.CreateShuffleVector(product, evens), builder.CreateShuffleVector(product, odds));
        });
        return true;
    }
    if (op == "pmuldq" || op == "pmuludq") {
        const bool isSigned = op == "pmuldq";
        lanewise(64, [&](llvm::Value* a, llvm::Value* b) {
            auto low = [&](llvm::Value* value) { return isSigned ? builder.CreateAShr(builder.CreateShl(value, splat(value, 32)), splat(value, 32)) : builder.CreateAnd(value, splat(value, 0xffffffffull)); };
            return builder.CreateMul(low(a), low(b));
        });
        return true;
    }
    if ((StartsWith(op, "pmin") || StartsWith(op, "pmax")) && op.size() == 6) {
        const bool min = op[3] == 'n', isSigned = op[4] == 's';
        const auto id = min ? (isSigned ? llvm::Intrinsic::smin : llvm::Intrinsic::umin) : (isSigned ? llvm::Intrinsic::smax : llvm::Intrinsic::umax);
        lanewise(Width(op[5]), intrinsic(id));
        return true;
    }
    if (op == "pabsb" || op == "pabsw" || op == "pabsd") {
        auto* a = Lanes(Read(instruction, 1), Width(op.back()));
        write(Flat(builder.CreateBinaryIntrinsic(llvm::Intrinsic::abs, a, builder.getFalse())));
        return true;
    }
    if (op == "pavgb" || op == "pavgw") {
        lanewise(Width(op.back()), [&](llvm::Value* a, llvm::Value* b) {
            auto* vector = llvm::cast<llvm::FixedVectorType>(a->getType());
            auto* wide = llvm::FixedVectorType::get(Int(vector->getScalarSizeInBits() * 2), vector->getNumElements());
            auto* sum = builder.CreateAdd(builder.CreateAdd(builder.CreateZExt(a, wide), builder.CreateZExt(b, wide)), llvm::ConstantInt::get(wide, 1));
            return builder.CreateTrunc(builder.CreateLShr(sum, llvm::ConstantInt::get(wide, 1)), vector);
        });
        return true;
    }
    if (op.size() == 7 && (StartsWith(op, "pcmpeq") || StartsWith(op, "pcmpgt"))) {
        const bool equal = op[5] == 'q';
        lanewise(Width(op[6]), [&](llvm::Value* a, llvm::Value* b) {
            return builder.CreateSExt(equal ? builder.CreateICmpEQ(a, b) : builder.CreateICmpSGT(a, b), a->getType());
        });
        return true;
    }
    if (op == "phaddw" || op == "phaddd" || op == "phsubw" || op == "phsubd") {
        const unsigned bits = Width(op.back());
        auto* a = first();
        auto* b = second();
        auto pairs = [&](int offset) {
            return LaneShuffle(a, b, bits, [offset](unsigned j, unsigned perLane) {
                const unsigned half = perLane / 2;
                return static_cast<int>(j < half ? 2 * j : perLane + 2 * (j - half)) + offset;
            });
        };
        auto* even = Lanes(pairs(0), bits);
        auto* odd = Lanes(pairs(1), bits);
        write(Flat(op[2] == 'a' ? builder.CreateAdd(even, odd) : builder.CreateSub(even, odd)));
        return true;
    }
    if (op == "packsswb" || op == "packssdw" || op == "packuswb" || op == "packusdw") {
        const unsigned from = op.back() == 'b' ? 16 : 32, to = from / 2;
        const bool isSigned = op[4] == 's';
        auto saturate = [&](llvm::Value* value) {
            auto* lanes = Lanes(value, from);
            const auto low = isSigned ? llvm::APInt::getSignedMinValue(to).sext(from) : llvm::APInt(from, 0);
            const auto high = isSigned ? llvm::APInt::getSignedMaxValue(to).sext(from) : llvm::APInt::getMaxValue(to).zext(from);
            auto* clamped = builder.CreateBinaryIntrinsic(llvm::Intrinsic::smax, lanes, llvm::ConstantInt::get(lanes->getType(), low));
            clamped = builder.CreateBinaryIntrinsic(llvm::Intrinsic::smin, clamped, llvm::ConstantInt::get(lanes->getType(), high));
            const unsigned count = llvm::cast<llvm::FixedVectorType>(lanes->getType())->getNumElements();
            return builder.CreateTrunc(clamped, llvm::FixedVectorType::get(Int(to), count));
        };
        auto* a = saturate(first());
        auto* b = saturate(second());
        const unsigned half = llvm::cast<llvm::FixedVectorType>(a->getType())->getNumElements();
        const unsigned perLane = 128 / to, laneHalf = perLane / 2;
        std::vector<int> mask;
        for (unsigned i = 0; i < half * 2; ++i) {
            const unsigned lane = i / perLane, j = i % perLane;
            mask.push_back(static_cast<int>(j < laneHalf ? lane * laneHalf + j : half + lane * laneHalf + j - laneHalf));
        }
        write(Flat(builder.CreateShuffleVector(a, b, mask)));
        return true;
    }

    // Unpacks and shuffles.
    if (StartsWith(op, "punpck") || op == "unpcklps" || op == "unpckhps" || op == "unpcklpd" || op == "unpckhpd") {
        unsigned bits = 0;
        bool high = false;
        if (op[0] == 'p') {
            high = op[6] == 'h';
            const auto suffix = op.substr(7);
            bits = suffix == "bw" ? 8 : suffix == "wd" ? 16 : suffix == "dq" ? 32 : suffix == "qdq" ? 64 : 0;
            if (bits == 0) return false;
        } else {
            high = op[5] == 'h';
            bits = op.back() == 's' ? 32 : 64;
        }
        write(LaneShuffle(first(), second(), bits, [high](unsigned j, unsigned perLane) {
            const unsigned source = j / 2 + (high ? perLane / 2 : 0);
            return static_cast<int>(j % 2 == 0 ? source : perLane + source);
        }));
        return true;
    }
    if (op == "pshufd" || op == "pshuflw" || op == "pshufhw") {
        const auto control = Immediate(instruction);
        auto* source = Read(instruction, 1);
        if (op == "pshufd") {
            write(LaneShuffle(source, source, 32, [control](unsigned j, unsigned) { return static_cast<int>((control >> (2 * j)) & 3); }));
        } else {
            const bool high = op == "pshufhw";
            write(LaneShuffle(source, source, 16, [control, high](unsigned j, unsigned) {
                const unsigned base = high ? 4 : 0;
                if (j < base || j >= base + 4) return static_cast<int>(j);
                return static_cast<int>(base + ((control >> (2 * (j - base))) & 3));
            }));
        }
        return true;
    }
    if (op == "pshufb") {
        auto* table = first();
        auto* indices = second();
        const auto bits = static_cast<unsigned>(table->getType()->getIntegerBitWidth());
        llvm::Value* result = nullptr;
        // tbl yields 0 for indices of 16 and more, so keeping bit 7 zeroes the lanes x86 zeroes.
        for (unsigned half = 0; half < bits / 128; ++half) {
            auto* t = Lanes(Resize(builder.CreateLShr(table, half * 128), 128), 8);
            auto* i = Lanes(Resize(builder.CreateLShr(indices, half * 128), 128), 8);
            i = builder.CreateAnd(i, llvm::ConstantInt::get(i->getType(), 0x8f));
            auto* picked = Resize(Flat(builder.CreateIntrinsic(llvm::Intrinsic::aarch64_neon_tbl1, {i->getType()}, {t, i})), bits);
            picked = builder.CreateShl(picked, half * 128);
            result = result ? builder.CreateOr(result, picked) : picked;
        }
        write(result);
        return true;
    }
    if (op == "palignr") {
        const auto shift = static_cast<unsigned>(Immediate(instruction));
        // Bytes of b (low) then a (high), shifted right by the immediate within each 128-bit lane.
        write(LaneShuffle(second(), first(), 8, [shift](unsigned j, unsigned) { return j + shift < 32 ? static_cast<int>(j + shift) : -1; }));
        return true;
    }
    if (op == "pslldq" || op == "psrldq") {
        const auto shift = static_cast<unsigned>(Immediate(instruction));
        const bool left = op[2] == 'l';
        auto* source = Read(instruction, vex ? 1 : 0);
        auto* zero = llvm::Constant::getNullValue(source->getType());
        write(LaneShuffle(source, zero, 8, [shift, left](unsigned j, unsigned) {
            if (left) return j >= shift ? static_cast<int>(j - shift) : -1;
            return j + shift < 16 ? static_cast<int>(j + shift) : -1;
        }));
        return true;
    }
    if (op == "shufps" || op == "shufpd") {
        const auto control = Immediate(instruction);
        if (op == "shufps") {
            write(LaneShuffle(first(), second(), 32, [control](unsigned j, unsigned perLane) {
                const auto selected = static_cast<unsigned>((control >> (2 * j)) & 3);
                return static_cast<int>(j < 2 ? selected : perLane + selected);
            }));
        } else {
            auto* a = Lanes(first(), 64);
            auto* b = Lanes(second(), 64);
            const unsigned count = llvm::cast<llvm::FixedVectorType>(a->getType())->getNumElements();
            std::vector<int> mask;
            for (unsigned i = 0; i < count; ++i) {
                const unsigned base = i / 2 * 2, bit = (control >> i) & 1;
                mask.push_back(static_cast<int>(i % 2 == 0 ? base + bit : count + base + bit));
            }
            write(Flat(builder.CreateShuffleVector(a, b, mask)));
        }
        return true;
    }
    if (op == "movlhps" || op == "movhlps") {
        const bool toHigh = op == "movlhps";
        write(LaneShuffle(first(), second(), 64, [toHigh](unsigned j, unsigned) {
            if (toHigh) return j == 0 ? 0 : 2;
            return j == 0 ? 3 : 1;
        }));
        return true;
    }
    if (op == "movshdup" || op == "movsldup") {
        const int odd = op == "movshdup" ? 1 : 0;
        auto* source = Read(instruction, 1);
        write(LaneShuffle(source, source, 32, [odd](unsigned j, unsigned) { return static_cast<int>(j / 2 * 2) + odd; }));
        return true;
    }
    if (op == "movddup") {
        const auto bits = instruction.Bits(0);
        auto* source = Read(instruction, 1);
        if (instruction.Memory(1) && bits == 128) source = Resize(source, 128);
        write(LaneShuffle(source, source, 64, [](unsigned, unsigned) { return 0; }));
        return true;
    }
    if (op == "insertps") {
        const auto control = Immediate(instruction);
        auto* base = Lanes(first(), 32);
        llvm::Value* element = nullptr;
        const unsigned sourceIndex = vex ? 2 : 1;
        if (instruction.Memory(sourceIndex)) element = Read(instruction, sourceIndex, 32);
        else element = builder.CreateExtractElement(Lanes(Read(instruction, sourceIndex), 32), static_cast<std::uint64_t>((control >> 6) & 3));
        llvm::Value* result = builder.CreateInsertElement(base, Resize(element, 32), static_cast<std::uint64_t>((control >> 4) & 3));
        for (unsigned i = 0; i < 4; ++i) {
            if ((control >> i) & 1) result = builder.CreateInsertElement(result, builder.getInt32(0), static_cast<std::uint64_t>(i));
        }
        write(Flat(result));
        return true;
    }

    // Blends.
    if (op == "pblendw" || op == "pblendd" || op == "blendps" || op == "blendpd") {
        const auto control = Immediate(instruction);
        const unsigned bits = op == "pblendw" ? 16 : op == "blendpd" ? 64 : 32;
        auto* a = Lanes(first(), bits);
        auto* b = Lanes(second(), bits);
        const unsigned count = llvm::cast<llvm::FixedVectorType>(a->getType())->getNumElements();
        std::vector<int> mask;
        for (unsigned i = 0; i < count; ++i) {
            const unsigned bit = bits == 16 ? i % 8 : i;
            mask.push_back(static_cast<int>((control >> bit) & 1 ? count + i : i));
        }
        write(Flat(builder.CreateShuffleVector(a, b, mask)));
        return true;
    }
    if (op == "pblendvb" || op == "blendvps" || op == "blendvpd") {
        const unsigned bits = op == "pblendvb" ? 8 : op == "blendvps" ? 32 : 64;
        auto* a = Lanes(first(), bits);
        auto* b = Lanes(second(), bits);
        llvm::Value* selector = vex ? Read(instruction, 3) : builder.CreateLoad(Int(128), Field(StateLayout::Ymm));
        auto* chosen = builder.CreateICmpSLT(Lanes(Resize(selector, static_cast<unsigned>(a->getType()->getPrimitiveSizeInBits().getFixedValue())), bits), llvm::Constant::getNullValue(a->getType()));
        write(Flat(builder.CreateSelect(chosen, b, a)));
        return true;
    }

    // Shifts: by an immediate, by the low 64 bits of a vector, or per lane (the v forms).
    const bool variableShift = op == "psllvd" || op == "psllvq" || op == "psrlvd" || op == "psrlvq" || op == "psravd";
    if (variableShift || ((StartsWith(op, "psll") || StartsWith(op, "psrl") || StartsWith(op, "psra")) && op.size() == 5)) {
        const unsigned bits = Width(op.back());
        const bool left = op[2] == 'l' && op[3] == 'l', arithmetic = op[3] == 'a';
        auto* value = Lanes(Read(instruction, vex ? 1 : 0), bits);
        llvm::Value* counts = nullptr;
        if (variableShift) {
            counts = Lanes(Read(instruction, 2), bits);
        } else {
            llvm::Value* count = immediate ? static_cast<llvm::Value*>(builder.getInt64(Immediate(instruction))) : Resize(Read(instruction, vex ? 2 : 1), 64);
            const unsigned lanes = llvm::cast<llvm::FixedVectorType>(value->getType())->getNumElements();
            count = builder.CreateSelect(builder.CreateICmpUGT(count, builder.getInt64(bits)), builder.getInt64(bits), count);
            counts = builder.CreateVectorSplat(lanes, Resize(count, bits));
        }
        auto* limit = splat(value, bits);
        auto* tooFar = builder.CreateICmpUGE(counts, limit);
        auto* clamped = builder.CreateSelect(tooFar, splat(value, bits - 1), counts);
        llvm::Value* result = nullptr;
        if (arithmetic) result = builder.CreateAShr(value, clamped);
        else result = builder.CreateSelect(tooFar, llvm::Constant::getNullValue(value->getType()), left ? builder.CreateShl(value, clamped) : builder.CreateLShr(value, clamped));
        write(Flat(result));
        return true;
    }

    // Broadcasts and widening moves.
    if (op == "pbroadcastb" || op == "pbroadcastw" || op == "pbroadcastd" || op == "pbroadcastq" || op == "broadcastss" || op == "broadcastsd") {
        const unsigned bits = op == "broadcastss" ? 32 : op == "broadcastsd" ? 64 : Width(op.back());
        auto* element = Resize(Read(instruction, 1), bits);
        write(Flat(builder.CreateVectorSplat(instruction.Bits(0) / bits, element)));
        return true;
    }
    if (op == "broadcasti128" || op == "broadcastf128") {
        auto* half = Resize(Read(instruction, 1, 128), 256);
        write(builder.CreateOr(half, builder.CreateShl(half, 128)));
        return true;
    }
    if ((StartsWith(op, "pmovzx") || StartsWith(op, "pmovsx")) && op.size() == 8) {
        const unsigned from = Width(op[6]), to = Width(op[7]);
        const unsigned count = instruction.Bits(0) / to;
        auto* source = Lanes(Resize(Read(instruction, 1), count * from), from);
        auto* wide = llvm::FixedVectorType::get(Int(to), count);
        write(Flat(op[4] == 's' ? builder.CreateSExt(source, wide) : builder.CreateZExt(source, wide)));
        return true;
    }

    // Single lanes and 128-bit halves.
    if (op == "pextrb" || op == "pextrw" || op == "pextrd" || op == "pextrq" || op == "extractps") {
        const unsigned bits = op == "extractps" ? 32 : Width(op.back());
        auto* lanes = Lanes(Read(instruction, 1), bits);
        const unsigned count = llvm::cast<llvm::FixedVectorType>(lanes->getType())->getNumElements();
        auto* element = builder.CreateExtractElement(lanes, Immediate(instruction) & (count - 1));
        Write(instruction, 0, Resize(element, instruction.Bits(0)));
        return true;
    }
    if (op == "pinsrb" || op == "pinsrw" || op == "pinsrd" || op == "pinsrq") {
        const unsigned bits = Width(op.back());
        auto* lanes = Lanes(first(), bits);
        const unsigned count = llvm::cast<llvm::FixedVectorType>(lanes->getType())->getNumElements();
        auto* element = Resize(Read(instruction, vex ? 2 : 1), bits);
        write(Flat(builder.CreateInsertElement(lanes, element, Immediate(instruction) & (count - 1))));
        return true;
    }
    if (op == "extracti128" || op == "extractf128") {
        auto* source = Read(instruction, 1);
        Write(instruction, 0, Resize(builder.CreateLShr(source, (Immediate(instruction) & 1) * 128), 128), true);
        return true;
    }
    if (op == "inserti128" || op == "insertf128") {
        auto* base = Read(instruction, 1);
        auto* half = Resize(Resize(Read(instruction, 2, 128), 128), 256);
        const auto shift = (Immediate(instruction) & 1) * 128;
        auto* halfMask = llvm::ConstantInt::get(Int(256), llvm::APInt::getLowBitsSet(256, 128));
        auto* kept = builder.CreateAnd(base, builder.CreateNot(builder.CreateShl(halfMask, shift)));
        write(builder.CreateOr(kept, builder.CreateShl(half, shift)));
        return true;
    }
    if (op == "permq" || op == "permpd") {
        const auto control = Immediate(instruction);
        auto* source = Lanes(Read(instruction, 1), 64);
        std::vector<int> mask;
        for (unsigned i = 0; i < 4; ++i) mask.push_back(static_cast<int>((control >> (2 * i)) & 3));
        write(Flat(builder.CreateShuffleVector(source, mask)));
        return true;
    }
    if (op == "permd" || op == "permps") {
        // vpermd dst, indices, source.
        auto* indices = Lanes(Read(instruction, 1), 32);
        auto* source = Lanes(Read(instruction, 2), 32);
        llvm::Value* result = llvm::Constant::getNullValue(source->getType());
        for (unsigned i = 0; i < 8; ++i) {
            auto* index = builder.CreateAnd(builder.CreateExtractElement(indices, static_cast<std::uint64_t>(i)), builder.getInt32(7));
            result = builder.CreateInsertElement(result, builder.CreateExtractElement(source, index), static_cast<std::uint64_t>(i));
        }
        write(Flat(result));
        return true;
    }
    if (op == "perm2i128" || op == "perm2f128") {
        const auto control = Immediate(instruction);
        auto* a = Read(instruction, 1);
        auto* b = Read(instruction, 2);
        auto half = [&](unsigned bitsAt) -> llvm::Value* {
            if ((control >> (bitsAt + 3)) & 1) return builder.getIntN(128, 0);
            const auto which = (control >> bitsAt) & 3;
            return Resize(builder.CreateLShr(which < 2 ? a : b, (which & 1) * 128), 128);
        };
        write(builder.CreateOr(Resize(half(0), 256), builder.CreateShl(Resize(half(4), 256), 128)));
        return true;
    }
    if (op == "permilps" || op == "permilpd") {
        const unsigned bits = op == "permilps" ? 32 : 64;
        auto* source = Lanes(Read(instruction, 1), bits);
        const unsigned count = llvm::cast<llvm::FixedVectorType>(source->getType())->getNumElements(), perLane = 128 / bits;
        llvm::Value* result = llvm::Constant::getNullValue(source->getType());
        llvm::Value* control = immediate ? nullptr : Lanes(Read(instruction, 2), bits);
        for (unsigned i = 0; i < count; ++i) {
            const unsigned base = i / perLane * perLane;
            llvm::Value* element = nullptr;
            if (immediate) {
                const auto control8 = Immediate(instruction);
                const unsigned selected = bits == 32 ? (control8 >> (2 * (i % 4))) & 3 : (control8 >> i) & 1;
                element = builder.CreateExtractElement(source, static_cast<std::uint64_t>(base + selected));
            } else {
                auto* selector = builder.CreateExtractElement(control, static_cast<std::uint64_t>(i));
                if (bits == 64) selector = builder.CreateLShr(selector, 1);
                selector = builder.CreateAnd(selector, llvm::ConstantInt::get(selector->getType(), perLane - 1));
                element = builder.CreateExtractElement(source, builder.CreateAdd(selector, llvm::ConstantInt::get(selector->getType(), base)));
            }
            result = builder.CreateInsertElement(result, element, static_cast<std::uint64_t>(i));
        }
        write(Flat(result));
        return true;
    }
    if (op == "pmaskmovd" || op == "pmaskmovq" || op == "maskmovps" || op == "maskmovpd") {
        const unsigned elementBits = op == "pmaskmovq" || op == "maskmovpd" ? 64 : 32;
        auto* mask = Lanes(Read(instruction, 1), elementBits);
        auto* active = builder.CreateICmpSLT(mask, llvm::Constant::getNullValue(mask->getType()));
        if (instruction.Memory(0)) {
            auto* value = Lanes(Read(instruction, 2), elementBits);
            builder.CreateMaskedStore(value, Pointer(Address(instruction, instruction.Op(0).mem)), llvm::Align(1), active);
        } else {
            auto* type = mask->getType();
            auto* loaded = builder.CreateMaskedLoad(type, Pointer(Address(instruction, instruction.Op(2).mem)), llvm::Align(1), active, llvm::Constant::getNullValue(type));
            write(Flat(loaded));
        }
        return true;
    }

    // Masks and tests.
    if (op == "movmskps" || op == "movmskpd" || op == "pmovmskb") {
        const unsigned bits = op == "pmovmskb" ? 8 : op == "movmskps" ? 32 : 64;
        auto* lanes = Lanes(Read(instruction, 1), bits);
        auto* signs = builder.CreateICmpSLT(lanes, llvm::Constant::getNullValue(lanes->getType()));
        const unsigned count = llvm::cast<llvm::FixedVectorType>(lanes->getType())->getNumElements();
        Write(instruction, 0, Resize(builder.CreateBitCast(signs, Int(count)), instruction.Bits(0)));
        return true;
    }
    if (op == "ptest" || op == "testps" || op == "testpd") {
        auto* a = Read(instruction, 0);
        auto* b = Read(instruction, 1);
        if (op != "ptest") {
            const unsigned bits = op == "testps" ? 32 : 64;
            auto* signs = Flat(llvm::ConstantVector::getSplat(llvm::ElementCount::getFixed(a->getType()->getIntegerBitWidth() / bits),
                                                              llvm::ConstantInt::get(Int(bits), 1ull << (bits - 1))));
            a = builder.CreateAnd(a, signs);
            b = builder.CreateAnd(b, signs);
        }
        auto* zero = llvm::Constant::getNullValue(a->getType());
        SetFlag(Zf, builder.CreateICmpEQ(builder.CreateAnd(a, b), zero));
        SetFlag(Cf, builder.CreateICmpEQ(builder.CreateAnd(builder.CreateNot(a), b), zero));
        for (auto flag : {Pf, Af, Sf, Of}) SetFlag(flag, builder.getFalse());
        return true;
    }
    return false;
}

}
