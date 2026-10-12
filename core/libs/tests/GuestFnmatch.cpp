#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdio>
#include <cstdlib>
#include <stdexcept>
extern "C" int APS5_VABI fnmatch_nid_postfix(const char*, const char*, int);
struct Case {
    const char* pattern;
    const char* string;
    int flags;
    int result;
};
int main() {
    static const Case cases[] = {
        {"*.txt", "notes.txt", 0x00, 0},
        {"*.txt", "notes.TXT", 0x00, 1},
        {"*.txt", "notes.TXT", 0x10, 0},
        {"a?c", "abc", 0x00, 0},
        {"a?c", "ac", 0x00, 1},
        {"a[bc]d", "acd", 0x00, 0},
        {"a[!bc]d", "acd", 0x00, 1},
        {"a[^bc]d", "aed", 0x00, 0},
        {"a[a-c]d", "abd", 0x00, 0},
        {"a[a-c]d", "add", 0x00, 1},
        {"a[]]d", "a]d", 0x00, 0},
        {"a[a-]d", "a-d", 0x00, 0},
        {"[A-C]x", "bx", 0x10, 0},
        {"*", "dir/file", 0x00, 0},
        {"*", "dir/file", 0x02, 1},
        {"dir/*", "dir/file", 0x02, 0},
        {"*/file", "dir/file", 0x02, 0},
        {"dir?file", "dir/file", 0x02, 1},
        {"dir[/]file", "dir/file", 0x02, 1},
        {"*", ".hidden", 0x04, 1},
        {".*", ".hidden", 0x04, 0},
        {"?hidden", ".hidden", 0x04, 1},
        {"dir/*", "dir/.hidden", 0x06, 1},
        {"dir/*", "dir/.hidden", 0x04, 0},
        {"dir/.*", "dir/.hidden", 0x06, 0},
        {"dir", "dir/sub/file", 0x08, 0},
        {"dir/*", "dir/sub/file", 0x0a, 0},
        {"dir", "dirx", 0x08, 1},
        {"\\*", "*", 0x00, 0},
        {"\\*", "x", 0x00, 1},
        {"\\*", "\\*", 0x01, 0},
        {"a\\", "a", 0x00, 1},
        {"a\\", "a\\", 0x01, 0},
        {"a*b*c", "axxbyyc", 0x00, 0},
        {"a*b*c", "axxbyy", 0x00, 1},
        {"*a*", "bbb", 0x00, 1},
        {"**a", "ba", 0x00, 0},
        {"", "", 0x00, 0},
        {"", "x", 0x00, 1},
        {"x", "", 0x00, 1},
        {"[", "[", 0x00, 0},
        {"[a", "[a", 0x00, 0},
        {"a[", "a[", 0x00, 0},
        {"[!]x", "x", 0x00, 1},
        {"*/", "dir/", 0x02, 0},
        {"*/", "dir", 0x02, 1},
        {"[[:digit:]]", "7", 0x00, 1},
        {"[[:digit:]]", "d]", 0x00, 0},
        {"[[:digit:]]", ":]", 0x00, 0},
        {"a[[:alpha:]]", "ab", 0x00, 1},
    };
    for (const Case& entry : cases) {
        if (fnmatch_nid_postfix(entry.pattern, entry.string, entry.flags) != entry.result) {
            std::fprintf(stderr, "fnmatch(\"%s\", \"%s\", 0x%x) != %d\n", entry.pattern, entry.string, entry.flags, entry.result);
            std::abort();
        }
    }
    bool threw = false;
    try {
        fnmatch_nid_postfix(nullptr, "x", 0);
    } catch (const std::invalid_argument&) {
        threw = true;
    }
    if (!threw) std::abort();
    return 0;
}
