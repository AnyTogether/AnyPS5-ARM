#include "prx/libc/include/ApplicationHeap.hpp"
#include "prx/libc/include/GuestLocale.hpp"
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <string>

extern "C" {
extern GuestLocale::Implementation* _ZSt21_sceLibcClassicLocale_nid_postfix;
std::size_t APS5_VABI _ZNSt7collateIcE7_GetcatEPPKNSt6locale5facetEPKS1__nid_postfix(GuestLocale::Facet** facet, const GuestLocale::Implementation* const* locale);
std::size_t APS5_VABI _ZNSt7collateIwE7_GetcatEPPKNSt6locale5facetEPKS1__nid_postfix(GuestLocale::Facet** facet, const GuestLocale::Implementation* const* locale);
}

namespace {

std::size_t allocations = 0;
std::size_t frees = 0;
std::size_t lastSize = 0;
void* lastAllocation = nullptr;
void* lastFree = nullptr;

void require(bool condition) {
    if (!condition) std::abort();
}

template<typename TAction>
void reject(TAction action) {
    bool rejected = false;
    try { action(); } catch (const std::exception&) { rejected = true; }
    require(rejected);
}

void* APS5_VABI allocate(std::size_t bytes) {
    ++allocations;
    lastSize = bytes;
    lastAllocation = std::malloc(bytes);
    return lastAllocation;
}

void APS5_VABI release(void* pointer) {
    ++frees;
    lastFree = pointer;
    std::free(pointer);
}

void* APS5_VABI allocateZeroed(std::size_t, std::size_t) { std::abort(); }
void* APS5_VABI reallocate(void*, std::size_t) { std::abort(); }
void* APS5_VABI align(std::size_t, std::size_t) { std::abort(); }
void* APS5_VABI realign(void*, std::size_t, std::size_t) { std::abort(); }
int APS5_VABI posixAlign(void**, std::size_t, std::size_t) { std::abort(); }

const GuestLocale::CollateVtable& Vtable(const GuestLocale::Facet* facet) {
    return *reinterpret_cast<const GuestLocale::CollateVtable*>(facet->vtable);
}

int Compare(const GuestLocale::CollateFacet* facet, const std::string& left, const std::string& right) {
    return Vtable(&facet->base).compare(facet, left.data(), left.data() + left.size(), right.data(), right.data() + right.size());
}

std::uint64_t Hash(const GuestLocale::CollateFacet* facet, const std::string& text) {
    return static_cast<std::uint64_t>(Vtable(&facet->base).hash(facet, text.data(), text.data() + text.size()));
}

}

int main() {
    const std::array<void*, 10> api{reinterpret_cast<void*>(&allocate), reinterpret_cast<void*>(&release), reinterpret_cast<void*>(&allocateZeroed), reinterpret_cast<void*>(&reallocate), reinterpret_cast<void*>(&align), reinterpret_cast<void*>(&realign), reinterpret_cast<void*>(&posixAlign)};
    ApplicationHeapRegister_nid_no_patch(api.data());

    const GuestLocale::Implementation* const* classic = &_ZSt21_sceLibcClassicLocale_nid_postfix;
    require(_ZNSt7collateIcE7_GetcatEPPKNSt6locale5facetEPKS1__nid_postfix(nullptr, classic) == 1);
    GuestLocale::Facet existing{};
    GuestLocale::Facet* facet = &existing;
    require(_ZNSt7collateIcE7_GetcatEPPKNSt6locale5facetEPKS1__nid_postfix(&facet, classic) == 1);
    require(facet == &existing && allocations == 0);

    GuestLocale::Implementation french = *_ZSt21_sceLibcClassicLocale_nid_postfix;
    french.name = "fr_FR";
    const GuestLocale::Implementation* frenchPointer = &french;
    facet = nullptr;
    reject([&] { _ZNSt7collateIcE7_GetcatEPPKNSt6locale5facetEPKS1__nid_postfix(&facet, &frenchPointer); });
    require(facet == nullptr && allocations == 0);

    require(_ZNSt7collateIcE7_GetcatEPPKNSt6locale5facetEPKS1__nid_postfix(&facet, classic) == 1);
    require(facet != nullptr && allocations == 1 && lastSize == sizeof(GuestLocale::CollateFacet) && lastAllocation == facet);
    const auto* collate = reinterpret_cast<const GuestLocale::CollateFacet*>(facet);
    require(facet->references == 0 && collate->collation == nullptr && collate->wideCollation == nullptr);

    require(Compare(collate, "abc", "abd") == -1);
    require(Compare(collate, "abd", "abc") == 1);
    require(Compare(collate, "a", "c") == -1);
    require(Compare(collate, "abc", "abc") == 0);
    require(Compare(collate, "ab", "abc") == -1);
    require(Compare(collate, "abc", "ab") == 1);
    require(Compare(collate, "", "") == 0);
    require(Compare(collate, "", "a") == -1);
    require(Compare(collate, "\x80", "a") == 1);
    require(Compare(collate, std::string("a\0", 2), "a") == 1);
    require(Compare(collate, std::string("a\0b", 3), std::string("a\0c", 3)) == -1);
    require(Vtable(facet).compare(collate, nullptr, nullptr, nullptr, nullptr) == 0);
    const char text[] = "abc";
    reject([&] { Vtable(facet).compare(collate, text + 2, text, text, text + 1); });
    reject([&] { Vtable(facet).compare(collate, nullptr, text, text, text + 1); });

    require(Hash(collate, "") == 0xcbf29ce484222325ull);
    require(Hash(collate, "a") == 0xaf63dc4c8601ec8cull);
    require(Hash(collate, "foobar") == 0x85944171f73967e8ull);
    require(Hash(collate, "\xff") == ((0xcbf29ce484222325ull ^ 0xffull) * 0x100000001b3ull));
    reject([&] { Vtable(facet).hash(collate, text + 1, text); });

    GuestLocale::String result;
    std::memset(&result, 0xcd, sizeof(result));
    const std::string shortText = "hello";
    require(Vtable(facet).transform(&result, collate, shortText.data(), shortText.data() + shortText.size()) == &result);
    require(result.reserved == 0xcdcdcdcdcdcdcdcdull && result.size == 5 && result.capacity == 15 && std::strcmp(result.buffer, "hello") == 0);
    require(allocations == 1);

    std::memset(&result, 0xcd, sizeof(result));
    require(Vtable(facet).transform(&result, collate, nullptr, nullptr) == &result);
    require(result.size == 0 && result.capacity == 15 && result.buffer[0] == 0);

    const std::string fifteen(15, 'q');
    require(Vtable(facet).transform(&result, collate, fifteen.data(), fifteen.data() + fifteen.size()) == &result);
    require(result.size == 15 && result.capacity == 15 && std::string(result.buffer) == fifteen && allocations == 1);

    const std::string longText = "collation of a longer text";
    require(Vtable(facet).transform(&result, collate, longText.data(), longText.data() + longText.size()) == &result);
    require(allocations == 2 && lastSize == 32 && result.pointer == lastAllocation);
    require(result.size == longText.size() && result.capacity == 31 && std::string(result.pointer) == longText);
    std::free(result.pointer);

    const std::string largestSmall(4079, 'z');
    require(Vtable(facet).transform(&result, collate, largestSmall.data(), largestSmall.data() + largestSmall.size()) == &result);
    require(allocations == 3 && lastSize == 4080 && result.pointer == lastAllocation && result.capacity == 4079 && std::string(result.pointer) == largestSmall);
    std::free(result.pointer);

    const std::string smallestLarge(4080, 'y');
    require(Vtable(facet).transform(&result, collate, smallestLarge.data(), smallestLarge.data() + smallestLarge.size()) == &result);
    const auto raw = reinterpret_cast<std::uintptr_t>(lastAllocation);
    const auto aligned = reinterpret_cast<std::uintptr_t>(result.pointer);
    require(allocations == 4 && lastSize == 4096 + 0x27);
    require(aligned % 0x20 == 0 && aligned >= raw + 8 && aligned <= raw + 0x27 && reinterpret_cast<void**>(result.pointer)[-1] == lastAllocation);
    require(result.size == 4080 && result.capacity == 4095 && std::string(result.pointer) == smallestLarge);
    std::free(lastAllocation);

    const std::string embedded("a\0b", 3);
    reject([&] { Vtable(facet).transform(&result, collate, embedded.data(), embedded.data() + embedded.size()); });
    reject([&] { Vtable(facet).transform(nullptr, collate, text, text + 1); });
    require(allocations == 4);

    Vtable(facet).facet.retain(facet);
    Vtable(facet).facet.retain(facet);
    require(facet->references == 2);
    require(Vtable(facet).facet.release(facet) == nullptr && facet->references == 1);
    require(Vtable(facet).facet.release(facet) == facet && facet->references == 0);
    Vtable(facet).facet.destroy(facet);
    require(frees == 0);
    Vtable(facet).facet.deleteObject(facet);
    require(frees == 1 && lastFree == collate);

    using Wide = std::u16string;
    struct WideVtable {
        GuestLocale::FacetVtable facet;
        int (APS5_VABI *compare)(const GuestLocale::CollateFacet*, const char16_t*, const char16_t*, const char16_t*, const char16_t*);
        void* (APS5_VABI *transform)(void*, const GuestLocale::CollateFacet*, const char16_t*, const char16_t*);
        std::int64_t (APS5_VABI *hash)(const GuestLocale::CollateFacet*, const char16_t*, const char16_t*);
    };
    struct WideResult {
        std::uint64_t reserved;
        union {
            char16_t buffer[8];
            char16_t* pointer;
        };
        std::uint64_t size;
        std::uint64_t capacity;
    };
    GuestLocale::Facet* wide = nullptr;
    reject([&] { _ZNSt7collateIwE7_GetcatEPPKNSt6locale5facetEPKS1__nid_postfix(&wide, &frenchPointer); });
    require(wide == nullptr && _ZNSt7collateIwE7_GetcatEPPKNSt6locale5facetEPKS1__nid_postfix(nullptr, classic) == 1);
    require(_ZNSt7collateIwE7_GetcatEPPKNSt6locale5facetEPKS1__nid_postfix(&wide, classic) == 1);
    require(wide != nullptr && allocations == 5 && lastSize == sizeof(GuestLocale::CollateFacet) && lastAllocation == wide);
    const auto& wideVtable = *reinterpret_cast<const WideVtable*>(wide->vtable);
    const auto* wideCollate = reinterpret_cast<const GuestLocale::CollateFacet*>(wide);
    const auto wideCompare = [&](const Wide& left, const Wide& right) {
        return wideVtable.compare(wideCollate, left.data(), left.data() + left.size(), right.data(), right.data() + right.size());
    };
    require(wideCompare(u"abc", u"abd") == -1 && wideCompare(u"abd", u"abc") == 1 && wideCompare(u"abc", u"abc") == 0);
    require(wideCompare(u"ab", u"abc") == -1 && wideCompare(u"\u00e9", u"z") == 1 && wideCompare(u"\uffff", u"\u0100") == 1);
    const Wide wideText = u"abc";
    reject([&] { wideVtable.compare(wideCollate, wideText.data() + 2, wideText.data(), wideText.data(), wideText.data() + 1); });
    require(static_cast<std::uint64_t>(wideVtable.hash(wideCollate, wideText.data(), wideText.data())) == 0xcbf29ce484222325ull);
    require(static_cast<std::uint64_t>(wideVtable.hash(wideCollate, u"\u0100", u"\u0100" + 1)) == ((0xcbf29ce484222325ull ^ 0x100ull) * 0x100000001b3ull));
    WideResult wideResult;
    std::memset(&wideResult, 0xcd, sizeof(wideResult));
    const Wide seven = u"seven!!";
    require(wideVtable.transform(&wideResult, wideCollate, seven.data(), seven.data() + seven.size()) == &wideResult);
    require(wideResult.size == 7 && wideResult.capacity == 7 && Wide(wideResult.buffer) == seven && allocations == 5);
    const Wide eight = u"eight!!!";
    require(wideVtable.transform(&wideResult, wideCollate, eight.data(), eight.data() + eight.size()) == &wideResult);
    require(allocations == 6 && lastSize == 18 && wideResult.pointer == lastAllocation && wideResult.capacity == 8 && Wide(wideResult.pointer) == eight);
    std::free(wideResult.pointer);
    const Wide wideEmbedded(u"a\0b", 3);
    reject([&] { wideVtable.transform(&wideResult, wideCollate, wideEmbedded.data(), wideEmbedded.data() + wideEmbedded.size()); });
    wideVtable.facet.deleteObject(wide);
    require(frees == 2 && lastFree == wide);
    return 0;
}
