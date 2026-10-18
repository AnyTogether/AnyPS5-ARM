#ifndef ELFPATCHER_MACOS_MACHOPATCHER_HPP
#define ELFPATCHER_MACOS_MACHOPATCHER_HPP

#include <elfpatcher/general/IElfPatcher.hpp>

namespace Elfpatcher::MacOs {

// Writes the guest image as an x86-64 Mach-O executable for macOS (run under Rosetta on Apple
// silicon). dyld does the dynamic linking: the prx libraries are LC_LOAD_DYLIBs, guest imports are
// flat-namespace binds to their NID names and RELATIVE relocations are rebases.
class MacOsMachOPatcher final : public IElfPatcher {
public:
    std::vector<std::uint8_t> Patch(
        std::vector<std::uint8_t> sourceElf,
        const std::vector<Domain::ProgramHeader>& originalHeaders,
        const Domain::SysVDynamicSection& dynamicSection,
        std::uint64_t originalPltGotVaddr,
        const std::string& runPath,
        bool lazyBinding,
        bool dependencyDiagnostics,
        const std::vector<Codegen::TrampolineSite>& trampolines
    ) override;
};

}

#endif
