#include "prx/libc/include/FileStream.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include <array>
#include <cerrno>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <fcntl.h>
#ifdef _WIN32
#include <io.h>
#else
#include <unistd.h>
#endif

extern "C" {
FileStream* APS5_VABI fopen_nid_postfix(const char* filename, const char* mode);
FileStream* APS5_VABI freopen_nid_postfix(const char* filename, const char* mode, FileStream* stream);
int APS5_VABI fclose_nid_postfix(FileStream* stream);
std::size_t APS5_VABI fread_nid_postfix(void* buffer, std::size_t size, std::size_t count, FileStream* stream);
std::size_t APS5_VABI fwrite_nid_postfix(const void* buffer, std::size_t size, std::size_t count, FileStream* stream);
int APS5_VABI fseek_nid_postfix(FileStream* stream, std::int64_t offset, int origin);
std::int64_t APS5_VABI ftell_nid_postfix(FileStream* stream);
int APS5_VABI fputs_nid_postfix(const char* str, FileStream* stream);
int APS5_VABI fflush_nid_postfix(FileStream* stream);
int APS5_VABI remove_nid_postfix(const char* path);
int APS5_VABI rename_nid_postfix(const char* from, const char* to);
int APS5_VABI ferror_nid_postfix(FileStream* stream);
void APS5_VABI clearerr_nid_postfix(FileStream* stream);
}

static void Require(bool condition) {
    if (!condition) throw std::runtime_error("File stream check failed");
}

template<typename TAction>
static void ExpectException(TAction action) {
    try {
        action();
    } catch (const std::runtime_error&) {
        return;
    }
    throw std::runtime_error("Expected a stream exception");
}

static void ReplaceWithReadOnlyDescriptor(FileStream* stream, const char* path) {
#ifdef _WIN32
    const int descriptor = _open(path, _O_RDONLY | _O_BINARY);
    Require(descriptor >= 0 && _dup2(descriptor, _fileno(GetNativeStream(stream))) == 0);
    Require(_close(descriptor) == 0);
#else
    const int descriptor = open(path, O_RDONLY);
    Require(descriptor >= 0 && dup2(descriptor, fileno(GetNativeStream(stream))) >= 0);
    Require(close(descriptor) == 0);
#endif
}

int main(int argc, char** argv) {
    Require(argc == 2);
    Require(_Stdout_nid_postfix.GetHandle() == stdout);
    Require(_Stderr_nid_postfix.GetHandle() == stderr);
    Require(fputs_nid_postfix("stdout object works\n", &_Stdout_nid_postfix) >= 0);
    Require(fputs_nid_postfix("stderr object works\n", &_Stderr_nid_postfix) >= 0);
    Require(fflush_nid_postfix(nullptr) == 0);
    auto* stream = fopen_nid_postfix(argv[1], "w+b");
    constexpr char payload[] = "stream round trip";
    Require(fputs_nid_postfix(payload, stream) >= 0);
    Require(fwrite_nid_postfix(payload, 1, sizeof(payload), stream) == sizeof(payload));
    const auto expectedSize = sizeof(payload) * 2 - 1;
    Require(ftell_nid_postfix(stream) == static_cast<long>(expectedSize));
    Require(fflush_nid_postfix(stream) == 0);
    Require(fseek_nid_postfix(stream, 0, SEEK_SET) == 0);
    std::array<char, sizeof(payload)> buffer{};
    Require(fread_nid_postfix(buffer.data(), 1, sizeof(payload) - 1, stream) == sizeof(payload) - 1);
    Require(std::strcmp(buffer.data(), payload) == 0);
    Require(fread_nid_postfix(buffer.data(), 1, buffer.size(), stream) == buffer.size());
    Require(std::strcmp(buffer.data(), payload) == 0);
    Require(fread_nid_postfix(buffer.data(), 1, buffer.size(), stream) == 0);
    ExpectException([&] { fputs_nid_postfix(nullptr, stream); });
    ExpectException([&] { fwrite_nid_postfix(nullptr, 1, sizeof(payload), stream); });
    errno = 0;
    Require(fseek_nid_postfix(stream, 0, -1) == -1);
    Require(errno == EINVAL);
    Require(fclose_nid_postfix(stream) == 0);
    ExpectException([] { fputs_nid_postfix("invalid stream", nullptr); });
    ExpectException([] { fopen_nid_postfix(nullptr, "r"); });
    FileStream closed(std::tmpfile());
    closed.Close();
    ExpectException([&] { fflush_nid_postfix(&closed); });
    Require(std::remove(argv[1]) == 0);
    errno = 0;
    Require(fopen_nid_postfix(argv[1], "rb") == nullptr);
    Require(errno == ENOENT);
#ifdef _WIN32
    const std::string directoryMode = "rb";
    constexpr int directoryError = EACCES;
#else
    const std::string directoryMode = "wb";
    constexpr int directoryError = EISDIR;
#endif
    const std::string directoryName = std::string(argv[1]) + ".dir";
    Require(std::filesystem::create_directory(directoryName));
    errno = 0;
    Require(fopen_nid_postfix(directoryName.c_str(), directoryMode.c_str()) == nullptr);
    Require(errno == directoryError);
    Require(std::filesystem::remove(directoryName));
    const std::u8string unicodeName = u8"セーブé.tmp";
    const std::string guestName(unicodeName.begin(), unicodeName.end());
    const std::filesystem::path hostName(unicodeName);
    constexpr char unicodePayload[] = "unicode";
    stream = fopen_nid_postfix(guestName.c_str(), "wb");
    Require(stream != nullptr);
    Require(fwrite_nid_postfix(unicodePayload, 1, sizeof(unicodePayload), stream) == sizeof(unicodePayload));
    Require(fclose_nid_postfix(stream) == 0);
    Require(std::filesystem::exists(hostName));
    Require(std::filesystem::file_size(hostName) == sizeof(unicodePayload));
    stream = fopen_nid_postfix(guestName.c_str(), "rb");
    Require(stream != nullptr);
    std::array<char, sizeof(unicodePayload)> unicodeBuffer{};
    Require(fread_nid_postfix(unicodeBuffer.data(), 1, unicodeBuffer.size(), stream) == unicodeBuffer.size());
    Require(std::strcmp(unicodeBuffer.data(), unicodePayload) == 0);
    stream = freopen_nid_postfix(guestName.c_str(), "wb", stream);
    Require(stream != nullptr);
    Require(fclose_nid_postfix(stream) == 0);
    Require(std::filesystem::file_size(hostName) == 0);
    std::filesystem::remove(hostName);
    const std::string heldName = std::string(argv[1]) + ".held";
    const std::string movedName = std::string(argv[1]) + ".moved";
    stream = fopen_nid_postfix(heldName.c_str(), "w+b");
    Require(stream != nullptr && fwrite_nid_postfix(payload, 1, sizeof(payload), stream) == sizeof(payload));
    Require(fflush_nid_postfix(stream) == 0);
    Require(rename_nid_postfix(heldName.c_str(), movedName.c_str()) == 0 && !std::filesystem::exists(heldName));
    Require(remove_nid_postfix(movedName.c_str()) == 0 && !std::filesystem::exists(movedName));
    Require(fseek_nid_postfix(stream, 0, SEEK_SET) == 0);
    std::array<char, sizeof(payload)> heldBuffer{};
    Require(fread_nid_postfix(heldBuffer.data(), 1, heldBuffer.size(), stream) == heldBuffer.size());
    Require(std::strcmp(heldBuffer.data(), payload) == 0 && fclose_nid_postfix(stream) == 0);
    stream = fopen_nid_postfix(heldName.c_str(), "ab");
    Require(stream != nullptr && fputs_nid_postfix("ab", stream) >= 0 && fclose_nid_postfix(stream) == 0);
    stream = fopen_nid_postfix(heldName.c_str(), "ab");
    Require(stream != nullptr && fputs_nid_postfix("cd", stream) >= 0 && fclose_nid_postfix(stream) == 0);
    errno = 0;
    Require(fopen_nid_postfix(heldName.c_str(), "wbx") == nullptr && errno == EEXIST);
    stream = fopen_nid_postfix(heldName.c_str(), "rb");
    std::array<char, 5> appended{};
    Require(stream != nullptr && fread_nid_postfix(appended.data(), 1, 4, stream) == 4 && std::strcmp(appended.data(), "abcd") == 0);
    Require(fclose_nid_postfix(stream) == 0 && remove_nid_postfix(heldName.c_str()) == 0);
    constexpr char marker[] = "marker";
    stream = fopen_nid_postfix(argv[1], "wb");
    Require(stream != nullptr);
    std::array<char, sizeof(marker)> markerBuffer{};
    Require(fread_nid_postfix(markerBuffer.data(), 1, markerBuffer.size(), stream) == 0);
    Require(ferror_nid_postfix(stream) != 0);
    Require(fclose_nid_postfix(stream) == 0);
    stream = fopen_nid_postfix(argv[1], "rb");
    Require(stream != nullptr);
    Require(fwrite_nid_postfix(marker, 1, sizeof(marker), stream) == 0);
    Require(ferror_nid_postfix(stream) != 0);
    clearerr_nid_postfix(stream);
    Require(fputs_nid_postfix(marker, stream) == EOF);
    Require(ferror_nid_postfix(stream) != 0);
    Require(fclose_nid_postfix(stream) == 0);
    stream = fopen_nid_postfix(argv[1], "wb");
    Require(stream != nullptr && fputs_nid_postfix(marker, stream) >= 0);
    ReplaceWithReadOnlyDescriptor(stream, argv[1]);
    Require(fflush_nid_postfix(stream) == EOF);
    Require(ferror_nid_postfix(stream) != 0);
    static_cast<void>(fclose_nid_postfix(stream));
    Require(std::remove(argv[1]) == 0);
    std::cout << "PASS: stream objects, file operations, EOF and error handling\n";
}
