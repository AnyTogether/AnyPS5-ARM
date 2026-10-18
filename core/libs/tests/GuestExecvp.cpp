#include "prx/libc/include/General.hpp"
#include <cstdlib>
#include <stdexcept>
#include <string>
extern "C" {
int APS5_VABI execvp_nid_postfix(const char*, char* const*);
int APS5_VABI execv_nid_postfix(const char*, char* const*);
int APS5_VABI execve_nid_postfix(const char*, char* const*, char* const*);
int* APS5_VABI __error_nid_postfix();
}
static void Require(bool value) { if (!value) std::abort(); }
static bool Fails(const char* file, char* const* arguments, int error) {
    *__error_nid_postfix() = 0;
    return execvp_nid_postfix(file, arguments) == -1 && *__error_nid_postfix() == error;
}
template <typename TCall> static bool Throws(TCall call, const std::string& message) {
    try {
        call();
    } catch (const std::runtime_error& error) {
        return error.what() == message;
    }
    return false;
}
int main() {
    char shell[] = "sh";
    char option[] = "-c";
    char command[] = "exit 0";
    char* arguments[] = {shell, option, command, nullptr};
    char variable[] = "HOME=/";
    char* environment[] = {variable, nullptr};
    Require(Fails("sh", arguments, 78));
    Require(Fails("/bin/sh", arguments, 78));
    Require(Fails("", arguments, 2));
    Require(Fails(nullptr, nullptr, 14));
    Require(Throws([&] { execv_nid_postfix("/bin/sh", arguments); }, "execv: executable replacement not implemented"));
    Require(Throws([&] { execve_nid_postfix("/bin/sh", arguments, environment); }, "execve: executable replacement not implemented"));
}
