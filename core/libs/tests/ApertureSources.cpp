#include "ControlFlow/GraphBuilder.hpp"
#include "FlatApertures.hpp"
#include "IntermediateRepresentation/IrProgram.hpp"
#include "RdnaDecoder/RdnaInstructionDecoder.hpp"
#include "Translation/InstructionTranslator.hpp"
#include <array>
#include <cstdint>
#include <cstdio>
#include <exception>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>

using namespace ShaderRecompiler;

namespace {

struct ApertureSource {
    std::uint32_t code;
    RdnaOperandKind kind;
    const char* name;
    std::uint64_t value;
};

constexpr std::array<ApertureSource, 4> ApertureSources{{
    {235u, RdnaOperandKind::SrcSharedBase, "src_shared_base", SharedApertureBase},
    {236u, RdnaOperandKind::SrcSharedLimit, "src_shared_limit", SharedApertureLimit},
    {237u, RdnaOperandKind::SrcPrivateBase, "src_private_base", PrivateApertureBase},
    {238u, RdnaOperandKind::SrcPrivateLimit, "src_private_limit", PrivateApertureLimit},
}};

constexpr std::uint32_t Destination = 4u;
constexpr std::uint32_t EndProgram = 0xbf810000u;
constexpr std::array<std::uint32_t, 2> WaveSizes{32u, 64u};

void Require(bool value, const std::string& message) {
    if (!value) throw std::runtime_error(message);
}

std::string Hex(std::uint32_t value) {
    char text[16];
    std::snprintf(text, sizeof(text), "0x%08x", value);
    return text;
}

std::uint32_t ScalarMove32(std::uint32_t source) {
    return 0xbe800300u | (Destination << 16u) | source;
}

std::uint32_t ScalarMove64(std::uint32_t source) {
    return 0xbe800400u | (Destination << 16u) | source;
}

IrProgram Translate(std::span<const std::uint32_t> code, std::uint32_t waveSize) {
    const auto decoded = RdnaInstructionDecoder{}.Decode(code);
    const auto graph = GraphBuilder{}.Build(decoded);
    const ShaderComputeInputInfo compute{};
    TranslateOptions options;
    options.stage = ShaderStageKind::Compute;
    options.waveSize = waveSize;
    options.userDataCount = 0;
    options.inputInfo.compute = &compute;
    return InstructionTranslator{}.Translate(decoded, graph, options);
}

std::optional<std::uint32_t> ScalarRegisterConstant(const IrProgram& program, std::uint32_t index) {
    const IrValue* written = nullptr;
    for (const auto& block : program.Blocks()) {
        for (const auto* instruction : block->Instructions()) {
            if (instruction->Opcode() != IrOpcode::SetScalarRegister) continue;
            const auto reg = instruction->Argument(0)->Register();
            if (reg.bank == RegisterBank::Scalar && reg.index == index) written = instruction->Argument(1);
        }
    }
    if (written == nullptr) return std::nullopt;
    Require(written->HasImmediate(), "s" + std::to_string(index) + " was last written with " + std::string(IrOpcodeName(written->Opcode())) + ", not a constant");
    return written->ImmediateU32();
}

void CheckDecode() {
    for (const auto& source : ApertureSources) {
        const auto operand = DecodeRdnaScalarSource(source.code, 0u);
        Require(operand.kind == source.kind, "scalar source " + std::to_string(source.code) + " decoded to the wrong operand kind");
        Require(RdnaOperandToString(operand) == source.name, "scalar source " + std::to_string(source.code) + " is named " + RdnaOperandToString(operand));
    }
}

void CheckMove32() {
    for (const auto& source : ApertureSources) {
        for (const auto waveSize : WaveSizes) {
            const std::string name = "s_mov_b32 s4, " + std::string(source.name) + " in wave" + std::to_string(waveSize);
            const std::array<std::uint32_t, 2> code{ScalarMove32(source.code), EndProgram};
            const auto program = Translate(code, waveSize);
            const auto low = ScalarRegisterConstant(program, Destination);
            Require(low.has_value(), name + " did not write s4");
            const auto expected = static_cast<std::uint32_t>(source.value);
            Require(*low == expected, name + " wrote " + Hex(*low) + ", expected the low dword " + Hex(expected));
            Require(!ScalarRegisterConstant(program, Destination + 1u).has_value(), name + " also wrote s5");
        }
    }
}

void CheckMove64() {
    for (const auto& source : ApertureSources) {
        for (const auto waveSize : WaveSizes) {
            const std::string name = "s_mov_b64 s[4:5], " + std::string(source.name) + " in wave" + std::to_string(waveSize);
            const std::array<std::uint32_t, 2> code{ScalarMove64(source.code), EndProgram};
            const auto program = Translate(code, waveSize);
            const auto low = ScalarRegisterConstant(program, Destination);
            const auto high = ScalarRegisterConstant(program, Destination + 1u);
            Require(low.has_value() && high.has_value(), name + " did not write both s4 and s5");
            const auto expectedLow = static_cast<std::uint32_t>(source.value);
            const auto expectedHigh = static_cast<std::uint32_t>(source.value >> 32u);
            Require(*low == expectedLow && *high == expectedHigh,
                name + " wrote " + Hex(*high) + "_" + Hex(*low) + ", expected " + Hex(expectedHigh) + "_" + Hex(expectedLow));
        }
    }
}

void CheckDwordPastThePairThrows() {
    for (const auto& source : ApertureSources) {
        const std::string name = "v_mqsad_u32_u8 v[0:3], v[4:5], v6, " + std::string(source.name);
        const std::array<std::uint32_t, 3> code{0xd5750000u, 0x00020d04u | (source.code << 18u), EndProgram};
        try {
            static_cast<void>(Translate(code, 32u));
        } catch (const std::runtime_error& error) {
            const std::string message = error.what();
            Require(message.find("v_mqsad_u32_u8") != std::string::npos && message.find(source.name) != std::string::npos && message.find("at pc 0") != std::string::npos,
                name + " refused without naming the instruction, the source and the program counter: " + message);
            continue;
        }
        throw std::runtime_error(name + " read dwords past the aperture pair");
    }
}

}

int main() {
    try {
        CheckDecode();
        CheckMove32();
        CheckMove64();
        CheckDwordPastThePairThrows();
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
    std::puts("aperture sources tests passed");
    return 0;
}
