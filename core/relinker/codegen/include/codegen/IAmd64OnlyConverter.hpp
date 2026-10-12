#ifndef CODEGEN_IAMD64ONLYCONVERTER_HPP
#define CODEGEN_IAMD64ONLYCONVERTER_HPP

#include <codegen/CodegenTypes.hpp>
#include <domain/Types.hpp>
#include <memory>
#include <utility>
#include <vector>

namespace Codegen {

class IAmd64OnlyConverter {
public:
    virtual ~IAmd64OnlyConverter() = default;

    [[nodiscard]] virtual ConvertResult Convert(
        std::vector<std::uint8_t> fileBytes,
        const std::vector<Domain::ProgramHeader>& codeSegments,
        const std::vector<Domain::VirtualAddress>& indirectTargets
    ) const = 0;

    [[nodiscard]] ConvertResult Convert(
        std::vector<std::uint8_t> fileBytes,
        const std::vector<Domain::ProgramHeader>& codeSegments
    ) const {
        return Convert(std::move(fileBytes), codeSegments, {});
    }
};

std::unique_ptr<IAmd64OnlyConverter> MakeAmd64OnlyConverter(Amd64OnlyTarget target = Amd64OnlyTarget::Intel);

}

#endif
