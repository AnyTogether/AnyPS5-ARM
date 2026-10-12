#ifndef RELINKER_DOMAIN_ISYSCALLSCANNER_HPP
#define RELINKER_DOMAIN_ISYSCALLSCANNER_HPP

#include <relinker/domain/Types.hpp>
#include <cstddef>
#include <vector>

namespace Relinker {

class ISyscallScanner {
public:
    virtual ~ISyscallScanner() = default;

    virtual std::vector<std::size_t> ScanCodeSectionForSyscalls(
        const std::vector<std::uint8_t>& codeSection,
        FileByteOffset codeSectionOffset,
        FileByteOffset codeSectionSize
    ) = 0;
};

}

#endif
