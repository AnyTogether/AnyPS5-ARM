#include "ElfFixture.hpp"
#include <relinker/analysis/IndirectBranchTargets.hpp>
#include <relinker/parsing/ElfReader.hpp>
#include <cstdint>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

using namespace RelinkerTests;
using Targets = std::vector<Relinker::VirtualAddress>;

void require(const bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

void requireFailure(const std::function<void()>& operation, const std::string& expected, const std::string& message) {
    try {
        operation();
    } catch (const Relinker::RelinkerException& error) {
        if (std::string(error.what()).find(expected) != std::string::npos) return;
        throw std::runtime_error(message + ": " + error.what());
    }
    throw std::runtime_error(message);
}

constexpr std::size_t kTagBase = kCodeOffset + kDynamicVaddr;
constexpr std::uint64_t kSymbolsVaddr = 0x400;
constexpr std::size_t kSymbols = kCodeOffset + kSymbolsVaddr;
constexpr std::size_t kRelocations = kCodeOffset + 0x700;
constexpr std::size_t kDynamicHeader = 64 + 56;
constexpr std::int64_t kDtHash = 4;
constexpr std::int64_t kDtSymtab = 6;
constexpr std::int64_t kDtRelasz = 8;
constexpr std::int64_t kDtInit = 12;
constexpr std::int64_t kDtFini = 13;
constexpr std::int64_t kDtPltrel = 20;
constexpr std::int64_t kDtPltrelsz = 2;
constexpr std::int64_t kDtJmprel = 23;
constexpr std::int64_t kDtOsRela = 0x6100002f;
constexpr std::int64_t kDtOsRelasz = 0x61000031;
constexpr std::int64_t kDtOsRelaent = 0x61000033;
constexpr std::int64_t kDtOsStrtab = 0x61000035;
constexpr std::int64_t kDtOsStrsz = 0x61000037;
constexpr std::int64_t kDtOsSymtab = 0x61000039;
constexpr std::int64_t kDtOsSyment = 0x6100003b;
constexpr std::int64_t kDtOsSymtabsz = 0x6100003f;
constexpr std::int64_t kDtGnuHash = 0x6ffffef5;
constexpr std::uint8_t kGlobalFunction = 0x12;
constexpr std::uint8_t kLocalFunction = 0x02;
constexpr std::uint8_t kGlobalObject = 0x11;
constexpr std::uint16_t kCodeSection = 1;
constexpr std::uint16_t kUndefined = 0;
constexpr std::uint16_t kAbsolute = 0xfff1;
constexpr std::uint32_t kRelative = 8;
constexpr std::uint32_t kAbsolute64 = 1;
constexpr std::uint32_t kGlobData = 6;
constexpr std::uint32_t kJumpSlot = 7;

void WriteTag(Bytes& image, const std::size_t index, const std::int64_t tag, const std::uint64_t value) {
    Write<std::int64_t>(image, kTagBase + index * 16, tag);
    Write<std::uint64_t>(image, kTagBase + index * 16 + 8, value);
}

void SetDynamicSize(Bytes& image, const std::size_t count) {
    Write<std::uint64_t>(image, kDynamicHeader + 32, count * 16);
    Write<std::uint64_t>(image, kDynamicHeader + 40, count * 16);
}

void WriteSymbol(Bytes& image, const std::size_t offset, const std::uint8_t info, const std::uint16_t section, const std::uint64_t value) {
    Write<std::uint32_t>(image, offset, 0);
    Write<std::uint8_t>(image, offset + 4, info);
    Write<std::uint8_t>(image, offset + 5, 0);
    Write<std::uint16_t>(image, offset + 6, section);
    Write<std::uint64_t>(image, offset + 8, value);
    Write<std::uint64_t>(image, offset + 16, 0);
}

void WriteRelocation(Bytes& image, const std::size_t offset, const std::uint64_t slot, const std::uint64_t info, const std::uint64_t addend) {
    Write<std::uint64_t>(image, offset, slot);
    Write<std::uint64_t>(image, offset + 8, info);
    Write<std::uint64_t>(image, offset + 16, addend);
}

Targets ReadTargets(const Bytes& image) {
    return Relinker::ReadIndirectBranchTargets(Relinker::ElfReader(image));
}

class Emitter {
public:
    Emitter(Bytes& image, const std::size_t fileOffset, const std::uint64_t address) : _image(image), _file(fileOffset), _address(address) {}

    void U8(const std::uint8_t value) {
        Write<std::uint8_t>(_image, _file, value);
        ++_file;
        ++_address;
    }

    void U32(const std::uint32_t value) {
        Write<std::uint32_t>(_image, _file, value);
        _file += 4;
        _address += 4;
    }

    void PcRel(const std::uint64_t target) {
        U32(static_cast<std::uint32_t>(static_cast<std::int32_t>(static_cast<std::int64_t>(target) - static_cast<std::int64_t>(_address))));
    }

    void DataRel(const std::uint64_t target, const std::uint64_t base) {
        U32(static_cast<std::uint32_t>(static_cast<std::int32_t>(static_cast<std::int64_t>(target) - static_cast<std::int64_t>(base))));
    }

    std::size_t BeginRecord() {
        const auto at = _file;
        U32(0);
        return at;
    }

    void EndRecord(const std::size_t at) {
        while ((_file - at) % 8 != 0) U8(0);
        Write<std::uint32_t>(_image, at, static_cast<std::uint32_t>(_file - at - 4));
    }

    [[nodiscard]] std::uint64_t Address() const { return _address; }

private:
    Bytes& _image;
    std::size_t _file;
    std::uint64_t _address;
};

constexpr std::uint64_t kFrameHeader = 0x800;
constexpr std::uint64_t kFrame = 0x900;
constexpr std::uint64_t kLsda = 0xA00;
constexpr std::uint64_t kFunction = 0x100;
constexpr std::uint64_t kFunctionSize = 0x20;
constexpr std::uint64_t kPersonality = 0x200;
constexpr std::uint64_t kLandingPad = 0x18;
constexpr std::uint8_t kPcRelSdata4 = 0x1B;
constexpr std::uint8_t kUdata4 = 0x03;
constexpr std::uint8_t kDataRelSdata4 = 0x3B;
constexpr std::uint8_t kOmit = 0xFF;
constexpr std::uint8_t kUleb128 = 0x01;

Bytes WithUnwindTable(const bool landingPad) {
    Bytes image = MakeExecutable(Bytes{0xC3});
    Emitter frame(image, kCodeOffset + kFrame, kFrame);
    const auto cie = frame.BeginRecord();
    frame.U32(0);
    frame.U8(1);
    for (const auto character : std::string(landingPad ? "zPLR" : "zR")) frame.U8(static_cast<std::uint8_t>(character));
    frame.U8(0);
    frame.U8(1);
    frame.U8(0x78);
    frame.U8(16);
    if (landingPad) {
        frame.U8(7);
        frame.U8(kPcRelSdata4);
        frame.PcRel(kPersonality);
        frame.U8(kPcRelSdata4);
    } else {
        frame.U8(1);
    }
    frame.U8(kPcRelSdata4);
    frame.EndRecord(cie);
    const auto fdeAddress = frame.Address();
    const auto fde = frame.BeginRecord();
    frame.U32(static_cast<std::uint32_t>(frame.Address() - kFrame));
    frame.PcRel(kFunction);
    frame.U32(kFunctionSize);
    if (landingPad) {
        frame.U8(4);
        frame.PcRel(kLsda);
    } else {
        frame.U8(0);
    }
    frame.EndRecord(fde);
    frame.U32(0);
    Emitter header(image, kCodeOffset + kFrameHeader, kFrameHeader);
    header.U8(1);
    header.U8(kPcRelSdata4);
    header.U8(kUdata4);
    header.U8(kDataRelSdata4);
    header.PcRel(kFrame);
    header.U32(1);
    header.DataRel(kFunction, kFrameHeader);
    header.DataRel(fdeAddress, kFrameHeader);
    WriteProgramHeader(image, 3, 0x6474E550, 4, kCodeOffset + kFrameHeader, kFrameHeader, header.Address() - kFrameHeader, 4);
    if (landingPad) {
        Emitter lsda(image, kCodeOffset + kLsda, kLsda);
        lsda.U8(kOmit);
        lsda.U8(kOmit);
        lsda.U8(kUleb128);
        lsda.U8(4);
        lsda.U8(0);
        lsda.U8(0x10);
        lsda.U8(kLandingPad);
        lsda.U8(0);
    }
    return image;
}

void entryPoint() {
    require(ReadTargets(MakeExecutable(Bytes{0xC3})).empty(), "An image without an entry point, symbols, relocations or unwind tables reported targets");
    Bytes image = MakeExecutable(Bytes{0xC3});
    Write<std::uint64_t>(image, 24, 0x10);
    require(ReadTargets(image) == Targets{0x10}, "The entry point was not reported");
    Write<std::uint64_t>(image, 24, kCodeSize);
    require(ReadTargets(image).empty(), "An entry point past the code segment was reported");
    Write<std::uint64_t>(image, 24, 0x2000);
    require(ReadTargets(image).empty(), "An entry point outside every code segment was reported");
}

void initializers() {
    Bytes image = MakeExecutable(Bytes{0xC3});
    WriteTag(image, 7, kDtInit, 0x20);
    WriteTag(image, 8, kDtFini, 0x30);
    WriteTag(image, 9, 0, 0);
    SetDynamicSize(image, 10);
    require(ReadTargets(image) == Targets{0x20, 0x30}, "DT_INIT and DT_FINI were not reported");
    WriteTag(image, 7, kDtInit, 0);
    require(ReadTargets(image) == Targets{0x30}, "A zero DT_INIT was reported");
}

void dynamicSymbols() {
    Bytes image = MakeExecutable(Bytes{0xC3});
    WriteTag(image, 2, kDtSymtab, kSymbolsVaddr);
    WriteTag(image, 7, kDtOsSymtabsz, 6 * 24);
    WriteTag(image, 8, 0, 0);
    SetDynamicSize(image, 9);
    WriteSymbol(image, kSymbols + 24, kGlobalFunction, kCodeSection, 0x40);
    WriteSymbol(image, kSymbols + 48, kGlobalObject, 2, 0x2000);
    WriteSymbol(image, kSymbols + 72, kGlobalFunction, kUndefined, 0x50);
    WriteSymbol(image, kSymbols + 96, kGlobalFunction, kAbsolute, 0x60);
    WriteSymbol(image, kSymbols + 120, kLocalFunction, kCodeSection, 0x70);
    require(ReadTargets(image) == Targets{0x40, 0x70}, "Defined symbols inside the code segment were not the reported targets");
    WriteTag(image, 7, kDtOsSymtabsz, 25);
    requireFailure([&] { (void)ReadTargets(image); }, "Invalid executable dynamic symbol table size", "A symbol table size that is not a multiple of the entry size was accepted");
    WriteTag(image, 7, kDtOsSymtabsz, 0x8000);
    requireFailure([&] { (void)ReadTargets(image); }, "Invalid executable dynamic symbol table size", "A symbol table exceeding the file was accepted");
    WriteTag(image, 7, kDtOsSymtab, 0x4620);
    WriteTag(image, 8, 0, 0);
    requireFailure([&] { (void)ReadTargets(image); }, "Both DT_OS_ and DT_ variants present for DT_SYMTAB", "Conflicting symbol table tags were accepted");
}

void hashSymbolCount() {
    Bytes image = MakeModule(Bytes{0xC3});
    constexpr std::size_t symbols = kModuleDataOffset + 0x100;
    Write<std::uint64_t>(image, kModuleDataOffset + 2 * 16 + 8, kModuleDataVaddr + 0x100);
    Write<std::uint32_t>(image, kModuleDataOffset + 0x244, 3);
    WriteSymbol(image, symbols + 24, kGlobalFunction, kCodeSection, 0x30);
    WriteSymbol(image, symbols + 48, kGlobalFunction, kCodeSection, 0x38);
    WriteSymbol(image, symbols + 72, kGlobalFunction, kCodeSection, 0x3C);
    require(ReadTargets(image) == Targets{0x30, 0x38}, "DT_HASH did not bound the module's symbol table");
}

void gnuHashSymbolCount() {
    Bytes image = MakeExecutable(Bytes{0xC3});
    constexpr std::size_t hash = kCodeOffset + 0x800;
    WriteTag(image, 2, kDtSymtab, kSymbolsVaddr);
    WriteTag(image, 7, kDtGnuHash, 0x800);
    WriteTag(image, 8, 0, 0);
    SetDynamicSize(image, 9);
    Write<std::uint32_t>(image, hash, 1);
    Write<std::uint32_t>(image, hash + 4, 2);
    Write<std::uint32_t>(image, hash + 8, 1);
    Write<std::uint32_t>(image, hash + 12, 0);
    Write<std::uint64_t>(image, hash + 16, 0);
    Write<std::uint32_t>(image, hash + 24, 2);
    Write<std::uint32_t>(image, hash + 28, 0x10);
    Write<std::uint32_t>(image, hash + 32, 0x21);
    for (std::size_t index = 1; index <= 4; ++index) WriteSymbol(image, kSymbols + index * 24, kGlobalFunction, kCodeSection, 0x40 + index * 8);
    require(ReadTargets(image) == Targets{0x48, 0x50, 0x58}, "DT_GNU_HASH chains did not bound the symbol table");
    Write<std::uint32_t>(image, hash + 24, 0);
    require(ReadTargets(image) == Targets{0x48}, "Empty DT_GNU_HASH buckets did not bound the symbol table at the first hashed symbol");
}

void relativeRelocations() {
    Bytes image = MakeExecutable(Bytes{0xC3});
    WriteTag(image, 5, kDtRelasz, 48);
    WriteRelocation(image, kRelocations, 0x780, kRelative, 0x80);
    WriteRelocation(image, kRelocations + 24, 0x788, kRelative, 0x3000);
    require(ReadTargets(image) == Targets{0x80}, "The RELATIVE addend inside the code segment was not the only reported target");
    WriteRelocation(image, kRelocations + 24, 0x788, (1ull << 32) | kRelative, 0x90);
    requireFailure([&] { (void)ReadTargets(image); }, "RELATIVE relocation has a nonzero symbol index", "A RELATIVE relocation with a symbol was accepted");
}

void symbolRelocations() {
    Bytes image = MakeExecutable(Bytes{0xC3});
    WriteTag(image, 2, kDtSymtab, kSymbolsVaddr);
    WriteTag(image, 5, kDtRelasz, 6 * 24);
    WriteTag(image, 7, kDtOsSymtabsz, 5 * 24);
    WriteTag(image, 8, 0, 0);
    SetDynamicSize(image, 9);
    WriteSymbol(image, kSymbols + 24, kGlobalFunction, kCodeSection, 0x40);
    WriteSymbol(image, kSymbols + 48, kGlobalFunction, kUndefined, 0);
    WriteSymbol(image, kSymbols + 72, kGlobalFunction, kCodeSection, 0x48);
    WriteSymbol(image, kSymbols + 96, kGlobalObject, kAbsolute, 0x58);
    WriteRelocation(image, kRelocations, 0x780, (1ull << 32) | kAbsolute64, 4);
    WriteRelocation(image, kRelocations + 24, 0x788, (3ull << 32) | kJumpSlot, 0);
    WriteRelocation(image, kRelocations + 48, 0x790, (2ull << 32) | kJumpSlot, 0);
    WriteRelocation(image, kRelocations + 72, 0x798, (3ull << 32) | kGlobData, 8);
    WriteRelocation(image, kRelocations + 96, 0x7A0, kAbsolute64, 0x50);
    WriteRelocation(image, kRelocations + 120, 0x7A8, (4ull << 32) | kAbsolute64, 0);
    require(ReadTargets(image) == Targets{0x40, 0x44, 0x48, 0x50}, "Symbol relocations did not resolve to the defined symbols' code addresses");
    WriteRelocation(image, kRelocations, 0x780, (0x10000000ull << 32) | kJumpSlot, 0);
    requireFailure([&] { (void)ReadTargets(image); }, "Symbol table entry out of bounds", "A relocation symbol outside the file was accepted");
}

void jumpSlotTable() {
    Bytes image = MakeExecutable(Bytes{0xC3});
    WriteTag(image, 2, kDtSymtab, kSymbolsVaddr);
    WriteTag(image, 7, kDtJmprel, 0x780);
    WriteTag(image, 8, kDtPltrelsz, 24);
    WriteTag(image, 9, kDtPltrel, 7);
    WriteTag(image, 10, kDtOsSymtabsz, 2 * 24);
    WriteTag(image, 11, 0, 0);
    SetDynamicSize(image, 12);
    WriteSymbol(image, kSymbols + 24, kGlobalFunction, kCodeSection, 0x40);
    WriteRelocation(image, kCodeOffset + 0x780, 0x7C0, (1ull << 32) | kJumpSlot, 0);
    require(ReadTargets(image) == Targets{0x40}, "The jump slot table was not read");
    WriteTag(image, 9, kDtPltrel, 4);
    requireFailure([&] { (void)ReadTargets(image); }, "Unsupported DT_PLTREL type", "A jump slot table without RELA entries was accepted");
}

void sceTables() {
    Bytes image = MakeExecutable(Bytes{0xC3});
    constexpr std::size_t base = 0x6000;
    WriteProgramHeader(image, 2, 0x61000000, 4, base, 0, 0x400, 8);
    const std::pair<std::int64_t, std::uint64_t> tags[] = {
        {kDtOsStrtab, 0}, {kDtOsStrsz, 1}, {kDtOsSymtab, 0x100}, {kDtOsSyment, 24}, {kDtOsSymtabsz, 2 * 24},
        {kDtOsRela, 0x200}, {kDtOsRelasz, 24}, {kDtOsRelaent, 24}, {0, 0}};
    for (std::size_t index = 0; index < sizeof(tags) / sizeof(tags[0]); ++index) WriteTag(image, index, tags[index].first, tags[index].second);
    SetDynamicSize(image, sizeof(tags) / sizeof(tags[0]));
    WriteSymbol(image, base + 0x100 + 24, kGlobalFunction, kCodeSection, 0x90);
    WriteRelocation(image, base + 0x200, 0x780, kRelative, 0xA0);
    require(ReadTargets(image) == Targets{0x90, 0xA0}, "SCE tables relative to PT_SCE_DYNLIBDATA were not read");
    WriteTag(image, 8, kDtSymtab, 0x620);
    WriteTag(image, 9, 0, 0);
    SetDynamicSize(image, 10);
    requireFailure([&] { (void)ReadTargets(image); }, "Both DT_OS_ and DT_ variants present for DT_SYMTAB", "Conflicting SCE and SysV symbol table tags were accepted");
}

void relocationBounds() {
    Bytes image = MakeExecutable(Bytes{0xC3});
    WriteTag(image, 4, kDtOsRela, 0x9000);
    requireFailure([&] { (void)ReadTargets(image); }, "Relocation table is out of bounds", "A relocation table past the end of the file was accepted");
    WriteTag(image, 4, kDtOsRela, 0x7FF0);
    WriteTag(image, 5, kDtOsRelasz, 48);
    requireFailure([&] { (void)ReadTargets(image); }, "Relocation table is out of bounds", "A relocation table that does not fit in the file was accepted");
    Bytes unmapped = MakeExecutable(Bytes{0xC3});
    WriteTag(unmapped, 4, 7, 0x2000);
    requireFailure([&] { (void)ReadTargets(unmapped); }, "Virtual address not mapped by any PT_LOAD segment", "A relocation table at an unmapped address was accepted");
}

void unwindFunctions() {
    require(ReadTargets(WithUnwindTable(false)) == Targets{kFunction}, "The FDE initial location was not reported");
    require(ReadTargets(WithUnwindTable(true)) == Targets{kFunction, kFunction + kLandingPad, kPersonality}, "The landing pad and the personality routine were not reported with the function");
}

void missingDynamicSegment() {
    Bytes image = MakeExecutable(Bytes{0xC3});
    Write<std::uint32_t>(image, kDynamicHeader, 0x6FFFFF01);
    requireFailure([&] { (void)ReadTargets(image); }, "No PT_DYNAMIC segment found", "An image without a dynamic segment was accepted");
}

}

int main() {
    try {
        entryPoint();
        initializers();
        dynamicSymbols();
        hashSymbolCount();
        gnuHashSymbolCount();
        relativeRelocations();
        symbolRelocations();
        jumpSlotTable();
        sceTables();
        relocationBounds();
        unwindFunctions();
        missingDynamicSegment();
        std::cout << "Indirect branch target tests passed\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
