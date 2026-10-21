#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdlib>
#include <cstring>

extern "C" {
void* APS5_VABI sceCesUcsProfileInitEucKr(void*);
void* APS5_VABI sceCesUcsProfileInitUhc(void*);
void* APS5_VABI sceCesUcsProfileInitBig5Cp950(void*);
void* APS5_VABI sceCesUcsProfileInitEucJpCp51932(void*);
int APS5_VABI sceCesEucKrToUtf8(const void*, const std::uint8_t*, std::uint32_t, std::uint32_t*, std::uint8_t*, std::uint32_t, std::uint32_t*);
int APS5_VABI sceCesUhcToUtf8(const void*, const std::uint8_t*, std::uint32_t, std::uint32_t*, std::uint8_t*, std::uint32_t, std::uint32_t*);
int APS5_VABI sceCesBig5ToUtf8(const void*, const std::uint8_t*, std::uint32_t, std::uint32_t*, std::uint8_t*, std::uint32_t, std::uint32_t*);
int APS5_VABI sceCesMbcsUcsContextInit(void*, const void*);
int APS5_VABI sceCesUtf8StrToMbcsStr(void*, const std::uint8_t*, std::uint32_t, std::uint32_t*, std::uint8_t*, std::uint32_t, std::uint32_t*);
int APS5_VABI sceCesMbcsStrToUtf8Str(void*, const std::uint8_t*, std::uint32_t, std::uint32_t*, std::uint8_t*, std::uint32_t, std::uint32_t*);
int APS5_VABI sceCesUcs2StrToMbcsStr(void*, const std::uint16_t*, std::uint32_t, std::uint32_t*, std::uint8_t*, std::uint32_t, std::uint32_t*);
int APS5_VABI sceCesMbcsStrToUcs2Str(void*, const std::uint8_t*, std::uint32_t, std::uint32_t*, std::uint16_t*, std::uint32_t, std::uint32_t*);
}

using ToUtf8 = int (APS5_VABI*)(const void*, const std::uint8_t*, std::uint32_t, std::uint32_t*, std::uint8_t*, std::uint32_t, std::uint32_t*);

constexpr int invalidParameter = static_cast<int>(0x805C0001);
constexpr int invalidSrcBuffer = static_cast<int>(0x805C0010);
constexpr int srcBufferEnd = static_cast<int>(0x805C0011);
constexpr int invalidEncode = static_cast<int>(0x805C0014);
constexpr int unassignedCode = static_cast<int>(0x805C0020);
constexpr int invalidDstBuffer = static_cast<int>(0x805C0030);
constexpr int dstBufferEnd = static_cast<int>(0x805C0031);

static void Require(bool value) { if (!value) std::abort(); }

static const std::uint8_t* Bytes(const char* text) { return reinterpret_cast<const std::uint8_t*>(text); }

static std::uint32_t Size(const char* text) { return static_cast<std::uint32_t>(std::strlen(text)); }

static std::uint64_t Fnv(std::uint64_t hash, std::uint8_t byte) { return (hash ^ byte) * 0x100000001B3ull; }

static void RequireTable(ToUtf8 convert, const void* profile, std::uint64_t expectedHash, std::uint32_t expectedCells) {
    std::uint64_t hash = 0xCBF29CE484222325ull;
    std::uint32_t cells = 0;
    for (std::uint32_t lead = 0; lead < 256; ++lead) {
        for (std::uint32_t trail = 0; trail < 256; ++trail) {
            const std::uint8_t source[2] = {static_cast<std::uint8_t>(lead), static_cast<std::uint8_t>(trail)};
            std::uint8_t utf8[4] = {};
            std::uint32_t consumed = 0;
            std::uint32_t produced = 0;
            const int result = convert(profile, source, sizeof(source), &consumed, utf8, sizeof(utf8), &produced);
            hash = Fnv(hash, static_cast<std::uint8_t>(result & 0xFF));
            if (result != 0) continue;
            hash = Fnv(hash, static_cast<std::uint8_t>(consumed));
            for (std::uint32_t i = 0; i < produced; ++i) hash = Fnv(hash, utf8[i]);
            if (consumed == 2) ++cells;
        }
    }
    Require(hash == expectedHash && cells == expectedCells);
}

static void RequireScalar(ToUtf8 convert, const void* profile, const char* source, const char* expected) {
    std::uint8_t utf8[4] = {};
    std::uint32_t consumed = 0;
    std::uint32_t produced = 0;
    Require(convert(profile, Bytes(source), Size(source), &consumed, utf8, sizeof(utf8), &produced) == 0);
    Require(consumed == Size(source) && produced == Size(expected) && std::memcmp(utf8, expected, produced) == 0);
}

static int Scalar(ToUtf8 convert, const void* profile, const char* source, std::uint32_t sourceMax, std::uint32_t utf8Max) {
    std::uint8_t utf8[4] = {0x55, 0x55, 0x55, 0x55};
    std::uint32_t consumed = 77;
    std::uint32_t produced = 77;
    const int result = convert(profile, Bytes(source), sourceMax, &consumed, utf8, utf8Max, &produced);
    if (result != 0) Require(consumed == 77 && produced == 77 && std::memcmp(utf8, "\x55\x55\x55\x55", 4) == 0);
    return result;
}

static void RequireString(void* context, const char* mbcs, const char* utf8) {
    std::uint8_t converted[32] = {};
    std::uint32_t read = 0;
    std::uint32_t written = 0;
    Require(sceCesMbcsStrToUtf8Str(context, Bytes(mbcs), Size(mbcs), &read, converted, sizeof(converted), &written) == 0);
    Require(read == Size(mbcs) && written == Size(utf8) && std::memcmp(converted, utf8, written) == 0);
    std::uint8_t back[32] = {};
    Require(sceCesUtf8StrToMbcsStr(context, Bytes(utf8), Size(utf8), &read, back, sizeof(back), &written) == 0);
    Require(read == Size(utf8) && written == Size(mbcs) && std::memcmp(back, mbcs, written) == 0);
}

static int Utf8ToMbcs(void* context, const char* utf8) {
    std::uint8_t mbcs[8] = {};
    std::uint32_t read = 0;
    std::uint32_t written = 0;
    return sceCesUtf8StrToMbcsStr(context, Bytes(utf8), Size(utf8), &read, mbcs, sizeof(mbcs), &written);
}

static std::uint32_t RoundTripMismatches(void* context) {
    std::uint32_t mismatches = 0;
    for (std::uint32_t lead = 0x81; lead < 0xFF; ++lead) {
        for (std::uint32_t trail = 0x40; trail < 0xFF; ++trail) {
            const std::uint8_t source[2] = {static_cast<std::uint8_t>(lead), static_cast<std::uint8_t>(trail)};
            std::uint16_t ucs2 = 0;
            std::uint32_t read = 0;
            std::uint32_t written = 0;
            if (sceCesMbcsStrToUcs2Str(context, source, sizeof(source), &read, &ucs2, 1, &written) != 0) continue;
            Require(read == 2 && written == 1);
            std::uint8_t back[2] = {};
            Require(sceCesUcs2StrToMbcsStr(context, &ucs2, 1, &read, back, sizeof(back), &written) == 0);
            Require(read == 1 && written == 2);
            if (std::memcmp(source, back, sizeof(back)) != 0) ++mismatches;
        }
    }
    return mismatches;
}

int main() {
    alignas(8) std::uint8_t eucKrSheet[64] = {};
    alignas(8) std::uint8_t uhcSheet[64] = {};
    alignas(8) std::uint8_t big5Sheet[64] = {};
    alignas(8) std::uint8_t eucJpSheet[64] = {};
    Require(sceCesUcsProfileInitEucKr(nullptr) == nullptr);
    Require(sceCesUcsProfileInitUhc(nullptr) == nullptr);
    Require(sceCesUcsProfileInitBig5Cp950(nullptr) == nullptr);
    void* eucKr = sceCesUcsProfileInitEucKr(eucKrSheet);
    void* uhc = sceCesUcsProfileInitUhc(uhcSheet);
    void* big5 = sceCesUcsProfileInitBig5Cp950(big5Sheet);
    void* eucJp = sceCesUcsProfileInitEucJpCp51932(eucJpSheet);
    Require(eucKr == eucKrSheet && uhc == uhcSheet && big5 == big5Sheet && eucJp == eucJpSheet);

    RequireTable(sceCesEucKrToUtf8, eucKr, 0x01FF720E36F4AD67ull, 8226);
    RequireTable(sceCesUhcToUtf8, uhc, 0x3B861A7E911985ABull, 17048);
    RequireTable(sceCesBig5ToUtf8, big5, 0xE4D0D6A8019F35D9ull, 13503);

    RequireScalar(sceCesEucKrToUtf8, eucKr, "\xB0\xA1", "\xEA\xB0\x80");
    RequireScalar(sceCesEucKrToUtf8, eucKr, "\xA2\xE6", "\xE2\x82\xAC");
    RequireScalar(sceCesUhcToUtf8, uhc, "\xB0\xA1", "\xEA\xB0\x80");
    RequireScalar(sceCesUhcToUtf8, uhc, "\x8C\x63", "\xEB\x98\xA0");
    RequireScalar(sceCesBig5ToUtf8, big5, "\xA4\xA4", "\xE4\xB8\xAD");
    RequireScalar(sceCesBig5ToUtf8, big5, "A", "A");
    std::uint8_t zero[4] = {0x55, 0x55, 0x55, 0x55};
    Require(sceCesUhcToUtf8(uhc, Bytes("\0"), 1, nullptr, zero, sizeof(zero), nullptr) == 0 && zero[0] == 0 && zero[1] == 0x55);

    Require(Scalar(sceCesEucKrToUtf8, nullptr, "\xB0\xA1", 2, 4) == invalidParameter);
    Require(Scalar(sceCesEucKrToUtf8, uhc, "\xB0\xA1", 2, 4) == invalidParameter);
    Require(Scalar(sceCesUhcToUtf8, eucKr, "\xB0\xA1", 2, 4) == invalidParameter);
    Require(Scalar(sceCesBig5ToUtf8, eucJp, "\xA4\xA4", 2, 4) == invalidParameter);
    Require(Scalar(sceCesEucKrToUtf8, eucKr, nullptr, 2, 4) == invalidSrcBuffer);
    Require(Scalar(sceCesEucKrToUtf8, eucKr, "\xB0\xA1", 0, 4) == srcBufferEnd);
    Require(Scalar(sceCesUhcToUtf8, uhc, "\x8C\x63", 1, 4) == srcBufferEnd);
    Require(Scalar(sceCesBig5ToUtf8, big5, "\xA4\xA4", 1, 4) == srcBufferEnd);
    Require(Scalar(sceCesEucKrToUtf8, eucKr, "\xB0\xA1", 2, 2) == dstBufferEnd);
    Require(Scalar(sceCesEucKrToUtf8, eucKr, "\x8C\x63", 2, 4) == invalidEncode);
    Require(Scalar(sceCesUhcToUtf8, uhc, "\x80\xA1", 2, 4) == invalidEncode);
    Require(Scalar(sceCesUhcToUtf8, uhc, "\xB0\x5B", 2, 4) == invalidEncode);
    Require(Scalar(sceCesUhcToUtf8, uhc, "\xC9\xA1", 2, 4) == unassignedCode);
    Require(Scalar(sceCesUhcToUtf8, uhc, "\xC7\x41", 2, 4) == unassignedCode);
    Require(Scalar(sceCesBig5ToUtf8, big5, "\xA4\x80", 2, 4) == invalidEncode);
    Require(Scalar(sceCesBig5ToUtf8, big5, "\xFF\xA1", 2, 4) == invalidEncode);
    Require(Scalar(sceCesBig5ToUtf8, big5, "\x81\x40", 2, 4) == unassignedCode);
    Require(Scalar(sceCesBig5ToUtf8, big5, "\xFA\x40", 2, 4) == unassignedCode);
    Require(sceCesEucKrToUtf8(eucKr, Bytes("\xB0\xA1"), 2, nullptr, nullptr, 4, nullptr) == invalidDstBuffer);

    alignas(8) std::uint8_t context[64] = {};
    Require(sceCesMbcsUcsContextInit(context, eucKr) == 0);
    RequireString(context, "\xC7\xD1\xB1\xB9\xBE\xEE A", "\xED\x95\x9C\xEA\xB5\xAD\xEC\x96\xB4 A");
    Require(Utf8ToMbcs(context, "\xEB\x98\xA0") == unassignedCode);
    Require(RoundTripMismatches(context) == 0);

    Require(sceCesMbcsUcsContextInit(context, uhc) == 0);
    RequireString(context, "\x8C\x63\xC7\xD1", "\xEB\x98\xA0\xED\x95\x9C");
    Require(Utf8ToMbcs(context, "\xE4\xB8\xAD") == 0);
    Require(Utf8ToMbcs(context, "\xE2\x82\xAC\xEF\xBF\xBF") == unassignedCode);
    Require(RoundTripMismatches(context) == 0);

    Require(sceCesMbcsUcsContextInit(context, big5) == 0);
    RequireString(context, "\xA4\xA4\xA4\xE5", "\xE4\xB8\xAD\xE6\x96\x87");
    RequireString(context, "\xF9\xF9\xA2\x7E\xA4\x51\xA4\xCA", "\xE2\x95\x90\xE2\x95\xAD\xE5\x8D\x81\xE5\x8D\x85");
    RequireString(context, "\xF9\xE9\xF9\xEB\xF9\xEA\xA2\xA1\xA2\xA3\xA2\xA2", "\xE2\x95\x9E\xE2\x95\xA1\xE2\x95\xAA\xE2\x95\xAE\xE2\x95\xAF\xE2\x95\xB0");
    Require(Utf8ToMbcs(context, "\xEA\xB0\x80") == unassignedCode);
    Require(RoundTripMismatches(context) == 10);
    return 0;
}
