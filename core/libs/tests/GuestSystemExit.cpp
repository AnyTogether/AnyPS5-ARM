#include "prx/libc/include/general/VabiMacros.hpp"
#include "prx/libc/include/Shutdown.hpp"
#include "prx/libSceSystemService/SystemService.hpp"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <cstring>
#include <string>
#include <thread>
#ifdef __APPLE__
#include "prx/libc/include/specifics/macos/ExecutablePath.hpp"
#endif
#ifdef _WIN32
#include <windows.h>
#else
#include <sys/wait.h>
#include <unistd.h>
#endif
extern "C" int APS5_VABI sceSystemServiceLoadExec(const char*, const char* const*);
extern "C" int APS5_VABI __cxa_atexit_nid_postfix(void (APS5_VABI *func)(void*), void* arg, void* dsoHandle);
extern "C" void APS5_VABI _Exit_nid_postfix(int);
extern "C" void APS5_VABI catchReturnFromMain_nid_postfix(int);
using GuestQuickExitCallback = void (APS5_VABI*)();
extern "C" int APS5_VABI at_quick_exit_nid_postfix(GuestQuickExitCallback);
extern "C" void APS5_VABI quick_exit_nid_postfix(int);
namespace {
bool cleaned = false;
bool finalized = false;
void Cleanup() { cleaned = true; }
void APS5_VABI Finalize(void*) { finalized = true; }
void VerifyExit() {
    if (!cleaned || !finalized) std::_Exit(1);
    std::puts("Guest shutdown and atexit completed");
}
int quickOrder = 0;
void APS5_VABI QuickSecond() { quickOrder = 1; }
void APS5_VABI QuickFirst() {
    if (quickOrder != 1) std::_Exit(1);
    std::puts("Guest quick_exit handlers completed");
    std::fflush(stdout);
}
void Require(bool value) { if (!value) std::abort(); }
void UnexpectedCleanup() { std::_Exit(3); }
#ifdef _WIN32
void WINAPI UnexpectedDetach(PVOID) { TerminateProcess(GetCurrentProcess(), 4); }
#endif
constexpr char RelaunchMarker[] = "ANYPS5_TEST_RELAUNCH_MARKER";
constexpr char MainExecutable[] = "ANYPS5_TEST_MAIN_EXECUTABLE";
void SetVariable(const char* name, const char* value) {
#ifdef _WIN32
    Require(SetEnvironmentVariableA(name, value) != 0);
    Require(_putenv_s(name, value) == 0);
#else
    Require(setenv(name, value, 1) == 0);
#endif
}
std::filesystem::path OwnExecutable() {
#ifdef _WIN32
    std::wstring executable(32768, L'\0');
    executable.resize(GetModuleFileNameW(nullptr, executable.data(), static_cast<DWORD>(executable.size())));
    return executable;
#elif defined(__APPLE__)
    return MacOsExecutablePath();
#else
    return std::filesystem::read_symlink("/proc/self/exe");
#endif
}
void AppendMarker(const std::string& line) {
    const char* marker = std::getenv(RelaunchMarker);
    Require(marker != nullptr);
    std::ofstream(marker, std::ios::app) << line << '\n';
}
void MainShutdown() { AppendMarker("shutdown"); }
void SecondaryShutdown() { AppendMarker("secondary shutdown"); }
int RunRelaunchingChild(const std::filesystem::path& self) {
#ifdef _WIN32
    std::wstring commandLine = L"\"" + self.wstring() + L"\" --relaunch";
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    Require(CreateProcessW(self.c_str(), commandLine.data(), nullptr, nullptr, TRUE, 0, nullptr, nullptr, &startup, &process) != 0);
    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(process.hProcess, &code);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return static_cast<int>(code);
#else
    const pid_t child = fork();
    Require(child >= 0);
    if (child == 0) {
        execl(self.c_str(), self.c_str(), "--relaunch", static_cast<char*>(nullptr));
        std::_Exit(127);
    }
    int status = 0;
    Require(waitpid(child, &status, 0) == child);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
#endif
}
int DriveRelaunch() {
    const auto self = OwnExecutable();
    const auto secondary = self.parent_path() / ("picker.picker.bin" + self.extension().string());
    std::filesystem::copy_file(self, secondary, std::filesystem::copy_options::overwrite_existing);
    const auto marker = std::filesystem::temp_directory_path() / ("anyps5-relaunch-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()) + ".txt");
    SetVariable(RelaunchMarker, marker.string().c_str());
    SetVariable(MainExecutable, self.string().c_str());
    Require(RunRelaunchingChild(self) == 0);
    std::string text;
    for (int attempt = 0; attempt < 200 && text.find("relaunched") == std::string::npos; ++attempt) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        std::ifstream file(marker);
        text.assign(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
    }
    std::error_code ignored;
    std::filesystem::remove(marker, ignored);
    for (int attempt = 0; attempt < 100 && std::filesystem::exists(secondary) && !std::filesystem::remove(secondary, ignored); ++attempt)
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    Require(text == "shutdown\narguments: --secondary|two words|quote\"d\\|\nsecondary shutdown\nrelaunched\n");
    std::puts("Guest relaunch completed");
    return 0;
}
}
int main(int argc, char** argv) {
    if (argc > 1 && std::strcmp(argv[1], "--immediate") == 0) {
        LibcRegisterShutdown_nid_postfix(UnexpectedCleanup);
        Require(std::atexit(UnexpectedCleanup) == 0);
#ifdef _WIN32
        auto slot = FlsAlloc(UnexpectedDetach);
        Require(slot != FLS_OUT_OF_INDEXES && FlsSetValue(slot, &slot));
#endif
        _Exit_nid_postfix(0);
        return 2;
    }
    if (argc > 1 && std::strcmp(argv[1], "--return-from-main") == 0) {
        catchReturnFromMain_nid_postfix(0);
        return 2;
    }
    if (argc > 1 && std::strcmp(argv[1], "--quick-exit") == 0) {
        Require(at_quick_exit_nid_postfix(QuickFirst) == 0);
        Require(at_quick_exit_nid_postfix(QuickSecond) == 0);
        quick_exit_nid_postfix(0);
        return 2;
    }
    if (argc > 1 && std::strcmp(argv[1], "--relaunch-driver") == 0) {
        return DriveRelaunch();
    }
    if (argc > 1 && std::strcmp(argv[1], "--relaunch") == 0) {
        LibcRegisterShutdown_nid_postfix(MainShutdown);
        const char* const arguments[] = {"--secondary", "two words", "quote\"d\\", "", nullptr};
        sceSystemServiceLoadExec("/app0/picker/picker.bin", arguments);
        return 2;
    }
    if (argc > 1 && std::strcmp(argv[1], "--secondary") == 0) {
        Require(OwnExecutable().filename().string().starts_with("picker.picker.bin"));
        std::string received = "arguments:";
        for (int index = 1; index < argc; ++index) received += std::string(index == 1 ? " " : "|") + argv[index];
        AppendMarker(received);
        LibcRegisterShutdown_nid_postfix(SecondaryShutdown);
        const char* const arguments[] = {"--relaunched", nullptr};
        sceSystemServiceLoadExec("/app0/eboot.bin", arguments);
        return 2;
    }
    if (argc > 1 && std::strcmp(argv[1], "--relaunched") == 0) {
        const char* main = std::getenv(MainExecutable);
        Require(main != nullptr && std::filesystem::equivalent(OwnExecutable(), main));
        AppendMarker("relaunched");
        return 0;
    }
    if (argc > 1) {
        LibcRegisterShutdown_nid_postfix(Cleanup);
        Require(__cxa_atexit_nid_postfix(Finalize, nullptr, nullptr) == 0);
        Require(std::atexit(VerifyExit) == 0);
        sceSystemServiceLoadExec("exit", nullptr);
        return 2;
    }
    Require(sceSystemServiceLoadExec(nullptr, nullptr) == SYSTEM_SERVICE_ERROR_PARAMETER);
    Require(sceSystemServiceLoadExec("", nullptr) == SYSTEM_SERVICE_ERROR_PARAMETER);
    for (const char* path : {"/app0/another.bin", "/data/eboot.bin", "/app0/../eboot.bin", "/app0//eboot.bin"}) {
        bool rejected = false;
        try { sceSystemServiceLoadExec(path, nullptr); }
        catch (const std::runtime_error&) { rejected = true; }
        Require(rejected);
    }
#ifdef _WIN32
    Require(GetEnvironmentVariableA("APS5_EBOOT", nullptr, 0) == 0);
#else
    Require(std::getenv("APS5_EBOOT") == nullptr);
#endif
}
