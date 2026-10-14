#include "ControlFlow/RequestSerializer.hpp"

#include <cstdlib>
#include <stdexcept>
#include <string_view>

namespace {

constexpr char kHistoricalVersion21[] =
    "NVNQQRUAAAAFAAADAAAAAAABAAAAAAAAAAAAgb8AAAAAAAAAAAAAAAAAAAAAQAAAAAgAAAADAAAAAAAAAN+bVxPgrGgk776t3gABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJAAAAAAAAAOQAAAAAAAAAAAAAAAAAAAAAAQEAAAEAAAAAAAAAAAAFAAAAAAAEAAAAAAAAABI0VngAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIAAAALAAAAEAAAAEAAAAAAAAF4VjQSAQEBOTAAAAA=";
constexpr char kVersion21WithF16Tail[] =
    "NVNQQRUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAQA0DAAEB";
constexpr char kVersion22WithoutF16Tail[] =
    "NVNQQRYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAQA0DAAE=";

void Require(bool condition) {
    if (!condition) std::abort();
}

}

int main() {
    const ShaderRecompiler::RequestSerializer serializer;

    const auto historical = serializer.Deserialize(kHistoricalVersion21);
    Require(!historical.request.target.float16DenormPreserve);

    const auto version21WithTail = serializer.Deserialize(kVersion21WithF16Tail);
    Require(version21WithTail.request.target.float16DenormPreserve);

    bool rejectedTruncatedVersion22 = false;
    try {
        static_cast<void>(serializer.Deserialize(kVersion22WithoutF16Tail));
    } catch (const std::runtime_error& error) {
        rejectedTruncatedVersion22 = std::string_view(error.what()) == "RequestSerializer: truncated data";
    }
    Require(rejectedTruncatedVersion22);

    ShaderRecompiler::RecompileRequest request{};
    request.target.float16DenormPreserve = false;
    const auto withoutPreserve = serializer.Deserialize(serializer.Serialize(request));
    Require(!withoutPreserve.request.target.float16DenormPreserve);

    request.target.float16DenormPreserve = true;
    const auto withPreserve = serializer.Deserialize(serializer.Serialize(request));
    Require(withPreserve.request.target.float16DenormPreserve);

    return 0;
}
