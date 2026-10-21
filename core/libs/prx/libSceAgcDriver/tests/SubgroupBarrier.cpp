#include "prx/libSceAgcDriver/Execution/include/SubgroupBarrier.hpp"
#include "Recompiler.hpp"
#include <spirv/unified1/spirv.hpp>
#include <array>
#include <cstdint>
#include <cstdio>
#include <exception>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>

namespace {

struct Case {
    VkDriverId driver;
    bool usable;
};

constexpr Case Cases[]{
    {VK_DRIVER_ID_AMD_PROPRIETARY, false},
    {VK_DRIVER_ID_AMD_OPEN_SOURCE, true},
    {VK_DRIVER_ID_MESA_RADV, true},
    {VK_DRIVER_ID_NVIDIA_PROPRIETARY, true},
    {VK_DRIVER_ID_INTEL_PROPRIETARY_WINDOWS, true},
    {VK_DRIVER_ID_INTEL_OPEN_SOURCE_MESA, true},
    {VK_DRIVER_ID_MESA_LLVMPIPE, true},
    {VK_DRIVER_ID_MOLTENVK, true},
};

constexpr std::array<std::uint32_t, 19> BranchedLdsStep{
    0x34040082u, 0x4a020081u, 0xd8340000u, 0x00000102u, 0xbf8cc07fu, 0xbf8a0000u, 0x7da800ffu, 0x00000080u,
    0xbf880006u, 0xd8d80200u, 0x03000002u, 0xbf8cc07fu, 0x4a020701u, 0xd8340000u, 0x00000102u, 0xbefe03c1u,
    0xbf8cc07fu, 0xbf8a0000u, 0xbf810000u,
};

struct Barriers {
    std::uint32_t subgroupControl = 0;
    std::uint32_t subgroupMemory = 0;
};

void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

Barriers recompile(std::uint32_t threads, bool waveLdsMemoryBarriers) {
    using namespace ShaderRecompiler;
    const std::array<std::uint32_t, 2> capabilities{spv::CapabilityShader, spv::CapabilityGroupNonUniform};
    const std::array<std::string_view, 1> extensions{"SPV_KHR_storage_buffer_storage_class"};
    RecompileRequest request{};
    request.shader = {ShaderStage::Compute, 0x20000u, BranchedLdsStep, 0, {}};
    request.context.waveSize = 32;
    request.context.compute = ShaderComputeStageInfo{{threads, 1u, 1u}, 256u, {false, false, false}, false, 1u};
    request.target.vulkanVersion = 0x00403000u;
    request.target.spirvVersion = 0x00010600u;
    request.target.subgroupSize = 32;
    request.target.bdaAbiVersion = 1;
    request.target.supportedCapabilities = capabilities;
    request.target.supportedExtensions = extensions;
    request.target.maxWorkgroupSize = {1024u, 1024u, 64u};
    request.target.maxWorkgroupInvocations = 1024;
    request.target.maxWorkgroupSharedMemoryBytes = 49152;
    request.target.waveLdsMemoryBarriers = waveLdsMemoryBarriers;
    request.layout = {0, 0, 0, 128};
    request.useCache = false;
    const auto result = Recompile(request);
    const auto& words = result.spirv.Words();
    std::unordered_map<std::uint32_t, std::uint32_t> constants;
    Barriers barriers;
    for (std::size_t at = 5; at < words.size() && (words[at] >> 16u) != 0; at += words[at] >> 16u) {
        const auto op = static_cast<spv::Op>(words[at] & 0xffffu);
        if (op == spv::OpConstant && (words[at] >> 16u) == 4u) constants[words[at + 2]] = words[at + 3];
        if (op != spv::OpControlBarrier && op != spv::OpMemoryBarrier) continue;
        const auto scope = constants.find(words[at + 1]);
        require(scope != constants.end(), "a barrier scope is not a 32-bit constant");
        if (scope->second != spv::ScopeSubgroup) continue;
        if (op == spv::OpControlBarrier) ++barriers.subgroupControl;
        else ++barriers.subgroupMemory;
    }
    return barriers;
}

void verifyDriverQuirk() {
    for (const auto& item : Cases) {
        require(AgcDriver::SubgroupControlBarrierUsable(item.driver) == item.usable, "driver " + std::to_string(static_cast<int>(item.driver)) + ": expected subgroup control barriers to be " + (item.usable ? "usable" : "unusable"));
    }
}

void verifyEmittedBarriers() {
    const auto control = recompile(256, false);
    require(control.subgroupControl != 0 && control.subgroupMemory == 0, "a wave32 program in a workgroup of eight waves did not order its LDS accesses with subgroup-scope OpControlBarrier only");
    const auto memory = recompile(256, true);
    require(memory.subgroupControl == 0 && memory.subgroupMemory != 0, "with wave LDS memory barriers, a wave32 program in a workgroup of eight waves did not order its LDS accesses with subgroup-scope OpMemoryBarrier only");
    const auto single = recompile(32, true);
    require(single.subgroupControl == 0 && single.subgroupMemory == 0, "with wave LDS memory barriers, a single-wave workgroup did not keep workgroup-scope barriers");
}

}

int main() {
    try {
        verifyDriverQuirk();
        verifyEmittedBarriers();
        std::puts("subgroup barrier tests passed");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}
