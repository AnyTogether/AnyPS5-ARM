#include "prx/libSceFont/include/FontTypes.hpp"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <exception>

extern "C" {
int APS5_VABI sceFontCreateWritingLine(const FontMemory*, std::int32_t, const void*, void**);
int APS5_VABI sceFontDestroyWritingLine(void**);
int APS5_VABI sceFontWritingLineClear(void*);
int APS5_VABI sceFontWritingLineWritesOrder(void*, std::uint64_t, const FontWritingMetrics*, void*);
const FontWritingLineStep* APS5_VABI sceFontWritingLineRefersRenderStep(void*);
int APS5_VABI sceFontWritingLineGetRenderMetrics(void*, FontWritingMetrics*);
int APS5_VABI sceFontWritingLineGetOrderingSpace(void*, float*, float*, float*, float*);
}

static void Check(bool value, int line) {
    if (!value) {
        std::fprintf(stderr, "Font writing line check failed at line %d\n", line);
        std::abort();
    }
}
#define Require(value) Check((value), __LINE__)

template <typename F>
static bool Throws(F f) {
    try {
        f();
    } catch (const std::exception&) {
        return true;
    }
    return false;
}

struct WritingLineDetail {
    std::uint16_t detailId;
    std::uint16_t reserved[3];
    void* reservedPointers[3];
};

constexpr std::uint64_t SPACE_BEFORE = std::uint64_t{1} << 30;
constexpr std::uint64_t SPACE_AFTER = std::uint64_t{1} << 31;

static std::uint64_t Attribute(std::uint64_t level, std::uint64_t flags = 0) {
    return 0xFA | (level << 8) | flags;
}

static bool Same(const FontWritingMetrics& a, const FontWritingMetrics& b) {
    return a.advanceX == b.advanceX && a.advanceY == b.advanceY && a.Extent.top == b.Extent.top &&
           a.Extent.bottom == b.Extent.bottom && a.Extent.left == b.Extent.left && a.Extent.right == b.Extent.right;
}

static bool SpaceIs(void* line, float advance, float head, float inner, float tail) {
    float gotAdvance = -1.0f;
    float gotHead = -1.0f;
    float gotInner = -1.0f;
    float gotTail = -1.0f;
    return sceFontWritingLineGetOrderingSpace(line, &gotAdvance, &gotHead, &gotInner, &gotTail) == SCE_FONT_OK && gotAdvance == advance &&
           gotHead == head && gotInner == inner && gotTail == tail;
}

static bool StepIs(const FontWritingLineStep* step, float x, float progress, const FontWritingMetrics& run, void* orderer) {
    return step && step->x == x && step->y == 0.0f && step->advanceX == 0.0f && step->advanceY == 0.0f &&
           step->spacingProgress == progress && step->writingOrderer == orderer && step->Adjusting.x == 0.0f &&
           step->Adjusting.y == 0.0f && Same(step->Metrics, run);
}

static bool OrderIs(void* line, const std::uint64_t* levels, const std::size_t* order, std::size_t count) {
    static int orderers[16];
    const FontWritingMetrics run{1.0f, 0.0f, {-1.0f, 1.0f, 0.0f, 1.0f}};
    if (sceFontWritingLineClear(line) != SCE_FONT_OK) return false;
    for (std::size_t i = 0; i < count; ++i) {
        if (sceFontWritingLineWritesOrder(line, Attribute(levels[i]), &run, &orderers[i]) != SCE_FONT_OK) return false;
    }
    for (std::size_t i = 0; i < count; ++i) {
        const FontWritingLineStep* step = sceFontWritingLineRefersRenderStep(line);
        if (!step || step->writingOrderer != &orderers[order[i]]) return false;
    }
    return sceFontWritingLineRefersRenderStep(line) == nullptr;
}

int main() {
    FontMemory memory{};
    void* line = nullptr;
    Require(Throws([&] { sceFontCreateWritingLine(&memory, 0x10, nullptr, nullptr); }));
    Require(Throws([&] { sceFontCreateWritingLine(&memory, 0x13, nullptr, &line); }) && line == nullptr);
    Require(Throws([&] { sceFontCreateWritingLine(&memory, 0, nullptr, &line); }) && line == nullptr);
    WritingLineDetail detail{0x0FD4, {}, {}};
    Require(Throws([&] { sceFontCreateWritingLine(&memory, 0x10, &detail, &line); }) && line == nullptr);
    detail.detailId = 0x0FD5;
    Require(sceFontCreateWritingLine(&memory, 0x10, &detail, &line) == SCE_FONT_OK && line != nullptr);
    void* ltr = nullptr;
    Require(sceFontCreateWritingLine(&memory, 0x12, nullptr, &ltr) == SCE_FONT_OK && ltr != nullptr && ltr != line);
    void* rtl = nullptr;
    Require(sceFontCreateWritingLine(&memory, 0x11, nullptr, &rtl) == SCE_FONT_OK && rtl != nullptr);

    FontWritingMetrics metrics{1.0f, 1.0f, {1.0f, 1.0f, 1.0f, 1.0f}};
    Require(SpaceIs(line, 0.0f, 0.0f, 0.0f, 0.0f));
    Require(sceFontWritingLineRefersRenderStep(line) == nullptr);
    Require(sceFontWritingLineGetRenderMetrics(line, &metrics) == SCE_FONT_OK && Same(metrics, {}));

    int a = 0;
    int b = 0;
    int c = 0;
    int d = 0;
    const FontWritingMetrics runA{10.0f, 0.0f, {-8.0f, 2.0f, 1.0f, 9.0f}};
    const FontWritingMetrics runB{6.0f, 0.0f, {-12.0f, 3.0f, -1.0f, 5.0f}};
    const FontWritingMetrics runC{8.0f, 0.0f, {-4.0f, 1.0f, 2.0f, 5.0f}};
    const FontWritingMetrics runD{4.0f, 0.0f, {-4.0f, 1.0f, 0.0f, 20.0f}};

    Require(Throws([&] { sceFontWritingLineWritesOrder(nullptr, Attribute(0), &runA, &a); }));
    Require(Throws([&] { sceFontWritingLineWritesOrder(line, 1, &runA, &a); }));
    Require(Throws([&] { sceFontWritingLineWritesOrder(line, 0x1FB, &runA, &a); }));
    Require(Throws([&] { sceFontWritingLineWritesOrder(line, Attribute(0), &runA, nullptr); }));
    Require(Throws([&] { sceFontWritingLineWritesOrder(line, Attribute(0x7F), &runA, &a); }));
    Require(sceFontWritingLineRefersRenderStep(line) == nullptr);

    Require(sceFontWritingLineWritesOrder(line, 0, &runA, &a) == SCE_FONT_OK);
    Require(sceFontWritingLineWritesOrder(line, Attribute(0), &runB, &b) == SCE_FONT_OK);
    Require(SpaceIs(line, 16.0f, 1.0f, 0.0f, 1.0f));
    Require(sceFontWritingLineGetRenderMetrics(line, &metrics) == SCE_FONT_OK && Same(metrics, {}));
    Require(StepIs(sceFontWritingLineRefersRenderStep(line), 0.0f, 0.0f, runA, &a));
    Require(sceFontWritingLineGetRenderMetrics(line, &metrics) == SCE_FONT_OK && Same(metrics, {}));
    Require(StepIs(sceFontWritingLineRefersRenderStep(line), 10.0f, 0.0f, runB, &b));
    Require(sceFontWritingLineGetRenderMetrics(line, &metrics) == SCE_FONT_OK && Same(metrics, {10.0f, 0.0f, {-8.0f, 2.0f, 1.0f, 9.0f}}));
    Require(sceFontWritingLineRefersRenderStep(line) == nullptr);
    Require(sceFontWritingLineGetRenderMetrics(line, &metrics) == SCE_FONT_OK && Same(metrics, {16.0f, 0.0f, {-12.0f, 3.0f, 1.0f, 15.0f}}));
    Require(StepIs(sceFontWritingLineRefersRenderStep(line), 0.0f, 0.0f, runA, &a));
    Require(sceFontWritingLineGetRenderMetrics(line, &metrics) == SCE_FONT_OK && Same(metrics, {}));

    Require(sceFontWritingLineWritesOrder(line, Attribute(0x7E), nullptr, &d) == SCE_FONT_OK);
    Require(SpaceIs(line, 0.0f, 0.0f, 0.0f, 0.0f));
    Require(StepIs(sceFontWritingLineRefersRenderStep(line), 0.0f, 0.0f, {}, &d));
    Require(sceFontWritingLineRefersRenderStep(line) == nullptr);

    Require(sceFontWritingLineClear(line) == SCE_FONT_OK);
    Require(sceFontWritingLineRefersRenderStep(line) == nullptr);
    Require(sceFontWritingLineWritesOrder(line, Attribute(0), &runA, &a) == SCE_FONT_OK);
    Require(sceFontWritingLineWritesOrder(line, Attribute(1), &runB, &b) == SCE_FONT_OK);
    Require(sceFontWritingLineWritesOrder(line, Attribute(1), &runC, &c) == SCE_FONT_OK);
    Require(sceFontWritingLineWritesOrder(line, Attribute(0), &runD, &d) == SCE_FONT_OK);
    Require(SpaceIs(line, 28.0f, 1.0f, 0.0f, -16.0f));
    Require(StepIs(sceFontWritingLineRefersRenderStep(line), 0.0f, 0.0f, runA, &a));
    Require(StepIs(sceFontWritingLineRefersRenderStep(line), 10.0f, 0.0f, runC, &c));
    Require(StepIs(sceFontWritingLineRefersRenderStep(line), 18.0f, 0.0f, runB, &b));
    Require(StepIs(sceFontWritingLineRefersRenderStep(line), 24.0f, 0.0f, runD, &d));
    Require(sceFontWritingLineRefersRenderStep(line) == nullptr);

    Require(sceFontWritingLineClear(line) == SCE_FONT_OK);
    Require(sceFontWritingLineWritesOrder(line, Attribute(0), &runA, &a) == SCE_FONT_OK);
    Require(sceFontWritingLineWritesOrder(line, Attribute(1), &runB, &b) == SCE_FONT_OK);
    Require(sceFontWritingLineWritesOrder(line, Attribute(2), &runC, &c) == SCE_FONT_OK);
    Require(sceFontWritingLineWritesOrder(line, Attribute(2), &runD, &d) == SCE_FONT_OK);
    Require(sceFontWritingLineWritesOrder(line, Attribute(1), &runA, &b) == SCE_FONT_OK);
    Require(sceFontWritingLineWritesOrder(line, Attribute(0), &runB, &a) == SCE_FONT_OK);
    Require(StepIs(sceFontWritingLineRefersRenderStep(line), 0.0f, 0.0f, runA, &a));
    Require(StepIs(sceFontWritingLineRefersRenderStep(line), 10.0f, 0.0f, runA, &b));
    Require(StepIs(sceFontWritingLineRefersRenderStep(line), 20.0f, 0.0f, runC, &c));
    Require(StepIs(sceFontWritingLineRefersRenderStep(line), 28.0f, 0.0f, runD, &d));
    Require(StepIs(sceFontWritingLineRefersRenderStep(line), 32.0f, 0.0f, runB, &b));
    Require(StepIs(sceFontWritingLineRefersRenderStep(line), 38.0f, 0.0f, runB, &a));
    Require(sceFontWritingLineRefersRenderStep(line) == nullptr);

    Require(sceFontWritingLineWritesOrder(ltr, Attribute(0, SPACE_AFTER), &runA, &a) == SCE_FONT_OK);
    Require(SpaceIs(ltr, 10.0f, 1.0f, 0.0f, 1.0f));
    Require(sceFontWritingLineWritesOrder(ltr, Attribute(0), &runC, &c) == SCE_FONT_OK);
    Require(SpaceIs(ltr, 18.0f, 1.0f, 3.0f, 3.0f));
    Require(sceFontWritingLineWritesOrder(ltr, Attribute(0, SPACE_BEFORE), &runB, &b) == SCE_FONT_OK);
    Require(SpaceIs(ltr, 24.0f, 1.0f, 5.0f, 1.0f));
    Require(StepIs(sceFontWritingLineRefersRenderStep(ltr), 0.0f, 0.0f, runA, &a));
    Require(StepIs(sceFontWritingLineRefersRenderStep(ltr), 10.0f, 3.0f / 5.0f, runC, &c));
    Require(StepIs(sceFontWritingLineRefersRenderStep(ltr), 18.0f, 1.0f, runB, &b));
    Require(sceFontWritingLineRefersRenderStep(ltr) == nullptr);

    Require(sceFontWritingLineClear(ltr) == SCE_FONT_OK);
    Require(sceFontWritingLineWritesOrder(ltr, Attribute(0, SPACE_AFTER), &runA, &a) == SCE_FONT_OK);
    Require(sceFontWritingLineWritesOrder(ltr, Attribute(1), &runC, &c) == SCE_FONT_OK);
    Require(SpaceIs(ltr, 18.0f, 1.0f, 3.0f, 3.0f));
    Require(sceFontWritingLineWritesOrder(ltr, Attribute(1), &runB, &b) == SCE_FONT_OK);
    Require(SpaceIs(ltr, 24.0f, 1.0f, 0.0f, 3.0f));
    Require(sceFontWritingLineWritesOrder(ltr, Attribute(1, SPACE_AFTER), &runD, &d) == SCE_FONT_OK);
    Require(SpaceIs(ltr, 28.0f, 1.0f, -16.0f, 3.0f));
    Require(StepIs(sceFontWritingLineRefersRenderStep(ltr), 0.0f, 0.0f, runA, &a));
    Require(StepIs(sceFontWritingLineRefersRenderStep(ltr), 10.0f, 1.0f / -16.0f, runD, &d));
    Require(StepIs(sceFontWritingLineRefersRenderStep(ltr), 14.0f, 1.0f, runB, &b));
    Require(StepIs(sceFontWritingLineRefersRenderStep(ltr), 20.0f, 1.0f, runC, &c));
    Require(sceFontWritingLineRefersRenderStep(ltr) == nullptr);

    Require(sceFontWritingLineWritesOrder(rtl, Attribute(0, SPACE_AFTER), &runA, &a) == SCE_FONT_OK);
    Require(sceFontWritingLineWritesOrder(rtl, Attribute(0), &runC, &c) == SCE_FONT_OK);
    Require(SpaceIs(rtl, 18.0f, 5.0f, 15.0f, 9.0f));
    Require(StepIs(sceFontWritingLineRefersRenderStep(rtl), 0.0f, 0.0f, runC, &c));
    Require(StepIs(sceFontWritingLineRefersRenderStep(rtl), 8.0f, 1.0f, runA, &a));
    Require(sceFontWritingLineRefersRenderStep(rtl) == nullptr);
    Require(sceFontWritingLineGetRenderMetrics(rtl, &metrics) == SCE_FONT_OK && Same(metrics, {18.0f, 0.0f, {-8.0f, 2.0f, 2.0f, 17.0f}}));

    const std::uint64_t nested[] = {0, 1, 2, 3, 1, 1, 0};
    const std::size_t nestedOrder[] = {0, 5, 4, 2, 3, 1, 6};
    Require(OrderIs(ltr, nested, nestedOrder, 7));
    const std::uint64_t repeated[] = {0, 1, 1, 2, 2, 0, 1, 2, 2, 0};
    const std::size_t repeatedOrder[] = {0, 3, 4, 2, 1, 5, 7, 8, 6, 9};
    Require(OrderIs(ltr, repeated, repeatedOrder, 10));
    const std::uint64_t skipped[] = {0, 2, 3, 3, 2, 1, 0};
    const std::size_t skippedOrder[] = {0, 5, 1, 3, 2, 4, 6};
    Require(OrderIs(ltr, skipped, skippedOrder, 7));

    const FontWritingMetrics runE{10.0f, 3.0f, {-8.0f, 2.0f, 1.0f, 9.0f}};
    const FontWritingMetrics runF{6.0f, -1.0f, {-12.0f, 3.0f, -1.0f, 5.0f}};
    Require(sceFontWritingLineClear(ltr) == SCE_FONT_OK);
    Require(sceFontWritingLineWritesOrder(ltr, Attribute(0), &runE, &a) == SCE_FONT_OK);
    Require(sceFontWritingLineWritesOrder(ltr, Attribute(0), &runF, &b) == SCE_FONT_OK);
    auto* adjusted = const_cast<FontWritingLineStep*>(sceFontWritingLineRefersRenderStep(ltr));
    Require(adjusted && adjusted->x == 0.0f && adjusted->y == 0.0f && adjusted->writingOrderer == &a);
    adjusted->Adjusting = {2.0f, 5.0f};
    const FontWritingLineStep* second = sceFontWritingLineRefersRenderStep(ltr);
    Require(second && second->x == 10.0f && second->y == 3.0f && second->Adjusting.x == 0.0f && second->Adjusting.y == 0.0f);
    Require(sceFontWritingLineGetRenderMetrics(ltr, &metrics) == SCE_FONT_OK && Same(metrics, {12.0f, 8.0f, {-3.0f, 7.0f, 3.0f, 11.0f}}));
    Require(sceFontWritingLineRefersRenderStep(ltr) == nullptr);
    Require(sceFontWritingLineGetRenderMetrics(ltr, &metrics) == SCE_FONT_OK && Same(metrics, {16.0f, 2.0f, {-9.0f, 7.0f, 3.0f, 15.0f}}));

    float space = 7.0f;
    Require(sceFontWritingLineGetOrderingSpace(rtl, nullptr, nullptr, &space, nullptr) == SCE_FONT_OK && space == 15.0f);
    Require(Throws([&] { sceFontWritingLineGetOrderingSpace(rtl, &space, &space, &space, nullptr); }));
    Require(Throws([&] { sceFontWritingLineGetOrderingSpace(nullptr, &space, nullptr, nullptr, nullptr); }));
    Require(Throws([&] { sceFontWritingLineGetRenderMetrics(nullptr, &metrics); }));
    Require(Throws([&] { sceFontWritingLineGetRenderMetrics(rtl, nullptr); }));
    Require(Throws([&] { sceFontWritingLineClear(nullptr); }));

    int notALine = 0;
    Require(sceFontWritingLineRefersRenderStep(nullptr) == nullptr);
    Require(Throws([&] { sceFontWritingLineClear(&notALine); }));
    Require(Throws([&] { sceFontWritingLineRefersRenderStep(&notALine); }));
    Require(Throws([&] { sceFontWritingLineGetOrderingSpace(&notALine, &space, &space, &space, &space); }));
    void* bogus = &notALine;
    Require(Throws([&] { sceFontDestroyWritingLine(&bogus); }) && bogus == &notALine);

    void* destroyed = line;
    Require(sceFontDestroyWritingLine(&line) == SCE_FONT_OK && line == nullptr);
    Require(sceFontDestroyWritingLine(&line) == SCE_FONT_OK && line == nullptr);
    Require(sceFontDestroyWritingLine(nullptr) == SCE_FONT_OK);
    Require(Throws([&] { sceFontWritingLineClear(destroyed); }));
    Require(Throws([&] { sceFontWritingLineWritesOrder(destroyed, Attribute(0), &runA, &a); }));
    Require(sceFontDestroyWritingLine(&ltr) == SCE_FONT_OK && ltr == nullptr);
    Require(sceFontDestroyWritingLine(&rtl) == SCE_FONT_OK && rtl == nullptr);
    std::puts("font writing line: ok");
}
