#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <vector>

extern "C" {
void APS5_VABI qsort_nid_postfix(void*, std::size_t, std::size_t, int (APS5_VABI*)(const void*, const void*));
}

namespace {

struct Element {
    int key;
    int tag;
};

int APS5_VABI CompareKeys(const void* left, const void* right) {
    const int first = static_cast<const Element*>(left)->key;
    const int second = static_cast<const Element*>(right)->key;
    return (first > second) - (first < second);
}

int APS5_VABI CompareFirstByte(const void* left, const void* right) {
    const int first = *static_cast<const unsigned char*>(left);
    const int second = *static_cast<const unsigned char*>(right);
    return (first > second) - (first < second);
}

bool ExpectOrder(const char* name, const std::vector<int>& keys, const std::vector<int>& tags) {
    std::vector<Element> elements;
    for (std::size_t index = 0; index < keys.size(); ++index) elements.push_back({keys[index], static_cast<int>(index)});
    qsort_nid_postfix(elements.data(), elements.size(), sizeof(Element), CompareKeys);
    for (std::size_t index = 0; index < tags.size(); ++index) {
        if (elements[index].tag != tags[index]) {
            std::fprintf(stderr, "%s: element %zu has tag %d, expected %d\n", name, index, elements[index].tag, tags[index]);
            return false;
        }
    }
    return true;
}

bool ExpectSorted(std::size_t size, std::size_t count) {
    std::vector<unsigned char> bytes(size * count);
    unsigned int state = static_cast<unsigned int>(size * 31 + count);
    for (auto& byte : bytes) {
        state = state * 1103515245u + 12345u;
        byte = static_cast<unsigned char>(state >> 16);
    }
    std::vector<unsigned char> counts(256);
    for (std::size_t index = 0; index < count; ++index) ++counts[bytes[index * size]];
    qsort_nid_postfix(bytes.data(), count, size, CompareFirstByte);
    for (std::size_t index = 0; index < count; ++index) {
        if (index > 0 && bytes[(index - 1) * size] > bytes[index * size]) {
            std::fprintf(stderr, "qsort of %zu %zu-byte elements is not sorted at %zu\n", count, size, index);
            return false;
        }
        --counts[bytes[index * size]];
    }
    for (const unsigned char remaining : counts) {
        if (remaining != 0) {
            std::fprintf(stderr, "qsort of %zu %zu-byte elements lost or duplicated elements\n", count, size);
            return false;
        }
    }
    return true;
}

}

int main() {
    bool correct = true;
    correct &= ExpectOrder("insertion sort", {1, 0, 1, 0}, {1, 3, 0, 2});
    correct &= ExpectOrder("median of three", {2, 1, 2, 0, 1, 2, 0, 1, 0, 2, 1, 0}, {11, 3, 6, 8, 10, 1, 7, 4, 9, 5, 0, 2});
    std::vector<int> keys;
    for (int index = 0; index < 48; ++index) keys.push_back((index * 7 + 3) % 5);
    correct &= ExpectOrder("pseudomedian of nine", keys,
        {21, 11, 36, 6, 1, 31, 16, 46, 41, 26, 29, 4, 24, 44, 9, 39, 34, 14, 19, 12, 2, 7, 17, 22,
         27, 32, 37, 42, 47, 5, 40, 30, 15, 35, 25, 20, 0, 45, 10, 28, 33, 13, 38, 8, 3, 23, 43, 18});
    for (const std::size_t size : {1, 3, 8, 24})
        for (const std::size_t count : {0, 1, 2, 6, 7, 8, 40, 41, 1000})
            correct &= ExpectSorted(size, count);
    return correct ? 0 : 1;
}
