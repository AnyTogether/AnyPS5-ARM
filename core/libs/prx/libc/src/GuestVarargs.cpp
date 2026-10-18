#include "prx/libc/include/GuestVarargs.hpp"
#include "prx/libc/include/General.hpp"

#if defined(__aarch64__)

#include <dlfcn.h>

namespace LibcDetail {

// The translator runtime (tools/translator/runtime/Runtime.cpp) lives in the translated executable.
VaList* GuestVaStart(VaList* list, void* saveArea, unsigned gp, unsigned fp) {
    using Start = int (*)(VaList*, void*, unsigned, unsigned);
    static const auto start = reinterpret_cast<Start>(dlsym(RTLD_DEFAULT, "aps5_guest_va_start"));
    if (start == nullptr || start(list, saveArea, gp, fp) != 0) NotImplemented_nid_no_patch("variadic call outside translated guest code");
    return list;
}

}

#endif
