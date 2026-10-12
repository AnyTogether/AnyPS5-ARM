#include <elfpatcher/general/ProgramHeaderLayoutBuilder.hpp>
#include <io/ByteWriter.hpp>
#include <iostream>
#include <limits>
#include <stdexcept>

class KeepAll : public Elfpatcher::ISegmentFilter {
public:
    bool ShouldSkip(const Domain::ProgramHeader&) const override { return false; }
};

static void Require(bool ok) { if (!ok) throw std::runtime_error("Program layout range validation failed"); }

int main() {
    try {
        Elfpatcher::ProgramHeaderLayoutBuilder builder(std::make_shared<KeepAll>(), std::make_shared<Io::ByteWriter>());
        constexpr auto maximum = std::numeric_limits<std::uint64_t>::max();
        Domain::ProgramHeader load{};
        load.Type = 1; load.MappedAddress = maximum - 3; load.MemorySize = 8;
        bool rejected = false;
        try { builder.ComputeExtraBlockVaddr({load}, 0x1000); } catch (const std::exception&) { rejected = true; }
        Require(rejected);
        load.MappedAddress = 0x1000; load.MemorySize = 0x1000;
        Require(builder.ComputeExtraBlockVaddr({load}, 0x1003) == 0x2003);
        Elfpatcher::ProgramHeaderLayoutRequest valid{64, 56, 6, {load}, 0x1000, 0x2000, 0x100, 0x1000, 16, 0x1010, 8};
        std::vector<std::uint8_t> output(0x1100, 0xA5);
        Require(builder.WriteLayout(output, valid) == 6);
        for (int kind = 0; kind < 11; ++kind) {
            auto request = valid;
            switch (kind) {
                case 0: request.PhEntSize = 55; break;
                case 1: request.PhOff = maximum - 10; break;
                case 2: request.PhOff = 0x10F0; break;
                case 3: request.ExtraBlockVaddr = maximum - 10; break;
                case 4: request.DynamicSegmentSize = maximum; break;
                case 5: request.InterpSize = maximum; break;
                case 6: request.DynamicSegmentOffset = maximum; break;
                case 7: request.InterpOffset = maximum; break;
                case 8: request.ExtraBlockOffset = maximum; break;
                case 9: request.ExtraBlockSize = 0x1000; break;
                case 10: request.PhOff = 0xF00; request.ExtraBlockVaddr = maximum - 0x1fff; break;
            }
            std::vector<std::uint8_t> bytes(0x1100, 0xA5);
            const auto before = bytes;
            rejected = false;
            try { builder.WriteLayout(bytes, request); } catch (const std::exception&) { rejected = true; }
            Require(rejected && bytes == before);
        }
        std::cout << "14 program layout cases passed\n";
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
