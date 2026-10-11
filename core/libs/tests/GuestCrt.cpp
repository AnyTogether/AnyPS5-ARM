#include "SceTypes.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include "prx/libc/include/SonyCrt.hpp"
#include <cfenv>
#include <climits>
#include <cerrno>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <exception>
#include <limits>

extern "C" {
SonyLconv* APS5_VABI sceAmprLocaleconv(void);
double APS5_VABI sceAmprSinh(double x, double y);
char* APS5_VABI sceAmprStrtokS(char* str, const char* delim, char** context);
int APS5_VABI sceAmprCtimeS(char* buffer, std::size_t size, const std::int64_t* time);
int APS5_VABI sceAmprWcscpyS(std::uint16_t* dest, std::size_t size, const std::uint16_t* src);
void* APS5_VABI sceAmprSetConstraintHandlerS(void* handler);
int APS5_VABI sceAmprFltrounds(void);
void APS5_VABI sceAmprIgnoreHandlerS(const char* message, void* pointer, int error);
std::size_t APS5_VABI sceAmprMbstowcs(std::uint16_t* dest, const char* src, std::size_t size);
int APS5_VABI sceAmprAsctimeS(char* buffer, std::size_t size, const GuestTm* time);
int APS5_VABI ctime_s_nid_postfix(char* buffer, std::size_t size, const std::int64_t* time);
int APS5_VABI asctime_s_nid_postfix(char* buffer, std::size_t size, const GuestTm* time);
std::size_t APS5_VABI mbstowcs_nid_postfix(std::uint16_t* dest, const char* src, std::size_t size);
char* APS5_VABI strtok_s_nid_postfix(char* str, const char* delim, char** context);
int APS5_VABI __fpclassifyd_nid_postfix(double value);
unsigned __int128 APS5_VABI __udivti3_nid_postfix(unsigned __int128 dividend, unsigned __int128 divisor);
SonyLconv* APS5_VABI localeconv_nid_postfix(void);
int APS5_VABI sceAmprFpclassifyd(double value);
}

#define Require(condition) do { if (!(condition)) { std::fprintf(stderr, "guest_crt: line %d: %s\n", __LINE__, #condition); std::abort(); } } while (0)

static int g_handlerCalls = 0;
static void CountingHandler(const char* message, void* pointer, int error) {
    (void)message;
    (void)pointer;
    (void)error;
    ++g_handlerCalls;
}

int main() {
    Require(sceAmprFpclassifyd(std::numeric_limits<double>::quiet_NaN()) == 2);
    Require(sceAmprFpclassifyd(std::numeric_limits<double>::infinity()) == 1);
    Require(sceAmprFpclassifyd(0.0) == 0);
    Require(sceAmprFpclassifyd(std::numeric_limits<double>::denorm_min()) == -2);
    Require(sceAmprFpclassifyd(1.5) == -1);
    Require(__fpclassifyd_nid_postfix(0.0) == 0);

    Require(sceAmprFltrounds() == 1);
    Require(std::fesetround(FE_DOWNWARD) == 0);
    Require(sceAmprFltrounds() == 3);
    Require(std::fesetround(FE_TONEAREST) == 0);
    Require(sceAmprFltrounds() == 1);

    Require(sceAmprSinh(1.0, 2.0) == 2.0 * std::sinh(1.0));
    Require(sceAmprSinh(0.0, 5.0) == 0.0);

    SonyLconv* locale = sceAmprLocaleconv();
    Require(reinterpret_cast<std::uintptr_t>(&locale->decimal_point) - reinterpret_cast<std::uintptr_t>(locale) == 0x48);
    Require(std::strcmp(locale->decimal_point, ".") == 0);
    Require(std::memcmp(localeconv_nid_postfix()->chars, locale->chars, sizeof(locale->chars)) == 0);
    Require(std::strcmp(localeconv_nid_postfix()->decimal_point, ".") == 0);
    for (const char* text : locale->monetary) Require(text != nullptr && text[0] == '\0');
    for (char value : locale->chars) Require(value == CHAR_MAX);
    Require(std::strcmp(locale->false_text, "false") == 0 && std::strcmp(locale->true_text, "true") == 0);
    Require(locale->grouping[0] == '\0' && locale->thousands_sep[0] == '\0');

    Require(__udivti3_nid_postfix(100, 3) == 33);
    Require(SonyUdivti3(100, 3) == 33);
    Require(SonyUdivti3(0, 5) == 0);
    Require(SonyUdivti3((unsigned __int128)1 << 100, 3) == (((unsigned __int128)1 << 100) / 3));
    bool trapped = false;
    try {
        SonyUdivti3(1, 0);
    } catch (const std::exception&) {
        trapped = true;
    }
    Require(trapped);

    void* previous = sceAmprSetConstraintHandlerS(reinterpret_cast<void*>(&CountingHandler));
    Require(previous != nullptr);
    Require(previous != reinterpret_cast<void*>(&CountingHandler));
    const std::uint16_t hello[] = {'h', 'i', 0};
    std::uint16_t buffer[8] = {};
    Require(sceAmprWcscpyS(buffer, 8, hello) == 0);
    Require(buffer[0] == 'h' && buffer[1] == 'i' && buffer[2] == 0);
    const std::uint16_t longText[] = {'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 0};
    g_handlerCalls = 0;
    Require(sceAmprWcscpyS(buffer, 4, longText) == ERANGE);
    Require(g_handlerCalls == 1);
    Require(sceAmprWcscpyS(nullptr, 4, longText) == EINVAL);
    previous = sceAmprSetConstraintHandlerS(nullptr);
    Require(previous == reinterpret_cast<void*>(&CountingHandler));
    previous = sceAmprSetConstraintHandlerS(reinterpret_cast<void*>(&CountingHandler));
    Require(previous != nullptr && previous != reinterpret_cast<void*>(&CountingHandler));
    sceAmprIgnoreHandlerS("msg", nullptr, 0);

    char text[64];
    GuestTm known{};
    known.tm_year = 70;
    known.tm_mon = 0;
    known.tm_mday = 1;
    known.tm_wday = 4;
    Require(sceAmprAsctimeS(text, sizeof(text), &known) == 0);
    Require(std::strcmp(text, "Thu Jan  1 00:00:00 1970\n") == 0);
    std::memset(text, 0, sizeof(text));
    Require(asctime_s_nid_postfix(text, sizeof(text), &known) == 0);
    Require(std::strcmp(text, "Thu Jan  1 00:00:00 1970\n") == 0);
    known.tm_wday = 7;
    Require(sceAmprAsctimeS(text, sizeof(text), &known) == EINVAL);
    known.tm_wday = 4;
    Require(sceAmprAsctimeS(nullptr, sizeof(text), &known) == EINVAL);
    Require(sceAmprAsctimeS(text, sizeof(text), nullptr) == EINVAL);
    Require(sceAmprAsctimeS(text, 25, &known) == EINVAL);
    const std::int64_t epoch = 0;
    Require(sceAmprCtimeS(text, sizeof(text), &epoch) == 0);
    Require(std::strlen(text) == 25 && text[24] == '\n');
    char libcText[64];
    Require(ctime_s_nid_postfix(libcText, sizeof(libcText), &epoch) == 0);
    Require(std::strcmp(libcText, text) == 0);
    Require(sceAmprCtimeS(text, 25, &epoch) == EINVAL);
    Require(sceAmprCtimeS(text, sizeof(text), nullptr) == EINVAL);

    char line[] = "a,b,,c";
    char* context = nullptr;
    Require(std::strcmp(sceAmprStrtokS(line, ",", &context), "a") == 0);
    Require(std::strcmp(sceAmprStrtokS(nullptr, ",", &context), "b") == 0);
    Require(std::strcmp(sceAmprStrtokS(nullptr, ",", &context), "c") == 0);
    Require(sceAmprStrtokS(nullptr, ",", &context) == nullptr);
    Require(sceAmprStrtokS(line, nullptr, &context) == nullptr);
    char again[] = "x y";
    char* again_context = nullptr;
    Require(std::strcmp(strtok_s_nid_postfix(again, " ", &again_context), "x") == 0);

    std::uint16_t wide[8] = {};
    Require(sceAmprMbstowcs(wide, "ABC", 8) == 3);
    Require(wide[0] == 65 && wide[1] == 66 && wide[2] == 67 && wide[3] == 0);
    Require(sceAmprMbstowcs(nullptr, "ABC", 8) == 3);
    Require(sceAmprMbstowcs(wide, "ABC", 2) == 2);
    Require(mbstowcs_nid_postfix(wide, "ABC", 8) == 3);
}
