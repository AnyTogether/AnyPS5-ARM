#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdlib>
#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif
extern "C" {
int APS5_VABI getpid_nid_postfix(void);
int APS5_VABI getppid_nid_postfix(void);
}
static void Require(bool value) { if (!value) std::abort(); }
int main() {
    const int parent = getppid_nid_postfix();
    Require(parent > 0 && parent != getpid_nid_postfix());
    Require(getppid_nid_postfix() == parent);
#ifdef _WIN32
    const HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, static_cast<DWORD>(parent));
    Require(process != nullptr);
    CloseHandle(process);
#else
    Require(parent == static_cast<int>(::getppid()));
#endif
    return 0;
}
