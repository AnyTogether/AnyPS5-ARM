#ifndef CORE_LIBS_PRX_LIBC_INCLUDE_RENAMEDOT_HPP
#define CORE_LIBS_PRX_LIBC_INCLUDE_RENAMEDOT_HPP

#include <filesystem>
#include <string>
#include "FilesystemError.hpp"

inline int RenameDotError_nid_no_patch(const char* path) {
    std::size_t length = std::char_traits<char>::length(path);
    const auto separator = [](char character) { return character == '/' || character == '\\'; };
    while (length > 1 && separator(path[length - 1])) --length;
    std::size_t start = length;
    while (start > 0 && !separator(path[start - 1])) --start;
    const std::size_t name = length - start;
    const bool dot = name == 1 && path[start] == '.';
    const bool dotDot = name == 2 && path[start] == '.' && path[start + 1] == '.';
    if (!dot && !dotDot) return 0;
    const std::string parent = start == 0 ? std::string(".") : std::string(path, start);
    std::filesystem::path resolved;
    if (const int error = ResolvePathError_nid_no_patch(parent.c_str(), resolved)) return error;
    std::error_code status;
    if (!std::filesystem::exists(resolved, status)) return 2;
    return std::filesystem::is_directory(resolved, status) ? 22 : 20;
}

#endif
