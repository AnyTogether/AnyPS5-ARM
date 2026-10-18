#ifndef CORE_LIBS_PRX_LIBC_INCLUDE_GUESTVARARGS_HPP
#define CORE_LIBS_PRX_LIBC_INCLUDE_GUESTVARARGS_HPP

#include "SceTypes.hpp"

// The guest passes variadic arguments the System V way. Hosts whose own variadic ABI differs read
// them through a System V va_list (SceTypes.hpp VaList) with the Windows formatting and scanning
// code: Windows hosts declare the exports sysv_abi and start the list with the builtin, and native
// arm64 hosts ask the translator runtime for a list over the guest call that is running.
#if defined(_WIN32) || defined(__aarch64__)
#define APS5_SYSV_GUEST_ARGS 1
#else
#define APS5_SYSV_GUEST_ARGS 0
#endif

#if defined(_WIN32)
#define APS5_GUEST_VA_START(list, last, gp, fp) \
    __builtin_sysv_va_list list;                \
    __builtin_sysv_va_start(list, last)
#define APS5_GUEST_VA_END(list) __builtin_sysv_va_end(list)
#elif defined(__aarch64__)
namespace LibcDetail {
// Fills list over the arguments of the running guest call after gp integer and fp vector named
// ones; saveArea (176 bytes) holds the guest's argument registers while the list is read.
VaList* GuestVaStart(VaList* list, void* saveArea, unsigned gp, unsigned fp);
}
#define APS5_GUEST_VA_START(list, last, gp, fp)       \
    VaList list##Storage;                            \
    alignas(16) unsigned char list##Save[176];       \
    VaList* list = LibcDetail::GuestVaStart(&list##Storage, list##Save, gp, fp)
#define APS5_GUEST_VA_END(list) static_cast<void>(list)
#endif

#endif
