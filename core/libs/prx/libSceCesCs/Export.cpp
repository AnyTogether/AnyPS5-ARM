#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

namespace {

constexpr int CES_ERROR_INVALID_PARAMETER = static_cast<int>(0x805C0001);
constexpr int CES_ERROR_INVALID_SRC_BUFFER = static_cast<int>(0x805C0010);
constexpr int CES_ERROR_SRC_BUFFER_END = static_cast<int>(0x805C0011);
constexpr int CES_ERROR_INVALID_ENCODE = static_cast<int>(0x805C0014);
constexpr int CES_ERROR_UNASSIGNED_CODE = static_cast<int>(0x805C0020);
constexpr int CES_ERROR_INVALID_DST_BUFFER = static_cast<int>(0x805C0030);
constexpr int CES_ERROR_DST_BUFFER_END = static_cast<int>(0x805C0031);

constexpr uint8_t PROFILES[2] = {0, 1};
constexpr const uint8_t* CP1252_PROFILE = &PROFILES[0];
constexpr const uint8_t* CP1251_PROFILE = &PROFILES[1];

constexpr uint16_t CP1252_HIGH[32] = {
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
};

constexpr uint16_t CP1251_HIGH[128] = {
    0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021, 0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
    0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x0098, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
    0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7, 0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
    0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7, 0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
    0x0410, 0x0411, 0x0412, 0x0413, 0x0414, 0x0415, 0x0416, 0x0417, 0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E, 0x041F,
    0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427, 0x0428, 0x0429, 0x042A, 0x042B, 0x042C, 0x042D, 0x042E, 0x042F,
    0x0430, 0x0431, 0x0432, 0x0433, 0x0434, 0x0435, 0x0436, 0x0437, 0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E, 0x043F,
    0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447, 0x0448, 0x0449, 0x044A, 0x044B, 0x044C, 0x044D, 0x044E, 0x044F,
};

uint32_t sbcToUnicode(const uint8_t* profile, uint8_t sbc) {
    if (profile == CP1251_PROFILE) return sbc >= 0x80 ? CP1251_HIGH[sbc - 0x80] : sbc;
    return sbc >= 0x80 && sbc < 0xA0 ? CP1252_HIGH[sbc - 0x80] : sbc;
}

bool unicodeToSbc(const uint8_t* profile, uint32_t code, uint8_t& sbc) {
    if (profile == CP1251_PROFILE) {
        if (code < 0x80) {
            sbc = static_cast<uint8_t>(code);
            return true;
        }
        for (uint32_t i = 0; i < 128; ++i) {
            if (CP1251_HIGH[i] == code) {
                sbc = static_cast<uint8_t>(0x80 + i);
                return true;
            }
        }
        return false;
    }
    if (code < 0x80 || (code >= 0xA0 && code <= 0xFF)) {
        sbc = static_cast<uint8_t>(code);
        return true;
    }
    for (uint8_t i = 0; i < 32; ++i) {
        if (CP1252_HIGH[i] == code) {
            sbc = static_cast<uint8_t>(0x80 + i);
            return true;
        }
    }
    return false;
}

int decodeUtf8(const uint8_t* utf8, uint32_t utf8max, uint32_t& length, uint32_t& code) {
    const uint8_t lead = utf8[0];
    uint32_t minimum = 0;
    if (lead < 0x80) {
        length = 1;
        code = lead;
        return 0;
    }
    if ((lead & 0xE0) == 0xC0) { length = 2; code = lead & 0x1F; minimum = 0x80; }
    else if ((lead & 0xF0) == 0xE0) { length = 3; code = lead & 0x0F; minimum = 0x800; }
    else if ((lead & 0xF8) == 0xF0) { length = 4; code = lead & 0x07; minimum = 0x10000; }
    else return CES_ERROR_INVALID_ENCODE;

    for (uint32_t i = 1; i < length; ++i) {
        if (i >= utf8max) return CES_ERROR_SRC_BUFFER_END;
        if ((utf8[i] & 0xC0) != 0x80) return CES_ERROR_INVALID_ENCODE;
        code = code << 6 | (utf8[i] & 0x3F);
    }
    if (code < minimum || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) return CES_ERROR_INVALID_ENCODE;
    return 0;
}

uint32_t encodeUtf8(uint32_t code, uint8_t* utf8) {
    if (code < 0x80) {
        utf8[0] = static_cast<uint8_t>(code);
        return 1;
    }
    if (code < 0x800) {
        utf8[0] = static_cast<uint8_t>(0xC0 | code >> 6);
        utf8[1] = static_cast<uint8_t>(0x80 | (code & 0x3F));
        return 2;
    }
    utf8[0] = static_cast<uint8_t>(0xE0 | code >> 12);
    utf8[1] = static_cast<uint8_t>(0x80 | (code >> 6 & 0x3F));
    utf8[2] = static_cast<uint8_t>(0x80 | (code & 0x3F));
    return 3;
}

}

extern "C" {

const uint8_t* APS5_VABI sceCesRefersUcsProfileCp1252(void) {
    return CP1252_PROFILE;
}

const uint8_t* APS5_VABI sceCesRefersUcsProfileCp1251(void) {
    return CP1251_PROFILE;
}

int APS5_VABI sceCesMbcsUcsContextInit(void* context, const void* profile) {
    (void)profile;
    if (!context) return CES_ERROR_INVALID_PARAMETER;
    return 0;
}

int APS5_VABI sceCesSbcToUtf8(const uint8_t* profile, uint8_t sbc, uint8_t* utf8, uint32_t utf8max, uint32_t* utf8_len) {
    if (profile != CP1252_PROFILE && profile != CP1251_PROFILE) return CES_ERROR_INVALID_PARAMETER;
    if (!utf8) return CES_ERROR_INVALID_DST_BUFFER;

    uint8_t encoded[3];
    const uint32_t length = encodeUtf8(sbcToUnicode(profile, sbc), encoded);
    if (utf8max < length) return CES_ERROR_DST_BUFFER_END;
    for (uint32_t i = 0; i < length; ++i) utf8[i] = encoded[i];
    if (utf8_len) *utf8_len = length;
    return 0;
}

int APS5_VABI sceCesUtf8ToSbc(const uint8_t* utf8, uint32_t utf8max, uint32_t* utf8_len, const uint8_t* profile, uint8_t* sbc) {
    if (profile != CP1252_PROFILE && profile != CP1251_PROFILE) return CES_ERROR_INVALID_PARAMETER;
    if (!utf8) return CES_ERROR_INVALID_SRC_BUFFER;
    if (utf8max == 0) return CES_ERROR_SRC_BUFFER_END;
    if (!sbc) return CES_ERROR_INVALID_DST_BUFFER;

    uint32_t length = 0;
    uint32_t code = 0;
    if (const int result = decodeUtf8(utf8, utf8max, length, code); result != 0) return result;
    if (!unicodeToSbc(profile, code, *sbc)) return CES_ERROR_UNASSIGNED_CODE;
    if (utf8_len) *utf8_len = length;
    return 0;
}

}
