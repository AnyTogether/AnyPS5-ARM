#include "prx/libSceAgcDriver/Execution/include/UpscalerSetting.hpp"
#include <cstddef>
#include <stdexcept>
#include <string>
#include <string_view>

namespace AgcDriver {
namespace {

float stops(std::string_view text) {
    const std::string refused = "ANYPS5_FSR_SHARPNESS must be a number of stops from 0 to " + std::to_string(static_cast<int>(UpscalerSetting::MaximumSharpness)) + ", such as 0.2, not '" + std::string(text) + "'";
    double whole = 0;
    double fraction = 0;
    double scale = 1;
    std::size_t digits = 0;
    bool point = false;
    for (const char character : text) {
        if (character == '.' && !point) {
            point = true;
        } else if (character >= '0' && character <= '9') {
            ++digits;
            if (point) {
                scale /= 10;
                fraction += (character - '0') * scale;
            } else {
                whole = whole * 10 + (character - '0');
            }
        } else {
            throw std::runtime_error(refused);
        }
    }
    const double value = whole + fraction;
    if (digits == 0 || value > UpscalerSetting::MaximumSharpness) throw std::runtime_error(refused);
    return static_cast<float>(value);
}

}

UpscalerSetting UpscalerRequested(const char* upscaler, const char* sharpness) {
    UpscalerSetting setting;
    const std::string_view name = upscaler != nullptr ? upscaler : "";
    if (name == "fsr1") {
        setting.upscaler = Upscaler::Fsr1;
    } else if (!name.empty() && name != "bilinear") {
        throw std::runtime_error("ANYPS5_UPSCALER must be fsr1 or bilinear, not '" + std::string(name) + "'");
    }
    const std::string_view strength = sharpness != nullptr ? sharpness : "";
    if (!strength.empty()) setting.sharpness = stops(strength);
    return setting;
}

}
