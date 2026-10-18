#include "prx/libc/include/General.hpp"

#include <array>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <optional>
#include <stdexcept>
#include <string>
#include <system_error>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include "prx/libkernel/File/include/TrustedRoots.hpp"
#else
#include <unistd.h>
#endif

extern "C" const char* APS5_VABI sceKernelGetFsSandboxRandomWord();

namespace {
constexpr char CertificateBegin[] = "-----BEGIN CERTIFICATE-----";

std::optional<std::string> ReadFile(const std::filesystem::path& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) return std::nullopt;
    std::string text((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    if (file.bad()) throw std::runtime_error("Reading " + path.string() + " failed");
    return text;
}

#ifdef _WIN32
std::string HostCertificates() {
    return HostTrustedTlsRoots_nid_no_patch();
}

unsigned long ProcessId() { return GetCurrentProcessId(); }
#else
std::string HostCertificates() {
    std::array<const char*, 5> candidates{std::getenv("SSL_CERT_FILE"), "/etc/ssl/certs/ca-certificates.crt", "/etc/pki/tls/certs/ca-bundle.crt",
        "/etc/ssl/ca-bundle.pem", "/etc/ssl/cert.pem"};
    for (const char* candidate : candidates) {
        std::error_code error;
        if (candidate == nullptr || *candidate == '\0' || !std::filesystem::is_regular_file(candidate, error)) continue;
        if (auto text = ReadFile(candidate)) return *text;
    }
    return {};
}

unsigned long ProcessId() { return static_cast<unsigned long>(getpid()); }
#endif

std::filesystem::path WriteCertificateList(const std::filesystem::path& root) {
    const auto bundle = HostCertificates();
    if (bundle.find(CertificateBegin) == std::string::npos) return {};
    const auto directory = root / "cert_cache";
    std::filesystem::create_directories(directory);
    const auto target = directory / "CA_LIST.cer";
    if (ReadFile(target) == bundle) return target;
    auto temporary = target;
    temporary += "." + std::to_string(ProcessId()) + ".tmp";
    {
        std::ofstream file(temporary, std::ios::binary | std::ios::trunc);
        file.write(bundle.data(), static_cast<std::streamsize>(bundle.size()));
        if (!file.flush()) throw std::runtime_error("Writing " + temporary.string() + " failed");
    }
    using std::filesystem::perms;
    std::filesystem::permissions(temporary, perms::owner_read | perms::group_read | perms::others_read);
    std::error_code error;
    if (std::filesystem::exists(target, error)) std::filesystem::permissions(target, perms::owner_write, std::filesystem::perm_options::add);
    std::filesystem::rename(temporary, target);
    return target;
}

std::filesystem::path CertificateList(const std::filesystem::path& root) {
    static const std::filesystem::path list = WriteCertificateList(root);
    return list;
}

const bool g_certificateListProvided = [] {
    AddPathProvider_nid_no_patch((std::string("/") + sceKernelGetFsSandboxRandomWord() + "/common/cert/CA_LIST.cer").c_str(), &CertificateList);
    return true;
}();
}
