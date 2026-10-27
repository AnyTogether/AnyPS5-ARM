#ifndef CORE_LIBS_NID_MACHONIDPATCHER_HPP
#define CORE_LIBS_NID_MACHONIDPATCHER_HPP

#include <nid/IBinaryPatcher.hpp>
#include <cstdint>
#include <string>
#include <vector>

namespace Nid {

constexpr std::uint32_t kMachOMagic64 = 0xfeedfacfu;

// One entry of a dyld export trie. Mach-O C symbols keep their leading underscore here.
struct MachOExport {
    std::string Name;
    std::uint64_t Flags = 0;
    std::uint64_t Address = 0;
    std::uint64_t Other = 0;
    std::string ImportName;
};

// The export trie of a 64-bit Mach-O image (LC_DYLD_EXPORTS_TRIE or LC_DYLD_INFO).
std::vector<MachOExport> ReadMachOExports(const std::vector<std::uint8_t>& binary);

class MachONidPatcher final : public IBinaryPatcher {
public:
    void PatchNids(std::vector<std::uint8_t>& binary, const std::string& libraryName, const std::unordered_set<std::string>& excludedExports, const PatchOptions& options = {}) const override;
};

}

#endif
