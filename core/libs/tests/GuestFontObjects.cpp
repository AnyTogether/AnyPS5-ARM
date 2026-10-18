#include "prx/libSceFont/include/FontTypes.hpp"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <initializer_list>
#include <utility>
#include <vector>

extern "C" {
int APS5_VABI sceFontMemoryInit(FontMemory*, void*, std::uint32_t, const FontMemoryInterface*, void*, FontMemoryDestroyFunction, void*);
int APS5_VABI sceFontMemoryTerm(FontMemory*);
int APS5_VABI sceFontCreateLibrary(const FontMemory*, const void*, FontLibrary*);
int APS5_VABI sceFontDestroyLibrary(FontLibrary*);
int APS5_VABI sceFontCreateRenderer(const FontMemory*, const void*, FontRenderer*);
int APS5_VABI sceFontDestroyRenderer(FontRenderer*);
int APS5_VABI sceFontSupportExternalFonts(FontLibrary, std::uint32_t, std::uint32_t);
int APS5_VABI sceFontOpenFontMemory(FontLibrary, const void*, std::uint32_t, const FontOpenDetail*, FontHandle*);
int APS5_VABI sceFontOpenFontInstance(FontHandle, FontHandle, FontHandle*);
int APS5_VABI sceFontCloseFont(FontHandle);
int APS5_VABI sceFontSetScalePixel(FontHandle, float, float);
int APS5_VABI sceFontDefineAttribute(FontHandle, int, int*);
int APS5_VABI sceFontGetAttribute(FontHandle, int, int*);
int APS5_VABI sceFontGenerateCharGlyph(FontHandle, std::uint32_t, const FontGenerateGlyphDetail*, FontGlyph*);
int APS5_VABI sceFontDeleteGlyph(const FontMemory*, FontGlyph*);
int APS5_VABI sceFontGlyphDefineAttribute(FontGlyph, int, int*);
int APS5_VABI sceFontGlyphGetAttribute(FontGlyph, int, int*);
int APS5_VABI sceFontGlyphRenderImage(FontGlyph, FontStyleFrame*, FontRenderer, FontRenderSurface*, float, float, FontGlyphMetrics*, FontRenderOutput*);
int APS5_VABI sceFontGlyphRenderImageHorizontal(FontGlyph, FontStyleFrame*, FontRenderer, FontRenderSurface*, float, float, FontGlyphMetrics*, FontRenderOutput*);
int APS5_VABI sceFontGlyphRenderImageVertical(FontGlyph, FontStyleFrame*, FontRenderer, FontRenderSurface*, float, float, FontGlyphMetrics*, FontRenderOutput*);
int APS5_VABI sceFontBindRenderer(FontHandle, FontRenderer);
int APS5_VABI sceFontUnbindRenderer(FontHandle);
int APS5_VABI sceFontSetupRenderScalePixel(FontHandle, float, float);
int APS5_VABI sceFontRenderCharGlyphImage(FontHandle, std::uint32_t, FontRenderSurface*, float, float, FontGlyphMetrics*, FontRenderOutput*);
int APS5_VABI sceFontStyleFrameInit(FontStyleFrame*);
int APS5_VABI sceFontStyleFrameSetScalePixel(FontStyleFrame*, float, float);
void APS5_VABI sceFontRenderSurfaceInit(FontRenderSurface*, void*, int, int, int, int);
int APS5_VABI sceFontTextSourceInit(FontTextSource*, const void*, std::uint32_t, FontTextParseFunction, void*);
int APS5_VABI sceFontCreateString(const FontMemory*, FontTextSource*, const FontCreateStringDetail*, FontString*);
int APS5_VABI sceFontDestroyString(FontString*);
FontTextCharacter* APS5_VABI sceFontStringRefersTextCharacters(FontString, std::uint32_t*);
int APS5_VABI sceFontCharacterGetSyllableStringState(const FontTextCharacter*, int*);
int APS5_VABI sceFontCreateWords(const FontMemory*, FontTextSource*, const void*, void**);
int APS5_VABI sceFontDestroyWords(void**);
int APS5_VABI sceFontWordsFindWordCharacters(void*, FontTextCharacter*, FontTextCharacter*, FontTextCharacter**, FontTextCharacter**);
const void* APS5_VABI sceFontSelectLibraryFt(int);
const void* APS5_VABI sceFontSelectRendererFt(int);
int APS5_VABI sceFontFtSupportTrueType(FontLibrary);
int APS5_VABI sceFontFtSupportTrueTypeGx(FontLibrary);
int APS5_VABI sceFontFtSupportOpenType(FontLibrary);
int APS5_VABI sceFontFtSupportOpenTypeOtf(FontLibrary);
int APS5_VABI sceFontFtSupportOpenTypeTtf(FontLibrary);
int APS5_VABI sceFontFtSupportType1(FontLibrary);
int APS5_VABI sceFontFtSupportType42(FontLibrary);
int APS5_VABI sceFontFtSupportCid(FontLibrary);
int APS5_VABI sceFontFtSupportPfr(FontLibrary);
int APS5_VABI sceFontFtSupportWinFonts(FontLibrary);
int APS5_VABI sceFontFtSupportPcf(FontLibrary);
int APS5_VABI sceFontFtSupportBdf(FontLibrary);
int APS5_VABI sceFontFtSupportSystemFonts(FontLibrary);
int APS5_VABI sceFontFtSupportFontFormats(FontLibrary);
}

static void Check(bool value, int line) {
    if (!value) {
        std::fprintf(stderr, "Font object check failed at line %d\n", line);
        std::abort();
    }
}
#define Require(value) Check((value), __LINE__)

static int allocations = 0;
static void* APS5_VABI Allocate(void*, std::uint32_t size) {
    ++allocations;
    return std::malloc(size);
}
static void APS5_VABI Release(void*, void* pointer) {
    if (pointer) --allocations;
    std::free(pointer);
}

static void Put16(std::vector<unsigned char>& out, std::uint32_t value) {
    out.push_back(static_cast<unsigned char>(value >> 8));
    out.push_back(static_cast<unsigned char>(value));
}

static void Put32(std::vector<unsigned char>& out, std::uint32_t value) {
    Put16(out, value >> 16);
    Put16(out, value & 0xFFFFu);
}

static void PutAll16(std::vector<unsigned char>& out, std::initializer_list<int> values) {
    for (const int value : values) Put16(out, static_cast<std::uint32_t>(static_cast<std::uint16_t>(value)));
}

// One glyph for 'A': a box from x 100 to 500 and y 0 to 700 in a 1000-unit em, advance 600.
static std::vector<unsigned char> SquareGlyphFont() {
    constexpr int width = 600;
    std::vector<unsigned char> head;
    Put32(head, 0x00010000u);
    Put32(head, 0x00010000u);
    Put32(head, 0);
    Put32(head, 0x5F0F3CF5u);
    PutAll16(head, {0x000B, 1000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, width, 800, 0, 8, 2, 0, 0});
    std::vector<unsigned char> hhea;
    Put32(hhea, 0x00010000u);
    PutAll16(hhea, {800, -200, 0, width, 0, 0, width, 1, 0, 0, 0, 0, 0, 0, 0, 2});
    std::vector<unsigned char> maxp;
    Put32(maxp, 0x00010000u);
    PutAll16(maxp, {2, 4, 1, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0});
    std::vector<unsigned char> hmtx;
    PutAll16(hmtx, {width, 0, width, 100});
    std::vector<unsigned char> glyf;
    PutAll16(glyf, {1, 100, 0, width - 100, 700, 3, 0});
    glyf.insert(glyf.end(), {1, 1, 1, 1});
    PutAll16(glyf, {100, 0, width - 200, 0, 0, 700, 0, -700});
    std::vector<unsigned char> loca;
    PutAll16(loca, {0, 0, static_cast<int>(glyf.size() / 2)});
    std::vector<unsigned char> cmap;
    PutAll16(cmap, {0, 1, 3, 1});
    Put32(cmap, 12);
    PutAll16(cmap, {4, 32, 0, 4, 4, 1, 0, 'A', 0xFFFF, 0, 'A', 0xFFFF, 1 - 'A', 1, 0, 0});
    const std::vector<std::pair<const char*, const std::vector<unsigned char>*>> tables = {
        {"cmap", &cmap}, {"glyf", &glyf}, {"head", &head}, {"hhea", &hhea}, {"hmtx", &hmtx}, {"loca", &loca}, {"maxp", &maxp}};
    std::vector<unsigned char> font;
    Put32(font, 0x00010000u);
    PutAll16(font, {static_cast<int>(tables.size()), 64, 2, static_cast<int>(tables.size()) * 16 - 64});
    std::uint32_t offset = 12 + static_cast<std::uint32_t>(tables.size()) * 16;
    for (const auto& [tag, data] : tables) {
        font.insert(font.end(), tag, tag + 4);
        Put32(font, 0);
        Put32(font, offset);
        Put32(font, static_cast<std::uint32_t>(data->size()));
        offset += (static_cast<std::uint32_t>(data->size()) + 3u) & ~3u;
    }
    for (const auto& [tag, data] : tables) {
        font.insert(font.end(), data->begin(), data->end());
        font.resize((font.size() + 3u) & ~std::size_t{3});
    }
    return font;
}

struct Text {
    const char32_t* codes;
    FontHandle font;
};

static std::int32_t APS5_VABI ParseText(FontTextSource* source, void** order, FontTextParseResult* result) {
    auto* text = static_cast<Text*>(source->textObject);
    const auto* current = static_cast<const char32_t*>(source->current);
    *order = const_cast<char32_t*>(current);
    if (*current == 0) {
        result->Terminate.terminateCode = 0;
        return 0;
    }
    result->FontCode.font = text->font;
    result->FontCode.code = *current;
    source->current = current + 1;
    return 1;
}

static void TestFtSupport(FontLibrary library) {
    for (auto support : {sceFontFtSupportTrueType, sceFontFtSupportTrueTypeGx, sceFontFtSupportOpenType, sceFontFtSupportOpenTypeOtf,
                         sceFontFtSupportOpenTypeTtf, sceFontFtSupportType1, sceFontFtSupportType42, sceFontFtSupportCid, sceFontFtSupportPfr,
                         sceFontFtSupportWinFonts, sceFontFtSupportPcf, sceFontFtSupportBdf, sceFontFtSupportSystemFonts, sceFontFtSupportFontFormats}) {
        Require(support(library) == SCE_FONT_OK);
        Require(support(nullptr) == SCE_FONT_ERROR_INVALID_LIBRARY);
        FontHandleOpaque notALibrary{};
        Require(support(&notALibrary) == SCE_FONT_ERROR_INVALID_LIBRARY);
    }
}

static void TestFontAttributes(FontHandle font) {
    int value = -1;
    Require(sceFontGetAttribute(font, 0x40, &value) == SCE_FONT_OK && value == 0x40);
    Require(sceFontGetAttribute(font, 0x11, &value) == SCE_FONT_OK && value == 0x10);
    Require(sceFontDefineAttribute(font, 0x41, &value) == SCE_FONT_OK && value == 0x40);
    Require(sceFontGetAttribute(font, 0x40, &value) == SCE_FONT_OK && value == 0x41);
    FontHandle instance = nullptr;
    Require(sceFontOpenFontInstance(font, nullptr, &instance) == SCE_FONT_OK);
    Require(sceFontGetAttribute(instance, 0x41, &value) == SCE_FONT_OK && value == 0x41);
    Require(sceFontCloseFont(instance) == SCE_FONT_OK);
    Require(sceFontDefineAttribute(font, 0x40, nullptr) == SCE_FONT_OK);
    Require(sceFontGetAttribute(font, 0x41, &value) == SCE_FONT_OK && value == 0x40);
    Require(sceFontDefineAttribute(font, 0x11, &value) == SCE_FONT_OK && value == 0x10);
    Require(sceFontGetAttribute(font, 0x10, &value) == SCE_FONT_OK && value == 0x11);
    for (const int invalid : {0, 0x01, 0x12, 0x50, 0x0F, -1}) {
        value = -1;
        Require(sceFontDefineAttribute(font, invalid, &value) == SCE_FONT_ERROR_INVALID_PARAMETER && value == 0);
        value = -1;
        Require(sceFontGetAttribute(font, invalid, &value) == SCE_FONT_ERROR_INVALID_PARAMETER && value == 0);
    }
    Require(sceFontGetAttribute(font, 0x40, nullptr) == SCE_FONT_ERROR_INVALID_PARAMETER);
    value = -1;
    Require(sceFontDefineAttribute(nullptr, 0x41, &value) == SCE_FONT_ERROR_INVALID_FONT_HANDLE && value == 0);
    FontHandleOpaque unopened{};
    Require(sceFontGetAttribute(&unopened, 0x40, &value) == SCE_FONT_ERROR_INVALID_FONT_HANDLE && value == 0);
}

static int Coverage(const std::vector<std::uint8_t>& pixels, int x, int y) {
    return pixels[static_cast<std::size_t>(y) * 128 + static_cast<std::size_t>(x)];
}

static void TestGlyphObjects(const FontMemory& memory, FontHandle font, FontRenderer renderer) {
    Require(sceFontSetScalePixel(font, 100.0f, 100.0f) == SCE_FONT_OK);
    FontGlyph glyph = nullptr;
    Require(sceFontGenerateCharGlyph(font, 'A', nullptr, &glyph) == SCE_FONT_OK && glyph != nullptr);

    int value = -1;
    Require(sceFontGlyphGetAttribute(glyph, 0x10, &value) == SCE_FONT_OK && value == 0x10);
    Require(sceFontGlyphDefineAttribute(glyph, 0x11, &value) == SCE_FONT_OK && value == 0x10);
    Require(sceFontGlyphGetAttribute(glyph, 0x10, &value) == SCE_FONT_OK && value == 0x11);
    Require(sceFontGlyphDefineAttribute(glyph, 0x11, nullptr) == SCE_FONT_OK);
    Require(sceFontGlyphDefineAttribute(glyph, 0x22, &value) == SCE_FONT_ERROR_INVALID_PARAMETER && value == 0);
    Require(sceFontGlyphGetAttribute(glyph, 0x60, &value) == SCE_FONT_ERROR_INVALID_PARAMETER && value == 0);
    Require(sceFontGlyphGetAttribute(glyph, 0x10, nullptr) == SCE_FONT_ERROR_INVALID_PARAMETER);
    FontGlyphOpaque notAGlyph{};
    Require(sceFontGlyphGetAttribute(&notAGlyph, 0x10, &value) == SCE_FONT_ERROR_INVALID_GLYPH && value == 0);

    std::vector<std::uint8_t> pixels(128 * 128);
    FontRenderSurface surface{};
    sceFontRenderSurfaceInit(&surface, pixels.data(), 128, 1, 128, 128);
    FontGlyphMetrics metrics{};
    FontRenderOutput result{};
    Require(sceFontGlyphRenderImageHorizontal(glyph, nullptr, renderer, &surface, 5.0f, 90.0f, &metrics, &result) == SCE_FONT_OK);
    Require(metrics.width == 40.0f && metrics.height == 70.0f && metrics.Horizontal.bearingX == 10.0f && metrics.Horizontal.bearingY == 70.0f && metrics.Horizontal.advance == 60.0f);
    Require(result.UpdateRect.x == 15 && result.UpdateRect.y == 20 && result.UpdateRect.w == 40 && result.UpdateRect.h == 70);
    Require(Coverage(pixels, 30, 50) == 0xFF && Coverage(pixels, 10, 50) == 0 && Coverage(pixels, 30, 10) == 0 && Coverage(pixels, 30, 95) == 0);

    pixels.assign(pixels.size(), 0);
    Require(sceFontGlyphRenderImage(glyph, nullptr, renderer, &surface, 5.0f, 20.0f, &metrics, &result) == SCE_FONT_OK);
    Require(result.UpdateRect.x == 15 && result.UpdateRect.y == 20 && result.UpdateRect.w == 40 && result.UpdateRect.h == 70);

    pixels.assign(pixels.size(), 0);
    FontStyleFrame frame{};
    Require(sceFontStyleFrameInit(&frame) == SCE_FONT_OK && sceFontStyleFrameSetScalePixel(&frame, 50.0f, 50.0f) == SCE_FONT_OK);
    Require(sceFontGlyphRenderImageVertical(glyph, &frame, renderer, &surface, 10.0f, 60.0f, &metrics, &result) == SCE_FONT_OK);
    Require(metrics.width == 20.0f && metrics.height == 35.0f && metrics.Horizontal.advance == 30.0f);
    Require(result.UpdateRect.x == 15 && result.UpdateRect.y == 25 && result.UpdateRect.w == 20 && result.UpdateRect.h == 35);

    Require(sceFontGlyphRenderImage(glyph, nullptr, nullptr, &surface, 0.0f, 0.0f, &metrics, &result) == SCE_FONT_ERROR_INVALID_RENDERER);
    Require(metrics.width == 0.0f && result.UpdateRect.w == 0);
    Require(sceFontGlyphRenderImage(glyph, nullptr, renderer, nullptr, 0.0f, 0.0f, &metrics, &result) == SCE_FONT_ERROR_INVALID_PARAMETER);
    Require(sceFontGlyphRenderImage(glyph, nullptr, renderer, &surface, 0.0f, 0.0f, nullptr, &result) == SCE_FONT_ERROR_INVALID_PARAMETER);
    FontStyleFrame uninitialized{};
    Require(sceFontGlyphRenderImage(glyph, &uninitialized, renderer, &surface, 0.0f, 0.0f, &metrics, &result) == SCE_FONT_ERROR_INVALID_PARAMETER);
    Require(sceFontGlyphRenderImage(&notAGlyph, nullptr, renderer, &surface, 0.0f, 0.0f, &metrics, &result) == SCE_FONT_ERROR_INVALID_GLYPH);
    Require(sceFontDeleteGlyph(&memory, &glyph) == SCE_FONT_OK);

    // The writing attribute selects how sceFontRenderCharGlyphImage places the glyph: below the line's
    // top edge when horizontal, around the column's centre line when vertical.
    Require(sceFontBindRenderer(font, renderer) == SCE_FONT_OK && sceFontSetupRenderScalePixel(font, 100.0f, 100.0f) == SCE_FONT_OK);
    pixels.assign(pixels.size(), 0);
    Require(sceFontRenderCharGlyphImage(font, 'A', &surface, 50.0f, 0.0f, &metrics, &result) == SCE_FONT_OK);
    const FontRenderOutput horizontal = result;
    Require(horizontal.UpdateRect.w == 40 && horizontal.UpdateRect.h == 70 && horizontal.UpdateRect.x == 60);
    Require(sceFontDefineAttribute(font, 0x41, nullptr) == SCE_FONT_OK);
    Require(sceFontRenderCharGlyphImage(font, 'A', &surface, 50.0f, 100.0f, &metrics, &result) == SCE_FONT_OK);
    Require(result.UpdateRect.w == 40 && result.UpdateRect.x != horizontal.UpdateRect.x);
    Require(sceFontDefineAttribute(font, 0x40, nullptr) == SCE_FONT_OK && sceFontUnbindRenderer(font) == SCE_FONT_OK);
}

static void TestWords(const FontMemory& memory, FontHandle font) {
    static const char32_t codes[] = U"ab  cd日本 e";
    Text text{codes, font};
    FontTextSource source{};
    Require(sceFontTextSourceInit(&source, codes, sizeof(codes) - sizeof(char32_t), ParseText, &text) == SCE_FONT_OK);
    FontString string = nullptr;
    Require(sceFontCreateString(&memory, &source, nullptr, &string) == SCE_FONT_OK);
    std::uint32_t count = 0;
    FontTextCharacter* characters = sceFontStringRefersTextCharacters(string, &count);
    Require(characters != nullptr && count == 10);

    int state = -1;
    Require(sceFontCharacterGetSyllableStringState(characters, &state) == SCE_FONT_OK && state == 0);
    Require(sceFontCharacterGetSyllableStringState(nullptr, &state) == SCE_FONT_ERROR_INVALID_PARAMETER);
    Require(sceFontCharacterGetSyllableStringState(characters, nullptr) == SCE_FONT_ERROR_INVALID_PARAMETER);

    void* words = nullptr;
    Require(sceFontCreateWords(&memory, nullptr, nullptr, &words) == SCE_FONT_ERROR_INVALID_PARAMETER && words == nullptr);
    FontTextSource uninitialized{};
    uninitialized.textParser = ParseText;
    Require(sceFontCreateWords(&memory, &uninitialized, nullptr, &words) == SCE_FONT_ERROR_INVALID_TEXT_SOURCE && words == nullptr);
    FontMemory badMemory{};
    Require(sceFontCreateWords(&badMemory, &source, nullptr, &words) == SCE_FONT_ERROR_INVALID_MEMORY && words == nullptr);
    Require(sceFontCreateWords(&memory, &source, nullptr, &words) == SCE_FONT_OK && words != nullptr);

    FontTextCharacter* last = nullptr;
    FontTextCharacter* next = nullptr;
    Require(sceFontWordsFindWordCharacters(words, &characters[0], nullptr, &last, &next) == SCE_FONT_OK && last == &characters[3] && next == &characters[4]);
    Require(sceFontWordsFindWordCharacters(words, &characters[4], nullptr, &last, &next) == SCE_FONT_OK && last == &characters[5] && next == &characters[6]);
    Require(sceFontWordsFindWordCharacters(words, &characters[6], nullptr, &last, &next) == SCE_FONT_OK && last == &characters[6] && next == &characters[7]);
    Require(sceFontWordsFindWordCharacters(words, &characters[7], nullptr, &last, &next) == SCE_FONT_OK && last == &characters[8] && next == &characters[9]);
    Require(sceFontWordsFindWordCharacters(words, &characters[9], nullptr, &last, &next) == SCE_FONT_OK && last == &characters[9] && next == nullptr);
    Require(sceFontWordsFindWordCharacters(words, &characters[2], nullptr, &last, &next) == SCE_FONT_OK && last == &characters[3] && next == &characters[4]);
    Require(sceFontWordsFindWordCharacters(words, &characters[0], &characters[1], &last, &next) == SCE_FONT_OK && last == &characters[0] && next == nullptr);
    Require(sceFontWordsFindWordCharacters(words, &characters[0], &characters[0], &last, &next) == SCE_FONT_ERROR_INVALID_PARAMETER && last == nullptr && next == nullptr);
    Require(sceFontWordsFindWordCharacters(words, nullptr, nullptr, &last, &next) == SCE_FONT_ERROR_INVALID_PARAMETER);
    Require(sceFontWordsFindWordCharacters(words, &characters[0], nullptr, nullptr, &next) == SCE_FONT_ERROR_INVALID_PARAMETER);
    Require(sceFontWordsFindWordCharacters(string, &characters[0], nullptr, &last, &next) == SCE_FONT_ERROR_INVALID_WORDS);

    Require(sceFontDestroyWords(&words) == SCE_FONT_OK && words == nullptr);
    Require(sceFontDestroyWords(&words) == SCE_FONT_ERROR_INVALID_WORDS);
    Require(sceFontDestroyWords(nullptr) == SCE_FONT_ERROR_INVALID_PARAMETER);
    Require(sceFontDestroyString(&string) == SCE_FONT_OK);
}

int main() {
    const FontMemoryInterface iface{Allocate, Release, nullptr, nullptr, nullptr, nullptr};
    FontMemory memory{};
    Require(sceFontMemoryInit(&memory, nullptr, 0, &iface, nullptr, nullptr, nullptr) == SCE_FONT_OK);
    FontLibrary library = nullptr;
    Require(sceFontCreateLibrary(&memory, sceFontSelectLibraryFt(0), &library) == SCE_FONT_OK);
    TestFtSupport(library);
    Require(sceFontSupportExternalFonts(library, 4, 0x52) == SCE_FONT_OK);
    FontRenderer renderer = nullptr;
    Require(sceFontCreateRenderer(&memory, sceFontSelectRendererFt(0), &renderer) == SCE_FONT_OK);

    const std::vector<unsigned char> fontData = SquareGlyphFont();
    FontHandle font = nullptr;
    Require(sceFontOpenFontMemory(library, fontData.data(), static_cast<std::uint32_t>(fontData.size()), nullptr, &font) == SCE_FONT_OK);
    TestFontAttributes(font);
    TestGlyphObjects(memory, font, renderer);
    TestWords(memory, font);
    Require(sceFontCloseFont(font) == SCE_FONT_OK);

    Require(sceFontDestroyRenderer(&renderer) == SCE_FONT_OK);
    Require(sceFontDestroyLibrary(&library) == SCE_FONT_OK);
    Require(allocations == 0);
    Require(sceFontMemoryTerm(&memory) == SCE_FONT_OK);
    std::puts("Font object tests passed");
    return 0;
}
