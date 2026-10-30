#ifndef CORE_LIBS_PRX_LIBSCEAGCDRIVER_EXECUTION_INCLUDE_UPSCALERSETTING_HPP
#define CORE_LIBS_PRX_LIBSCEAGCDRIVER_EXECUTION_INCLUDE_UPSCALERSETTING_HPP

namespace AgcDriver {

enum class Upscaler { Bilinear, Fsr1 };

struct UpscalerSetting {
    static constexpr float DefaultSharpness = 0.2f;
    static constexpr float MaximumSharpness = 2.0f;
    Upscaler upscaler = Upscaler::Bilinear;
    float sharpness = DefaultSharpness;
};

UpscalerSetting UpscalerRequested(const char* upscaler, const char* sharpness);

}

#endif
