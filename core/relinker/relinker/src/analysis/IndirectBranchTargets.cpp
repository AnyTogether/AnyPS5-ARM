#include <relinker/analysis/IndirectBranchTargets.hpp>
#include <relinker/analysis/UnusedNidFilter/EhFrameReader.hpp>
#include <elfpatcher/general/ElfConstants.hpp>
#include <algorithm>
#include <cstring>
#include <limits>
#include <map>
#include <optional>
#include <set>
#include <string>

namespace Relinker {

using namespace Elfpatcher;

namespace {

constexpr std::int64_t kDtGnuHash = 0x6ffffef5;
constexpr std::uint16_t kShnAbs = 0xfff1;

struct RelocationTable {
    std::int64_t AddressTag;
    std::int64_t OsAddressTag;
    std::int64_t SizeTag;
    std::int64_t OsSizeTag;
    std::int64_t EntryTag;
    std::int64_t OsEntryTag;
    std::uint64_t EntryValue;
    const char* AddressName;
    const char* SizeName;
    const char* EntryName;
    const char* EntryMessage;
    const char* SizeMessage;
    const char* BoundsMessage;
};

constexpr RelocationTable kRelaTable{DT_RELA, DT_OS_RELA, DT_RELASZ, DT_OS_RELASZ, DT_RELAENT, DT_OS_RELAENT, kRelaEntrySize, "DT_RELA", "DT_RELASZ", "DT_RELAENT", "Unsupported DT_RELAENT value", "Invalid DT_RELASZ value", "Relocation table is out of bounds"};
constexpr RelocationTable kJmpRelTable{DT_JMPREL, DT_OS_JMPREL, DT_PLTRELSZ, DT_OS_PLTRELSZ, DT_PLTREL, DT_OS_PLTREL, static_cast<std::uint64_t>(DT_RELA), "DT_JMPREL", "DT_PLTRELSZ", "DT_PLTREL", "Unsupported DT_PLTREL type", "Invalid DT_PLTRELSZ value", "Jump relocation table is out of bounds"};

class IndirectBranchTargetReader {
public:
    explicit IndirectBranchTargetReader(const IElfReader& reader)
        : _reader(reader), _bytes(reader.GetRawBytes()), _headers(reader.ReadProgramHeaders()) {}

    std::vector<VirtualAddress> Read() {
        _readDynamicTags();
        if (const auto entry = _reader.ReadHeader().EntryPoint; entry != 0) _add(entry);
        if (const auto init = _value(DT_INIT, DT_OS_INIT, "DT_INIT"); init && *init != 0) _add(*init);
        if (const auto fini = _value(DT_FINI, DT_OS_FINI, "DT_FINI"); fini && *fini != 0) _add(*fini);
        _readSymbols();
        _readRelocations(kRelaTable);
        _readRelocations(kJmpRelTable);
        for (const auto& function : UnusedNidFilter::ReadExceptionFunctions(_bytes, _headers, _pointers, _importSlots)) {
            _add(function.Begin);
            for (const auto target : function.ExtraTargets) _add(target);
        }
        return {_targets.begin(), _targets.end()};
    }

private:
    const IElfReader& _reader;
    const std::vector<std::uint8_t>& _bytes;
    std::vector<ProgramHeader> _headers;
    std::map<std::int64_t, std::uint64_t> _tags;
    std::optional<FileByteOffset> _sceBase;
    std::optional<FileByteOffset> _symbols;
    std::map<VirtualAddress, VirtualAddress> _pointers;
    std::set<VirtualAddress> _importSlots;
    std::set<VirtualAddress> _targets;

    void _require(const FileByteOffset offset, const std::uint64_t size, const char* message) const {
        if (offset > _bytes.size() || size > _bytes.size() - offset) throw RelinkerException(message, offset);
    }

    template<typename TValue>
    TValue _read(const FileByteOffset offset) const {
        _require(offset, sizeof(TValue), "File range out of bounds");
        TValue value;
        std::memcpy(&value, _bytes.data() + offset, sizeof(value));
        return value;
    }

    void _add(const VirtualAddress address) {
        for (const auto& header : _headers) {
            if (header.Type != PT_LOAD || (header.Flags & PF_X) == 0 || address < header.MappedAddress || address - header.MappedAddress >= header.FileSize) continue;
            _targets.insert(address);
            return;
        }
    }

    void _readDynamicTags() {
        const ProgramHeader* dynamic = nullptr;
        for (const auto& header : _headers) {
            if (header.Type == PT_SCE_DYNLIBDATA) {
                if (_sceBase) throw RelinkerException("Multiple PT_SCE_DYNLIBDATA segments", header.Offset);
                _sceBase = header.Offset;
            }
            if (header.Type == PT_DYNAMIC && dynamic == nullptr) dynamic = &header;
        }
        if (dynamic == nullptr) throw RelinkerException("No PT_DYNAMIC segment found");
        for (const auto& tag : _reader.ReadDynamicTags(*dynamic)) _tags.emplace(tag.Tag, tag.Value);
    }

    std::optional<std::uint64_t> _value(const std::int64_t standard, const std::int64_t os, const char* name) const {
        const auto standardTag = _tags.find(standard);
        const auto osTag = _tags.find(os);
        if (standardTag != _tags.end() && osTag != _tags.end()) throw RelinkerException(std::string("Both DT_OS_ and DT_ variants present for ") + name);
        if (osTag != _tags.end()) return osTag->second;
        if (standardTag != _tags.end()) return standardTag->second;
        return std::nullopt;
    }

    std::uint64_t _required(const std::int64_t standard, const std::int64_t os, const char* name) const {
        const auto value = _value(standard, os, name);
        if (!value) throw RelinkerException(std::string("Neither DT_OS_ nor DT_ variant present for ") + name);
        return *value;
    }

    FileByteOffset _table(const std::int64_t standard, const std::int64_t os, const char* name) const {
        const auto value = _required(standard, os, name);
        if (!_tags.contains(os)) return _reader.TranslateVirtualAddress(value);
        const auto base = _sceBase.value_or(0);
        if (value > std::numeric_limits<FileByteOffset>::max() - base) throw RelinkerException(std::string("Adding PT_SCE_DYNLIBDATA base to ") + name + " overflows", value);
        return base + value;
    }

    FileByteOffset _symbol(const std::uint64_t index) const {
        if (!_symbols) throw RelinkerException("Neither DT_OS_ nor DT_ variant present for DT_SYMTAB");
        const auto offset = *_symbols + index * kSymEntrySize;
        if (offset < *_symbols || offset > _bytes.size() || _bytes.size() - offset < kSymEntrySize) throw RelinkerException("Symbol table entry out of bounds", offset);
        return offset;
    }

    std::uint64_t _gnuHashSymbolCount(const VirtualAddress address) const {
        const auto header = _reader.TranslateVirtualAddress(address);
        _require(header, 16, "GNU hash table is out of bounds");
        const auto bucketCount = _read<std::uint32_t>(header);
        const auto firstSymbol = _read<std::uint32_t>(header + 4);
        const auto bloomCount = _read<std::uint32_t>(header + 8);
        if (bucketCount == 0 || bloomCount == 0 || firstSymbol == 0) throw RelinkerException("Invalid GNU hash header", address);
        const auto buckets = header + 16 + static_cast<std::uint64_t>(bloomCount) * 8;
        const auto chains = buckets + static_cast<std::uint64_t>(bucketCount) * 4;
        _require(buckets, static_cast<std::uint64_t>(bucketCount) * 4, "GNU hash table is out of bounds");
        std::uint64_t last = 0;
        for (std::uint64_t index = 0; index < bucketCount; ++index) {
            const auto bucket = _read<std::uint32_t>(buckets + index * 4);
            if (bucket != 0 && bucket < firstSymbol) throw RelinkerException("Invalid GNU hash bucket", address);
            last = std::max<std::uint64_t>(last, bucket);
        }
        if (last == 0) return firstSymbol;
        auto count = last;
        for (;;) {
            const auto chain = chains + (count - firstSymbol) * 4;
            _require(chain, 4, "GNU hash chain is out of bounds");
            ++count;
            if ((_read<std::uint32_t>(chain) & 1) != 0) return count;
        }
    }

    std::uint64_t _symbolCount() const {
        if (const auto size = _tags.find(DT_OS_SYMTABSZ); size != _tags.end()) {
            if (size->second % kSymEntrySize != 0 || *_symbols > _bytes.size() || size->second > _bytes.size() - *_symbols)
                throw RelinkerException("Invalid executable dynamic symbol table size");
            return size->second / kSymEntrySize;
        }
        if (const auto hash = _tags.find(DT_HASH); hash != _tags.end()) {
            const auto offset = _reader.TranslateVirtualAddress(hash->second);
            _require(offset, 8, "Hash table is out of bounds");
            return _read<std::uint32_t>(offset + 4);
        }
        if (const auto hash = _tags.find(kDtGnuHash); hash != _tags.end()) return _gnuHashSymbolCount(hash->second);
        return 0;
    }

    void _readSymbols() {
        if (!_value(DT_SYMTAB, DT_OS_SYMTAB, "DT_SYMTAB")) return;
        _symbols = _table(DT_SYMTAB, DT_OS_SYMTAB, "DT_SYMTAB");
        if (_required(DT_SYMENT, DT_OS_SYMENT, "DT_SYMENT") != kSymEntrySize) throw RelinkerException("Unsupported DT_SYMENT value");
        const auto count = _symbolCount();
        for (std::uint64_t index = 1; index < count; ++index) {
            const auto entry = _symbol(index);
            const auto section = _read<std::uint16_t>(entry + 6);
            if (section == SHN_UNDEF || section == kShnAbs) continue;
            _add(_read<std::uint64_t>(entry + 8));
        }
    }

    void _readRelocations(const RelocationTable& table) {
        const bool present = _value(table.AddressTag, table.OsAddressTag, table.AddressName) || _value(table.SizeTag, table.OsSizeTag, table.SizeName) || _value(table.EntryTag, table.OsEntryTag, table.EntryName);
        if (!present) return;
        const auto offset = _table(table.AddressTag, table.OsAddressTag, table.AddressName);
        const auto size = _required(table.SizeTag, table.OsSizeTag, table.SizeName);
        if (_required(table.EntryTag, table.OsEntryTag, table.EntryName) != table.EntryValue) throw RelinkerException(table.EntryMessage);
        if (size % kRelaEntrySize != 0) throw RelinkerException(table.SizeMessage);
        if (offset > _bytes.size() || size > _bytes.size() - offset) throw RelinkerException(table.BoundsMessage, offset);
        for (auto position = offset; position < offset + size; position += kRelaEntrySize) {
            const auto slot = _read<std::uint64_t>(position);
            const auto info = _read<std::uint64_t>(position + 8);
            const auto addend = _read<std::uint64_t>(position + 16);
            const auto type = static_cast<std::uint32_t>(info);
            const auto index = info >> 32;
            if (type == R_X86_64_RELATIVE) {
                if (index != 0) throw RelinkerException("RELATIVE relocation has a nonzero symbol index", position);
                _pointers[slot] = addend;
                _add(addend);
                continue;
            }
            if (type != R_X86_64_64 && type != R_X86_64_GLOB_DAT && type != R_X86_64_JUMP_SLOT) continue;
            std::uint64_t value = 0;
            if (index != 0) {
                const auto symbol = _symbol(index);
                const auto section = _read<std::uint16_t>(symbol + 6);
                if (section == SHN_UNDEF || section == kShnAbs) {
                    _importSlots.insert(slot);
                    continue;
                }
                value = _read<std::uint64_t>(symbol + 8);
            }
            const auto target = type == R_X86_64_64 ? value + addend : value;
            _pointers[slot] = target;
            _add(target);
        }
    }
};

}

std::vector<VirtualAddress> ReadIndirectBranchTargets(const IElfReader& reader) {
    return IndirectBranchTargetReader(reader).Read();
}

}
