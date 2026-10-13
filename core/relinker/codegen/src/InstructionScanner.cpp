#include <codegen/IInstructionScanner.hpp>
#include <codegen/CodegenException.hpp>
#include <codegen/x86/X64InstructionDecoder.hpp>
#include <algorithm>
#include <memory>
#include <limits>
#include <string>

namespace Codegen {

class InstructionScanner : public IInstructionScanner {
public:
    explicit InstructionScanner(std::function<void(std::uint64_t, std::uint64_t)> progress) : progress(std::move(progress)) {}
    [[nodiscard]] std::vector<InstructionMatch> ScanCodeSection(const std::vector<std::uint8_t>& codeSection, Domain::FileByteOffset codeSectionOffset, Domain::FileByteOffset codeSectionSize) const override;

private:
    std::function<void(std::uint64_t, std::uint64_t)> progress;
};

std::vector<InstructionMatch> InstructionScanner::ScanCodeSection(const std::vector<std::uint8_t>& codeSection, const Domain::FileByteOffset codeSectionOffset, const Domain::FileByteOffset codeSectionSize) const {
    if (codeSectionSize > codeSection.size()) throw CodegenException("Code section exceeds the input buffer", codeSectionOffset);
    if (codeSectionSize > std::numeric_limits<Domain::FileByteOffset>::max() - codeSectionOffset) throw CodegenException("Code section offset overflow", codeSectionOffset);
    const auto limit = static_cast<std::size_t>(codeSectionSize);

    const X64InstructionDecoder decoder;
    std::vector<InstructionMatch> matches;
    std::size_t i = 0;

    if (progress) progress(0, limit);
    std::size_t lastReport = 0;
    while (i < limit) {
        const std::uint8_t* cursor = codeSection.data() + i;
        const std::size_t available = limit - i;

        std::size_t length = 0;
        try {
            length = decoder.Decode(cursor, available);
        } catch (const CodegenException& e) {
            if (std::all_of(cursor, cursor + available, [](const std::uint8_t b) { return b == 0; })) break;
            throw CodegenException(std::string("Cannot decode instruction: ") + e.what(), codeSectionOffset + i);
        }

        matches.push_back({codeSectionOffset + i, length});

        i += length;
        if (progress && i - lastReport >= 65536) {
            progress(i, limit);
            lastReport = i;
        }
    }

    if (progress) progress(limit, limit);
    return matches;
}

std::unique_ptr<IInstructionScanner> MakeInstructionScanner(std::function<void(std::uint64_t, std::uint64_t)> progress) {
    return std::make_unique<InstructionScanner>(std::move(progress));
}

}
