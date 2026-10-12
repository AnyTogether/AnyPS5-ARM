#include <codegen/x86/X64InstructionRewriter.hpp>
#include <iostream>
#include <stdexcept>

static void Require(bool ok) { if (!ok) throw std::runtime_error("Invalid rewrite boundary accepted"); }

int main() {
    try {
        const Codegen::X64InstructionRewriter rewriter;
        for (const auto& code : {std::vector<std::uint8_t>{0xB8, 0x90, 0x90, 0x90, 0x90, 0xC3},
                               std::vector<std::uint8_t>{0x48, 0x8B, 0x05, 0x90, 0x90, 0x90, 0x90, 0xC3},
                               std::vector<std::uint8_t>{0xE8, 0x90, 0x90, 0x90, 0x90, 0xC3}}) {
            const auto original = code;
            for (std::size_t offset = 1; offset + 1 < code.size(); ++offset) {
                bool rejected = false;
                try { (void)rewriter.Rewrite(code, {offset, {0x90}}); }
                catch (const std::exception&) { rejected = true; }
                Require(rejected && code == original);
            }
            const auto result = rewriter.Rewrite(code, {0, {0x90}});
            Require(result.Bytes == std::vector<std::uint8_t>{0x90, 0xC3});
        }
        const auto result = rewriter.Rewrite({0x90, 0x90, 0xC3}, {1, {0x90, 0x90}});
        Require(result.Bytes == std::vector<std::uint8_t>{0x90, 0x90, 0x90, 0xC3});
        std::cout << "18 rewrite boundary cases passed\n";
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
