#include <cstddef>
#include "prx/libc/include/General.hpp"

extern "C" {

int APS5_VABI sceLibcBacktraceGetBufferSize_nid_postfix(int, int*, std::size_t*) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceLibcBacktraceSelf_nid_postfix(int, void*, std::size_t, int*) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}
