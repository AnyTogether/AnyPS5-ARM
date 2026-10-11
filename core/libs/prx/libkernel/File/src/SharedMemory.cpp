#include "prx/libc/include/General.hpp"
#include "prx/libkernel/File/include/FileFlags.hpp"

#include <cerrno>
#include <cstring>
#include <filesystem>
#include <mutex>
#include <stdexcept>
#include <string>
#include <unordered_map>

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#include <share.h>
#include <sys/stat.h>
#include <atomic>
#include <filesystem>
#include <random>
#else
#include <cstdlib>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#endif

extern "C" int* APS5_VABI __error_nid_postfix();

namespace {

constexpr int GuestNoEntry = 2;
constexpr int GuestNoMemory = 12;
constexpr int GuestFault = 14;
constexpr int GuestExists = 17;
constexpr int GuestInvalid = 22;
constexpr int GuestTooManyFilesInSystem = 23;
constexpr int GuestTooManyFiles = 24;
constexpr int GuestNameTooLong = 63;
constexpr std::size_t GuestMaxPath = 1024;
constexpr int GuestCloseOnExec = 0x00100000;
constexpr int AcceptedFlags = SCE_KERNEL_O_ACCMODE | SCE_KERNEL_O_CREAT | SCE_KERNEL_O_EXCL | SCE_KERNEL_O_TRUNC | GuestCloseOnExec;

const char* const anonymousObject = reinterpret_cast<const char*>(1);

int Fail(int error) {
    *__error_nid_postfix() = error;
    return -1;
}

int GuestError(int error) {
    switch (error) {
    case EMFILE:
        return GuestTooManyFiles;
    case ENFILE:
        return GuestTooManyFilesInSystem;
    case ENOMEM:
        return GuestNoMemory;
    case ENOENT:
        return GuestNoEntry;
    default:
        return 0;
    }
}

int CreateAnonymousFile() {
#ifdef _WIN32
    static std::atomic<unsigned> sequence{0};
    const auto directory = std::filesystem::temp_directory_path();
    const auto seed = std::to_string(std::random_device{}());
    for (int attempt = 0; attempt < 64; ++attempt) {
        const auto path = directory / ("anyps5-shm-" + seed + "-" + std::to_string(sequence++));
        int descriptor = -1;
        const int error = _wsopen_s(&descriptor, path.c_str(),
                                    _O_CREAT | _O_EXCL | _O_RDWR | _O_BINARY | _O_TEMPORARY | _O_SHORT_LIVED | _O_NOINHERIT,
                                    _SH_DENYNO, _S_IREAD | _S_IWRITE);
        if (error == 0) return descriptor;
        if (error != EEXIST) {
            errno = error;
            return -1;
        }
    }
    errno = EEXIST;
    return -1;
#elif defined(__APPLE__)
    // macOS has no memfd: an unlinked temporary file is the anonymous object.
    char path[] = "/tmp/anyps5-shm-XXXXXX";
    const int descriptor = ::mkstemp(path);
    if (descriptor < 0) return -1;
    ::unlink(path);
    ::fcntl(descriptor, F_SETFD, FD_CLOEXEC);
    return descriptor;
#else
    return memfd_create("anyps5 shm_open", MFD_CLOEXEC);
#endif
}

// A named object lives as long as the process (libkernel exports no shm_unlink), so each name is
// backed by a host file that every shm_open of that name reopens with its own access mode and
// offset, as separate descriptors of one FreeBSD shmfd behave.
class NamedObjects {
public:
    ~NamedObjects() {
        std::error_code ignored;
        for (const auto& [name, backing] : objects)
            std::filesystem::remove(backing, ignored);
    }

    std::mutex lock;
    std::unordered_map<std::string, std::filesystem::path> objects;
};

NamedObjects& Named() {
    static NamedObjects named;
    return named;
}

bool CreateBackingFile(std::filesystem::path& backing) {
#ifdef _WIN32
    static std::atomic<unsigned> sequence{0};
    const auto directory = std::filesystem::temp_directory_path();
    const auto seed = std::to_string(std::random_device{}());
    for (int attempt = 0; attempt < 64; ++attempt) {
        const auto path = directory / ("anyps5-shm-named-" + seed + "-" + std::to_string(sequence++));
        int descriptor = -1;
        const int error = _wsopen_s(&descriptor, path.c_str(), _O_CREAT | _O_EXCL | _O_RDWR | _O_BINARY, _SH_DENYNO, _S_IREAD | _S_IWRITE);
        if (error == 0) {
            _close(descriptor);
            backing = path;
            return true;
        }
        if (error != EEXIST) {
            errno = error;
            return false;
        }
    }
    errno = EEXIST;
    return false;
#else
    std::string path = (std::filesystem::temp_directory_path() / "anyps5-shm-named-XXXXXX").string();
    const int descriptor = ::mkstemp(path.data());
    if (descriptor < 0) return false;
    ::close(descriptor);
    backing = path;
    return true;
#endif
}

int OpenBackingFile(const std::filesystem::path& backing, bool writable) {
#ifdef _WIN32
    int descriptor = -1;
    const int error = _wsopen_s(&descriptor, backing.c_str(), (writable ? _O_RDWR : _O_RDONLY) | _O_BINARY | _O_NOINHERIT, _SH_DENYNO, 0);
    if (error != 0) {
        errno = error;
        return -1;
    }
    return descriptor;
#else
    return ::open(backing.c_str(), (writable ? O_RDWR : O_RDONLY) | O_CLOEXEC);
#endif
}

int TruncateToEmpty(int descriptor) {
#ifdef _WIN32
    const int error = _chsize_s(descriptor, 0);
    if (error != 0) errno = error;
    return error == 0 ? 0 : -1;
#else
    return ::ftruncate(descriptor, 0);
#endif
}

int HostFailure(const char* what) {
    const int error = errno;
    if (const int guest = GuestError(error)) return Fail(guest);
    throw std::runtime_error(std::string("shm_open: ") + what + " failed, errno=" + std::to_string(error));
}

int OpenNamed(const char* path, int flags) {
    if (path == nullptr) return Fail(GuestFault);
    if (std::strlen(path) >= GuestMaxPath) return Fail(GuestNameTooLong);
    const bool writable = (flags & SCE_KERNEL_O_ACCMODE) == SCE_KERNEL_O_RDWR;
    auto& named = Named();
    std::lock_guard guard(named.lock);
    auto found = named.objects.find(path);
    if (found == named.objects.end()) {
        if ((flags & SCE_KERNEL_O_CREAT) == 0) return Fail(GuestNoEntry);
        std::filesystem::path backing;
        if (!CreateBackingFile(backing)) return HostFailure("creating the host backing file");
        found = named.objects.emplace(path, std::move(backing)).first;
    } else {
        if ((flags & (SCE_KERNEL_O_CREAT | SCE_KERNEL_O_EXCL)) == (SCE_KERNEL_O_CREAT | SCE_KERNEL_O_EXCL)) return Fail(GuestExists);
    }
    const int descriptor = OpenBackingFile(found->second, writable);
    if (descriptor < 0) return HostFailure("opening the host backing file");
    // FreeBSD truncates an existing object only for a read-write open; O_TRUNC is ignored otherwise.
    if (writable && (flags & SCE_KERNEL_O_TRUNC) != 0 && TruncateToEmpty(descriptor) != 0) {
        const int error = errno;
#ifdef _WIN32
        _close(descriptor);
#else
        ::close(descriptor);
#endif
        errno = error;
        return HostFailure("truncating the named object");
    }
    return descriptor;
}

}

extern "C" int APS5_VABI shm_open_nid_postfix(const char* path, int flags, int) {
    const int accessMode = flags & SCE_KERNEL_O_ACCMODE;
    if (accessMode != SCE_KERNEL_O_RDONLY && accessMode != SCE_KERNEL_O_RDWR) return Fail(GuestInvalid);
    if ((flags & ~AcceptedFlags) != 0) return Fail(GuestInvalid);
    if (path != anonymousObject) return OpenNamed(path, flags);
    if (accessMode == SCE_KERNEL_O_RDONLY) return Fail(GuestInvalid);
    const int descriptor = CreateAnonymousFile();
    if (descriptor >= 0) return descriptor;
    const int error = errno;
    if (const int guest = GuestError(error)) return Fail(guest);
    throw std::runtime_error("shm_open: creating the host anonymous file failed, errno=" + std::to_string(error));
}
