#ifndef ELFPATCHER_MACOS_IMAGE_HPP
#define ELFPATCHER_MACOS_IMAGE_HPP

#include <elfpatcher/windows/WindowsLoadImage.hpp>
#include <codegen/CodegenTypes.hpp>
#include <domain/Types.hpp>
#include <cstdint>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

namespace Elfpatcher::MacOs {

inline constexpr std::uint64_t ExportKindAbsolute = 2;
inline constexpr std::uint64_t ExportWeakDefinition = 4;

// A flat-namespace bind of a pointer slot to a symbol (Mach-O spelling, with the leading underscore).
struct MacOsBind {
    std::string Symbol;
    std::uint32_t Rva;
    std::int64_t Addend = 0;
    bool Weak = false;
};

struct MacOsExport {
    std::string Symbol;
    std::uint64_t Value;
    std::uint64_t Flags = 0;
};

// A TLS variable another image reaches with general-dynamic access. The slot receives the defining
// image's module id (DTPMOD64) or the variable's offset plus the addend (DTPOFF64); the image
// initializer copies them from the TLS index the defining image exports under the symbol.
struct MacOsTlsImport {
    std::string Symbol;
    std::uint32_t Rva;
    bool Module;
    std::int64_t Addend = 0;
};

// An exported TLS variable: its symbol names a TLS index {module id, offset}, as on Windows.
struct MacOsTlsExport {
    std::string Symbol;
    std::uint64_t Offset;
    std::uint64_t Flags = 0;
};

struct MacOsTraceImport {
    std::uint32_t Rva;
    std::string Name;
    std::string Library;
};

// A guest image laid out by WindowsLoadImage (ImageBase + RVA, relocations already written) and what
// the Mach-O writer adds around it. dyld rebases the Rebases slots, binds the Binds slots and loads the
// Dylibs in order; flat-namespace lookups then search the images in that load order.
struct MacOsImageInput {
    bool Executable = true;
    std::string InstallName;
    const std::vector<std::uint8_t>* Source = nullptr;
    const std::vector<Domain::ProgramHeader>* Headers = nullptr;
    Windows::WindowsLoadImage* Image = nullptr;
    std::vector<std::uint32_t> Rebases;
    std::vector<MacOsBind> Binds;
    std::vector<MacOsExport> Exports;
    std::vector<std::string> Dylibs;
    std::vector<std::string> RunPaths;
    // Executables: where the entry stub hands over.
    std::uint32_t EntryRva = 0;
    // Guest modules: run from the image initializer with zero arguments, finalizers at exit or unload.
    std::uint32_t InitRva = 0;
    std::uint32_t FiniRva = 0;
    std::vector<std::uint32_t> InitArrayRvas;
    std::vector<std::uint32_t> FiniArrayRvas;
    // Slots that receive the image's TLS descriptor address (DTPMOD64 for the image's own TLS).
    std::vector<std::uint32_t> TlsModuleSlots;
    std::vector<MacOsTlsImport> TlsImports;
    std::vector<MacOsTlsExport> TlsExports;
    // --to-intel: AMD-only instructions that jump to an out-of-line stub (in __AMDSTUB).
    const std::vector<Codegen::TrampolineSite>* Trampolines = nullptr;
    bool TraceImports = false;
    std::vector<MacOsTraceImport> Traced;
    std::function<void(std::string_view)> Message;
};

// The size of the static TLS block the thread pointer follows (variant II), shared by the TLS stubs,
// TPOFF64 relocations and the runtime descriptor.
std::uint64_t GuestTlsBlockSize(const Domain::ProgramHeader& tls);

std::vector<std::uint8_t> WriteMacOsImage(MacOsImageInput& input);

// "$ORIGIN" rewritten to a dyld path prefix (@executable_path or @loader_path).
std::string MachOLoadPath(const std::string& path, const std::string& origin);
std::vector<std::string> MachORunPaths(const std::string& paths, const std::string& origin);

// A DT_NEEDED name as an LC_LOAD_DYLIB path: guest modules ($ORIGIN) beside the loader, prx libraries
// through the rpath.
std::string MachODependency(const std::string& name, const std::string& origin);

std::vector<std::string> ReadNeededLibraries(const Domain::SysVDynamicSection& dynamicSection);

}

#endif
