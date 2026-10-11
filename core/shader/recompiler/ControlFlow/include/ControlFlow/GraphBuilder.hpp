#ifndef CORE_SHADER_RECOMPILIER_CONTROLFLOW_INCLUDE_CONTROLFLOW_GRAPHBUILDER_HPP
#define CORE_SHADER_RECOMPILIER_CONTROLFLOW_INCLUDE_CONTROLFLOW_GRAPHBUILDER_HPP

#include "ControlFlow/ControlFlowGraph.hpp"
#include "RdnaDecoder/RdnaProgram.hpp"
#include <cstdint>
#include <optional>
#include <span>
#include <vector>

namespace ShaderRecompiler {

struct SwappcInfo {
    bool fetchCallAllowed = false;
    std::uint32_t userDataBaseRegister = 0;
    std::uint32_t userDataCount = 0;
};

struct SwappcCall {
    std::uint32_t callIndex = 0;
    std::uint32_t linkRegister = 0;
    bool fetch = false;
    std::uint32_t targetIndex = 0;
    std::uint32_t targetProgramCounter = 0;
    std::uint32_t returnIndex = 0;
    std::uint32_t returnTargetProgramCounter = 0;
};

struct UserDataCall {
    std::uint32_t programCounter = 0;
    std::uint32_t linkRegister = 0;
    std::uint32_t userDataRegister = 0;
};

[[nodiscard]] std::optional<std::uint32_t> UnresolvableSwappcTarget(const RdnaProgram& program, const SwappcInfo* swappc);
[[nodiscard]] std::vector<UserDataCall> FindUserDataCalls(const RdnaProgram& program, const SwappcInfo& swappc);
[[nodiscard]] std::optional<std::uint32_t> UserDataCalleeLength(std::span<const std::uint32_t> callee, std::uint32_t linkRegister);
[[nodiscard]] std::vector<std::uint32_t> LinkUserDataCalls(const RdnaProgram& program, std::span<const UserDataCall> calls, std::span<const std::vector<std::uint32_t>> callees);

class GraphBuilder {
public:
    [[nodiscard]] ControlFlowGraph Build(const RdnaProgram& program, const SwappcInfo* swappc = nullptr) const;

private:
    [[nodiscard]] std::vector<BasicBlock> splitIntoBlocks(const RdnaProgram& program, const std::vector<SwappcCall>& calls) const;
    void linkBlocks(std::vector<BasicBlock>& blocks, const RdnaProgram& program, const std::vector<SwappcCall>& calls) const;
};

}

#endif
