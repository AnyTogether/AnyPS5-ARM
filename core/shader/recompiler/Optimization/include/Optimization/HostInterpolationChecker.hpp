#ifndef CORE_SHADER_RECOMPILIER_OPTIMIZATION_INCLUDE_OPTIMIZATION_HOSTINTERPOLATIONCHECKER_HPP
#define CORE_SHADER_RECOMPILIER_OPTIMIZATION_INCLUDE_OPTIMIZATION_HOSTINTERPOLATIONCHECKER_HPP

#include "IntermediateRepresentation/IrProgram.hpp"
#include "Optimization/ShaderStageInputInfo.hpp"

namespace ShaderRecompiler {

class HostInterpolationChecker {
public:
    [[nodiscard]] bool Lower(IrProgram& program, const ShaderPixelInputInfo& pixel) const;
    // For devices that can run neither barycentric inputs nor the geometry stage that emulates them: every
    // interpolation reads the attribute the host interpolated, and barycentric and P1 results read as 0.
    void ForceLower(IrProgram& program) const;
};

}

#endif
