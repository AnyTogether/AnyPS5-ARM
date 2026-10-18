#ifndef TOOLS_TRANSLATOR_SRC_ELF_HPP
#define TOOLS_TRANSLATOR_SRC_ELF_HPP

#include <cstdint>
#include <filesystem>
#include <map>
#include <string>
#include <vector>

namespace Translator {

struct Segment {
    std::uint64_t vaddr;
    std::uint64_t fileOffset;
    std::uint64_t fileSize;
    std::uint64_t memorySize;
    std::uint32_t flags;

    bool Executable() const { return (flags & 1u) != 0; }
};

struct Relocation {
    std::uint64_t offset;
    std::uint32_t type;
    std::uint32_t symbol;
    std::int64_t addend;
};

struct Symbol {
    std::string name;
    std::uint64_t value;
    std::uint64_t size;
    std::uint8_t info;
    std::uint16_t section;
};

// A guest ELF as the relinker reads it: PT_LOAD segments mapped at their virtual addresses, and the
// dynamic tables either through SysV tags (virtual addresses) or the PS5 DT_OS_* tags (file offsets).
class Elf {
public:
    explicit Elf(const std::filesystem::path& path);

    const std::vector<std::uint8_t>& Bytes() const { return bytes; }
    const std::vector<Segment>& Loads() const { return loads; }
    std::uint64_t Entry() const { return entry; }
    std::uint64_t ImageBegin() const;
    std::uint64_t ImageEnd() const;

    const std::vector<Relocation>& Relocations() const { return relocations; }
    const std::vector<Symbol>& Symbols() const { return symbols; }
    const std::vector<std::string>& Needed() const { return needed; }
    std::vector<std::uint64_t> InitFunctions() const;

    // The bytes of the loaded image at a virtual address, or null outside the file-backed part.
    const std::uint8_t* At(std::uint64_t vaddr, std::uint64_t size) const;
    bool InExecutable(std::uint64_t vaddr) const;

private:
    std::uint64_t Translate(std::uint64_t vaddr) const;
    std::uint64_t Tag(std::int64_t tag, std::uint64_t fallback = 0) const;
    bool HasTag(std::int64_t tag) const;
    std::uint64_t TableOffset(std::int64_t osTag, std::int64_t sysvTag) const;
    std::uint64_t TableSize(std::int64_t osTag, std::int64_t sysvTag) const;
    std::string String(std::uint64_t offset) const;
    void ReadRelocations(std::uint64_t offset, std::uint64_t size);

    std::vector<std::uint8_t> bytes;
    std::vector<Segment> loads;
    std::vector<Segment> dynamicData;
    std::multimap<std::int64_t, std::uint64_t> tags;
    std::uint64_t entry = 0;
    std::uint64_t stringsOffset = 0;
    std::uint64_t stringsSize = 0;
    std::vector<Relocation> relocations;
    std::vector<Symbol> symbols;
    std::vector<std::string> needed;
};

}

#endif
