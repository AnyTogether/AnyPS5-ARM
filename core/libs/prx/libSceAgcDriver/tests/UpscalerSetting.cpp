#include "prx/libSceAgcDriver/Execution/include/UpscalerSetting.hpp"
#include <cmath>
#include <exception>
#include <iostream>
#include <stdexcept>
#include <string>

using AgcDriver::Upscaler;
using AgcDriver::UpscalerRequested;
using AgcDriver::UpscalerSetting;

namespace {

void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

bool near(float value, float expected) {
    return std::fabs(value - expected) < 1e-6f;
}

std::string refusal(const char* upscaler, const char* sharpness) {
    try {
        static_cast<void>(UpscalerRequested(upscaler, sharpness));
    } catch (const std::runtime_error& error) {
        return error.what();
    }
    return {};
}

void defaultsAreBilinear() {
    for (const char* unset : {static_cast<const char*>(nullptr), ""}) {
        const auto setting = UpscalerRequested(unset, unset);
        require(setting.upscaler == Upscaler::Bilinear, "the upscaler is not bilinear when ANYPS5_UPSCALER is unset");
        require(near(setting.sharpness, 0.2f), "the sharpness is not 0.2 stops when ANYPS5_FSR_SHARPNESS is unset");
    }
    require(UpscalerRequested("bilinear", nullptr).upscaler == Upscaler::Bilinear, "ANYPS5_UPSCALER=bilinear is not bilinear");
}

void fsr1IsChosen() {
    const auto setting = UpscalerRequested("fsr1", nullptr);
    require(setting.upscaler == Upscaler::Fsr1, "ANYPS5_UPSCALER=fsr1 does not choose FSR 1");
    require(near(setting.sharpness, UpscalerSetting::DefaultSharpness), "FSR 1 without a sharpness does not use 0.2 stops");
}

void sharpnessIsRead() {
    require(near(UpscalerRequested("fsr1", "0").sharpness, 0.0f), "sharpness 0 is not read");
    require(near(UpscalerRequested("fsr1", "2").sharpness, 2.0f), "sharpness 2 is not read");
    require(near(UpscalerRequested("fsr1", "0.5").sharpness, 0.5f), "sharpness 0.5 is not read");
    require(near(UpscalerRequested("fsr1", "1.25").sharpness, 1.25f), "sharpness 1.25 is not read");
    require(near(UpscalerRequested("fsr1", "2.0").sharpness, 2.0f), "sharpness 2.0 is not read");
    require(near(UpscalerRequested("fsr1", ".3").sharpness, 0.3f), "sharpness .3 is not read");
}

void badValuesAreRefused() {
    for (const char* name : {"FSR1", "fsr", "fsr2", "nearest", "1", " fsr1"}) {
        const auto message = refusal(name, nullptr);
        require(message.find("ANYPS5_UPSCALER") != std::string::npos && message.find(name) != std::string::npos, std::string("ANYPS5_UPSCALER=") + name + " was accepted or not named: " + message);
    }
    for (const char* value : {"-0.5", "2.1", "3", "abc", "0,5", "1e1", ".", "0.2.3", " 0.2", "nan", "inf"}) {
        const auto message = refusal("fsr1", value);
        require(message.find("ANYPS5_FSR_SHARPNESS") != std::string::npos && message.find(value) != std::string::npos, std::string("ANYPS5_FSR_SHARPNESS=") + value + " was accepted or not named: " + message);
    }
    require(!refusal("bilinear", "9").empty(), "a bad sharpness is accepted while bilinear is chosen");
}

}

int main() {
    try {
        defaultsAreBilinear();
        fsr1IsChosen();
        sharpnessIsRead();
        badValuesAreRefused();
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
    std::cout << "upscaler setting tests passed\n";
    return 0;
}
