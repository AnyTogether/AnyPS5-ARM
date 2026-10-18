#include "ShaderCacheDirectory.hpp"
#include <iostream>
#include <new>
#include <stdexcept>

static bool FailLargeAllocation = false;

void* operator new(std::size_t size) {
    if (FailLargeAllocation && size > 1024 * 1024) throw std::bad_alloc();
    if (auto* memory = std::malloc(size == 0 ? 1 : size)) return memory;
    throw std::bad_alloc();
}
void operator delete(void* memory) noexcept { std::free(memory); }
void operator delete(void* memory, std::size_t) noexcept { std::free(memory); }
void* operator new[](std::size_t size) { return ::operator new(size); }
void operator delete[](void* memory) noexcept { ::operator delete(memory); }
void operator delete[](void* memory, std::size_t) noexcept { ::operator delete(memory); }

static void Require(bool ok) { if (!ok) throw std::runtime_error("Cache file read failed"); }

int main() {
    const auto path = std::filesystem::temp_directory_path() / ("anyps5-cache-read-" +
        std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    int status = 0;
    try {
        std::vector<std::byte> bytes{std::byte{1}};
        Require(!ShaderRecompiler::ReadWholeFile(path, bytes) && bytes.empty());
        { std::ofstream file(path, std::ios::binary); }
        Require(ShaderRecompiler::ReadWholeFile(path, bytes) && bytes.empty());
        const std::vector<char> payload(2 * 1024 * 1024, 'S');
        { std::ofstream file(path, std::ios::binary | std::ios::trunc); file.write(payload.data(), payload.size()); Require(static_cast<bool>(file)); }
        Require(ShaderRecompiler::ReadWholeFile(path, bytes) && bytes.size() == payload.size());
        Require(bytes.front() == std::byte{'S'} && bytes.back() == std::byte{'S'});
        std::vector<std::byte> failed{std::byte{1}};
        FailLargeAllocation = true;
        const auto read = ShaderRecompiler::ReadWholeFile(path, failed);
        FailLargeAllocation = false;
        Require(!read && failed.empty());
        std::cout << "5 cache file read cases passed\n";
    } catch (const std::exception& error) { FailLargeAllocation = false; std::cerr << error.what() << '\n'; status = 1; }
    std::error_code error;
    std::filesystem::remove(path, error);
    return status;
}
