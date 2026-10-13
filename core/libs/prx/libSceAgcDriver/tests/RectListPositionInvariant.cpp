#include "Recompiler.hpp"
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <exception>
#include <span>
#include <spirv/unified1/spirv.hpp>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {

using namespace ShaderRecompiler;

void Check(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

bool PositionIsInvariant(std::span<const std::uint32_t> words) {
    Check(words.size() >= 5 && words[0] == spv::MagicNumber, "rect-list invariant: missing SPIR-V module");
    std::vector<std::pair<std::uint32_t, std::uint32_t>> positionMembers;
    std::vector<std::pair<std::uint32_t, std::uint32_t>> invariantMembers;
    for (std::size_t offset = 5; offset < words.size();) {
        const auto count = words[offset] >> spv::WordCountShift;
        Check(count != 0 && count <= words.size() - offset, "rect-list invariant: malformed SPIR-V instruction");
        const auto opcode = words[offset] & spv::OpCodeMask;
        if (opcode == spv::OpMemberDecorate && count == 5 && words[offset + 3] == spv::DecorationBuiltIn && words[offset + 4] == spv::BuiltInPosition) {
            positionMembers.emplace_back(words[offset + 1], words[offset + 2]);
        }
        if (opcode == spv::OpMemberDecorate && count == 4 && words[offset + 3] == spv::DecorationInvariant) {
            invariantMembers.emplace_back(words[offset + 1], words[offset + 2]);
        }
        offset += count;
    }
    Check(!positionMembers.empty(), "rect-list invariant: shader has no gl_Position");
    for (const auto& member : positionMembers) {
        if (std::find(invariantMembers.begin(), invariantMembers.end(), member) == invariantMembers.end()) return false;
    }
    return true;
}

}

int main() {
    try {
        static constexpr std::array<std::uint32_t, 2> capabilities{spv::CapabilityShader, spv::CapabilityTessellation};
        SpirvTarget target{};
        target.vulkanVersion = 0x00401000u;
        target.spirvVersion = 0x00010400u;
        target.supportedCapabilities = capabilities;
        target.tessellation = TessellationTargetLimits{32, 128, 128, 120, 4096, 128, 128};
        RecompileResult vertex;
        RecompileResult fragment;
        const auto shaders = BuildRectListShaders(vertex, fragment, target);
        Check(PositionIsInvariant(shaders.control.spirv.Words()), "rect-list control gl_Position is not Invariant");
        Check(PositionIsInvariant(shaders.evaluation.spirv.Words()), "rect-list evaluation gl_Position is not Invariant");
        std::printf("rect-list position invariant tests passed\n");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}
