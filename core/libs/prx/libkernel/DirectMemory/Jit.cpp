#include "prx/libkernel/include/Api.hpp"
#include "prx/libc/include/General.hpp"
#include "prx/libc/include/GuestArena.hpp"
#include "prx/libkernel/DirectMemory/DirectMemory.hpp"

#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <system_error>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#include <atomic>
#include <filesystem>
#else
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#ifdef __APPLE__
#include <filesystem>
#endif
#endif
#ifdef __APPLE__
#include "prx/libc/include/GuestWriteWatch.hpp"
#include <atomic>
#include <cstdio>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <stdexcept>
#endif

namespace {

constexpr int CpuRead = 0x1;
constexpr int CpuWrite = 0x2;
constexpr int CpuExecute = 0x4;
constexpr int CpuProtection = CpuRead | CpuWrite | CpuExecute;

int Granted(int protection) {
    return (protection & (CpuWrite | CpuExecute)) != 0 ? protection | CpuRead : protection;
}

int KernelError(int error) {
    switch (error) {
    case EMFILE:
        return SCE_KERNEL_ERROR_EMFILE;
    case ENFILE:
        return SCE_KERNEL_ERROR_ENFILE;
    case ENOMEM:
    case ENOSPC:
        return SCE_KERNEL_ERROR_ENOMEM;
    default:
        return 0;
    }
}

int HostFailure(const char* operation, int error) {
    if (const int kernel = KernelError(error)) return kernel;
    throw std::system_error(error, std::generic_category(), operation);
}

class JitObject {
public:
#ifdef _WIN32
    JitObject(std::size_t bytes, HANDLE section) : bytes(bytes), section(section) {}
    ~JitObject() {
        GuestArena::GuestArenaForgetSection_nid_postfix(section);
        CloseHandle(section);
    }
#elif defined(__APPLE__)
    JitObject(std::size_t bytes, void* memory) : bytes(bytes), memory(memory) {}
    ~JitObject() { ::munmap(memory, bytes); }
#else
    explicit JitObject(std::size_t bytes) : bytes(bytes) {}
#endif
    JitObject(const JitObject&) = delete;
    JitObject& operator=(const JitObject&) = delete;

    std::size_t Bytes() const { return bytes; }

#ifdef __APPLE__
    void* Memory() const { return memory; }
#else
    HostSharedMemory Host(int descriptor) const {
#ifdef _WIN32
        static_cast<void>(descriptor);
        return section;
#else
        return descriptor;
#endif
    }
#endif

private:
    std::size_t bytes;
#ifdef _WIN32
    HANDLE section;
#elif defined(__APPLE__)
    void* memory;
#endif
};

struct JitDescriptor {
    std::shared_ptr<JitObject> object;
    int maxProtection;
};

std::mutex g_jitLock;
std::map<int, JitDescriptor> g_jitDescriptors;

#ifdef _WIN32
int WindowsFailure(const char* operation, DWORD error) {
    if (error == ERROR_NOT_ENOUGH_MEMORY || error == ERROR_COMMITMENT_LIMIT || error == ERROR_DISK_FULL) return SCE_KERNEL_ERROR_ENOMEM;
    throw std::system_error(static_cast<int>(error), std::system_category(), operation);
}

std::filesystem::path BackingPath() {
    static std::atomic<std::uint64_t> sequence{0};
    LARGE_INTEGER counter{};
    QueryPerformanceCounter(&counter);
    const auto name = "anyps5-jit-" + std::to_string(GetCurrentProcessId()) + "-" + std::to_string(sequence++) + "-" + std::to_string(counter.QuadPart);
    return std::filesystem::temp_directory_path() / name;
}

int CreateBacking(std::size_t bytes, int* descriptor, std::shared_ptr<JitObject>* object) {
    HANDLE file = CreateFileW(BackingPath().c_str(), GENERIC_READ | GENERIC_WRITE | GENERIC_EXECUTE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, CREATE_NEW,
                              FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE, nullptr);
    if (file == INVALID_HANDLE_VALUE) throw std::system_error(static_cast<int>(GetLastError()), std::system_category(), "create JIT shared memory file");
    const auto size = static_cast<std::uint64_t>(bytes);
    HANDLE section = CreateFileMappingW(file, nullptr, PAGE_EXECUTE_READWRITE, static_cast<DWORD>(size >> 32), static_cast<DWORD>(size), nullptr);
    if (section == nullptr) {
        const DWORD error = GetLastError();
        CloseHandle(file);
        return WindowsFailure("create JIT shared memory section", error);
    }
    auto created = std::make_shared<JitObject>(bytes, section);
    const int opened = _open_osfhandle(reinterpret_cast<std::intptr_t>(file), _O_BINARY);
    if (opened < 0) {
        const int error = errno;
        CloseHandle(file);
        return HostFailure("open JIT shared memory descriptor", error);
    }
    *descriptor = opened;
    *object = std::move(created);
    return 0;
}

int DuplicateDescriptor(int descriptor) {
    return _dup(descriptor);
}
#else
#ifdef __APPLE__
// Under Rosetta no descriptor maps runnable code: a PROT_EXEC mapping of a regular file is refused (EPERM) and
// code in a POSIX shared memory mapping faults when run. The object's memory is anonymous shared memory that
// every view aliases (MapView); the descriptor is an unlinked shared memory object of the same size that names
// the object: fstat sees its size, and read and write on it fail (ENXIO) rather than reach other contents.
int CreateBacking(std::size_t bytes, int* descriptor, std::shared_ptr<JitObject>* object) {
    static std::atomic<unsigned> sequence{0};
    char name[32];
    std::snprintf(name, sizeof(name), "/aps5-jit-%d-%u", static_cast<int>(::getpid()), sequence.fetch_add(1));
    const int file = ::shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0600);
    if (file < 0) return HostFailure("create JIT shared memory", errno);
    ::shm_unlink(name);
    ::fcntl(file, F_SETFD, FD_CLOEXEC);
    const bool representable = bytes <= static_cast<std::uint64_t>(std::numeric_limits<off_t>::max());
    if (!representable || ftruncate(file, static_cast<off_t>(bytes)) != 0) {
        const int error = !representable || errno == EFBIG ? ENOMEM : errno;
        ::close(file);
        return HostFailure("size JIT shared memory", error);
    }
    void* memory = ::mmap(nullptr, bytes, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANON, -1, 0);
    if (memory == MAP_FAILED) {
        const int error = errno;
        ::close(file);
        return HostFailure("allocate JIT shared memory", error);
    }
    *descriptor = file;
    *object = std::make_shared<JitObject>(bytes, memory);
    return 0;
}

int NativeProtection(int protection) {
    const int granted = Granted(protection);
    return ((granted & CpuRead) != 0 ? PROT_READ : 0) | ((granted & CpuWrite) != 0 ? PROT_WRITE : 0) | ((granted & CpuExecute) != 0 ? PROT_EXEC : 0);
}

// Places the view as anonymous guest memory, then replaces its pages with an alias of the object's memory.
// Rosetta keeps the translation of code it ran through a view after a store through another view, so code a JIT
// rewrites in place after running it stays stale until the executable view's protection changes.
int MapView(void** address, const JitObject& object, int protection) {
    const std::size_t bytes = object.Bytes();
    if (const int result = DoMapAnon(address, bytes, protection, 0)) return result;
    GuestWriteWatch::GuestWriteWatchUnregister_nid_postfix(*address, bytes);
    auto view = reinterpret_cast<mach_vm_address_t>(*address);
    vm_prot_t current = VM_PROT_NONE;
    vm_prot_t maximum = VM_PROT_NONE;
    const kern_return_t remapped = mach_vm_remap(mach_task_self(), &view, bytes, 0, VM_FLAGS_FIXED | VM_FLAGS_OVERWRITE, mach_task_self(),
                                                 reinterpret_cast<mach_vm_address_t>(object.Memory()), FALSE, &current, &maximum, VM_INHERIT_SHARE);
    if (remapped != KERN_SUCCESS) {
        DoMunmap(*address, bytes);
        throw std::runtime_error(std::string("map JIT shared memory: mach_vm_remap failed: ") + mach_error_string(remapped));
    }
    if (::mprotect(*address, bytes, NativeProtection(protection)) != 0) {
        const int error = errno;
        DoMunmap(*address, bytes);
        throw std::system_error(error, std::generic_category(), "protect JIT shared memory view");
    }
    return 0;
}
#else
int CreateBacking(std::size_t bytes, int* descriptor, std::shared_ptr<JitObject>* object) {
#ifdef __APPLE__
    auto path = (std::filesystem::temp_directory_path() / "anyps5-jit-XXXXXX").string();
    const int file = mkstemp(path.data());
    if (file < 0) return HostFailure("create JIT shared memory", errno);
    if (unlink(path.c_str()) != 0 || fcntl(file, F_SETFD, FD_CLOEXEC) != 0) {
        const int error = errno;
        ::close(file);
        return HostFailure("create JIT shared memory", error);
    }
#else
    const int file = memfd_create("anyps5 jit shared memory", MFD_CLOEXEC);
    if (file < 0) return HostFailure("create JIT shared memory", errno);
#endif
    const bool representable = bytes <= static_cast<std::uint64_t>(std::numeric_limits<off_t>::max());
    if (!representable || ftruncate(file, static_cast<off_t>(bytes)) != 0) {
        const int error = !representable || errno == EFBIG ? ENOMEM : errno;
        ::close(file);
        return HostFailure("size JIT shared memory", error);
    }
    *descriptor = file;
    *object = std::make_shared<JitObject>(bytes);
    return 0;
}
#endif

int DuplicateDescriptor(int descriptor) {
    return fcntl(descriptor, F_DUPFD_CLOEXEC, 0);
}
#endif

}

void ForgetJitSharedMemory(int descriptor) {
    std::lock_guard lock(g_jitLock);
    g_jitDescriptors.erase(descriptor);
}

void DuplicateJitSharedMemory(int from, int to) {
    std::lock_guard lock(g_jitLock);
    g_jitDescriptors.erase(to);
    const auto source = g_jitDescriptors.find(from);
    if (source != g_jitDescriptors.end()) g_jitDescriptors.emplace(to, source->second);
}

extern "C" {

int APS5_VABI sceKernelJitCreateSharedMemory(const char* name, std::size_t len, int maxProt, int* fdOut) {
    static_cast<void>(name);
    if (fdOut == nullptr || len == 0 || (len & (PS5_PAGE_SIZE - 1)) != 0 || (maxProt & ~CpuProtection) != 0) return SCE_KERNEL_ERROR_EINVAL;
    int descriptor = -1;
    std::shared_ptr<JitObject> object;
    if (const int result = CreateBacking(len, &descriptor, &object)) return result;
    std::lock_guard lock(g_jitLock);
    g_jitDescriptors.insert_or_assign(descriptor, JitDescriptor{std::move(object), maxProt});
    *fdOut = descriptor;
    return 0;
}

int APS5_VABI sceKernelJitCreateAliasOfSharedMemory(int fd, int maxProt, int* fdOut) {
    if (fdOut == nullptr || (maxProt & ~CpuProtection) != 0) return SCE_KERNEL_ERROR_EINVAL;
    std::lock_guard lock(g_jitLock);
    const auto source = g_jitDescriptors.find(fd);
    if (source == g_jitDescriptors.end()) return SCE_KERNEL_ERROR_EBADF;
    if ((Granted(maxProt) & ~Granted(source->second.maxProtection)) != 0) return SCE_KERNEL_ERROR_EACCES;
    const int alias = DuplicateDescriptor(fd);
    if (alias < 0) return HostFailure("duplicate JIT shared memory descriptor", errno);
    g_jitDescriptors.insert_or_assign(alias, JitDescriptor{source->second.object, maxProt});
    *fdOut = alias;
    return 0;
}

int APS5_VABI sceKernelJitMapSharedMemory(int fd, int prot, void** startOut) {
    if (startOut == nullptr || (prot & ~CpuProtection) != 0) return SCE_KERNEL_ERROR_EINVAL;
    std::lock_guard lock(g_jitLock);
    const auto found = g_jitDescriptors.find(fd);
    if (found == g_jitDescriptors.end()) return SCE_KERNEL_ERROR_EBADF;
    if ((Granted(prot) & ~Granted(found->second.maxProtection)) != 0) return SCE_KERNEL_ERROR_EACCES;
    const auto& object = *found->second.object;
    void* address = *startOut;
    std::uintptr_t arenaBase = 0;
    std::size_t arenaBytes = 0;
    GuestArena::GuestArenaRange_nid_postfix(&arenaBase, &arenaBytes);
    if (arenaBytes != 0 && reinterpret_cast<std::uintptr_t>(address) - arenaBase >= arenaBytes) address = nullptr;
#ifdef __APPLE__
    if (const int result = MapView(&address, object, prot)) return result;
#else
    if (const int result = DoMapShared(&address, object.Bytes(), prot, object.Host(fd))) return result;
#endif
    *startOut = address;
    return 0;
}

}
