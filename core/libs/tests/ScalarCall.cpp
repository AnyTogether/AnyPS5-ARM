#include "Translation/TranslationContext.hpp"
#include "Translation/InstructionTranslator.hpp"
#include "RdnaDecoder/RdnaScalarOpDecoder.hpp"
#include "RdnaDecoder/RdnaInstructionDecoder.hpp"
#include "RdnaDecoder/RdnaMemoryOpDecoder.hpp"
#include "ControlFlow/GraphBuilder.hpp"
#include <array>
#include <cstdio>
#include <algorithm>
#include <initializer_list>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

using namespace ShaderRecompiler;

static void Require(bool value) {
    if (!value) throw std::runtime_error("scalar call regression");
}

template <typename TFunction>
static void ExpectThrow(const char* needle, TFunction fn) {
    try {
        fn();
    } catch (const std::exception& error) {
        if (std::string(error.what()).find(needle) == std::string::npos) {
            throw std::runtime_error(std::string("expected ") + needle + ", got " + error.what());
        }
        return;
    }
    throw std::runtime_error(std::string("expected throw containing ") + needle);
}

static RdnaInstruction Call(std::uint32_t pc, std::uint32_t link, std::uint32_t immediate) {
    const std::array<std::uint32_t, 1> code{0xbb000000u | (link << 16u) | (immediate & 0xffffu)};
    return DecodeRdnaSopk(pc, code, 0u);
}

static RdnaInstruction Sop1(std::uint32_t pc, std::uint32_t destination, std::uint32_t op, std::uint32_t source) {
    const std::array<std::uint32_t, 1> code{0xbe800000u | (destination << 16u) | (op << 8u) | source};
    return DecodeRdnaSop1(pc, code, 0u);
}

static RdnaInstruction Sopp(std::uint32_t pc, std::uint32_t op, std::uint32_t immediate = 0u) {
    const std::array<std::uint32_t, 1> code{0xbf800000u | (op << 16u) | immediate};
    return DecodeRdnaSopp(pc, code, 0u);
}

static ControlFlowGraph Build(std::initializer_list<RdnaInstruction> instructions) {
    RdnaProgram program;
    program.instructions.assign(instructions);
    return GraphBuilder{}.Build(program);
}

static void CheckDecode() {
    const auto instruction = Call(0x40u, 8u, 7u);
    Require(instruction.op == RdnaOpcode::SCallB64);
    Require(instruction.family == RdnaInstructionFamily::SOPK);
    Require(instruction.destination.kind == RdnaOperandKind::ScalarRegister && instruction.destination.reg == 8u);
    Require(instruction.dataDwordCount == 2u && instruction.wordCount == 1u);
    Require(instruction.branchTarget == 0x60u);
    Require(Call(0x40u, 8u, 0xfff9u).branchTarget == 0x28u);
    Require(Call(0x20000u, 8u, 0x8000u).branchTarget == 4u);
    Require(Call(0u, 8u, 0x7fffu).branchTarget == 0x20000u);
}

static std::string TranslateDump(const RdnaInstruction& instruction) {
    IrProgram program;
    auto& block = program.CreateBlock();
    program.SetEntryBlock(block);
    program.BlockOrder() = {&block};
    program.Metadata().blockInfo.resize(1);
    TranslationContext context(program, block, 256);
    context.TranslateInstruction(instruction);
    return ProgramToString(program);
}

static void CheckLink() {
    const auto dump = TranslateDump(Call(0x50u, 8u, 2u));
    Require(dump.find("0x0000000000000054") != std::string::npos);
    Require(dump == TranslateDump(Sop1(0x50u, 8u, 0x1fu, 0u)));
}

static void CheckCallAfterEnd() {
    const std::array<std::uint32_t, 5> code{0xbb080001u, 0xbf810000u, 0xbf800000u, 0xbe802008u, 0xbf810000u};
    const auto decoded = RdnaInstructionDecoder{}.Decode(code);
    Require(decoded.instructions.size() == code.size());
    const auto cfg = GraphBuilder{}.Build(decoded);
    const auto& caller = cfg.FindBlockByProgramCounter(0u);
    const auto& callee = cfg.FindBlockByProgramCounter(8u);
    Require(caller.terminator.kind == TerminatorKind::Branch && caller.terminator.trueBlock == callee.id);
    Require(callee.terminator.kind == TerminatorKind::Branch && callee.terminator.trueBlock == cfg.FindBlockByProgramCounter(4u).id);
    ShaderComputeInputInfo computeInfo{};
    TranslateOptions options{};
    options.stage = ShaderStageKind::Compute;
    options.inputInfo.compute = &computeInfo;
    static_cast<void>(InstructionTranslator{}.Translate(decoded, cfg, options));
}

static std::vector<std::uint32_t> UserDataCaller() {
    return {0x7e020280u, 0xbe940383u, 0xbe8e0300u, 0xbe8f0301u, 0xbe8e210eu, 0xbe8e0302u, 0xbe8f0303u, 0xbe8e210eu,
        0x80948114u, 0xbf078014u, 0xbf85fff7u, 0xbf810000u, 0x30306c73u};
}

static std::vector<UserDataCall> UserDataCalls(const std::vector<std::uint32_t>& code, std::uint32_t userDataCount = 8u) {
    const SwappcInfo swappc{false, 0u, userDataCount};
    return FindUserDataCalls(RdnaInstructionDecoder{}.Decode(code), swappc);
}

static void CheckUserDataCalls() {
    const SwappcInfo swappc{false, 0u, 8u};
    const auto caller = UserDataCaller();
    const auto program = RdnaInstructionDecoder{}.Decode(caller);
    const auto calls = FindUserDataCalls(program, swappc);
    Require(calls.size() == 2u);
    Require(calls[0].programCounter == 0x10u && calls[0].linkRegister == 14u && calls[0].userDataRegister == 0u);
    Require(calls[1].programCounter == 0x1cu && calls[1].linkRegister == 14u && calls[1].userDataRegister == 2u);
    ExpectThrow("not statically resolvable", [&] { static_cast<void>(GraphBuilder{}.Build(program, &swappc)); });

    auto overwritten = caller;
    overwritten[1] = 0xbe800380u;
    const auto second = UserDataCalls(overwritten);
    Require(second.size() == 1u && second[0].programCounter == 0x1cu);
    auto entered = caller;
    entered[10] = 0xbf85fff8u;
    const auto afterLabel = UserDataCalls(entered);
    Require(afterLabel.size() == 1u && afterLabel[0].programCounter == 0x1cu);
    auto looped = caller;
    looped[8] = 0xbe820380u;
    const auto beforeWrite = UserDataCalls(looped);
    Require(beforeWrite.size() == 1u && beforeWrite[0].programCounter == 0x10u);
    Require(UserDataCalls({0xbe842104u, 0xbf810000u}, 6u).empty());
    const auto direct = UserDataCalls({0xbe8e2104u, 0xbf810000u}, 6u);
    Require(direct.size() == 1u && direct[0].linkRegister == 14u && direct[0].userDataRegister == 4u);

    const std::vector<std::uint32_t> addFive{0x4a020285u, 0xbe80200eu};
    const std::vector<std::uint32_t> addSixtyFour{0x4a0202c0u, 0xbe80200eu};
    Require(UserDataCalleeLength(addFive, 14u) == 2u);
    Require(!UserDataCalleeLength(std::vector<std::uint32_t>{0x4a020285u}, 14u).has_value());
    ExpectThrow("reads its program counter", [] { static_cast<void>(UserDataCalleeLength(std::vector<std::uint32_t>{0xbe901f00u, 0xbe80200eu}, 14u)); });
    ExpectThrow("makes a call", [] { static_cast<void>(UserDataCalleeLength(std::vector<std::uint32_t>{0xbe92210eu, 0xbe80200eu}, 14u)); });
    ExpectThrow("ends the program", [] { static_cast<void>(UserDataCalleeLength(std::vector<std::uint32_t>{0xbf810000u}, 14u)); });
    ExpectThrow("jumps through another register pair", [] { static_cast<void>(UserDataCalleeLength(std::vector<std::uint32_t>{0xbe802010u}, 14u)); });
    ExpectThrow("before code it branches to", [] { static_cast<void>(UserDataCalleeLength(std::vector<std::uint32_t>{0xbf840001u, 0xbe80200eu, 0x4a020285u, 0xbe80200eu}, 14u)); });

    const std::vector<std::vector<std::uint32_t>> callees{addFive, addSixtyFour};
    const auto linked = LinkUserDataCalls(program, calls, callees);
    Require(linked.size() == 17u && linked[4] == 0xbb0e0007u && linked[7] == 0xbb0e0006u && linked[16] == 0xbf9f0000u);
    Require(std::equal(addFive.begin(), addFive.end(), linked.begin() + 12) && std::equal(addSixtyFour.begin(), addSixtyFour.end(), linked.begin() + 14));
    auto readsPc = caller;
    readsPc[1] = 0xbe941f00u;
    ExpectThrow("cannot have user-data callees linked", [&] {
        const auto readsPcProgram = RdnaInstructionDecoder{}.Decode(readsPc);
        static_cast<void>(LinkUserDataCalls(readsPcProgram, FindUserDataCalls(readsPcProgram, swappc), callees));
    });

    const auto linkedProgram = RdnaInstructionDecoder{}.Decode(linked);
    const auto cfg = GraphBuilder{}.Build(linkedProgram, &swappc);
    const auto block = [&](std::uint32_t programCounter) { return cfg.FindBlockByProgramCounter(programCounter).id; };
    Require(cfg.FindBlockByProgramCounter(0x08u).terminator.trueBlock == block(0x30u));
    Require(cfg.FindBlockByProgramCounter(0x30u).terminator.trueBlock == block(0x14u));
    Require(cfg.FindBlockByProgramCounter(0x14u).terminator.trueBlock == block(0x38u));
    Require(cfg.FindBlockByProgramCounter(0x38u).terminator.trueBlock == block(0x20u));
    ShaderComputeInputInfo computeInfo{};
    TranslateOptions options{};
    options.stage = ShaderStageKind::Compute;
    options.inputInfo.compute = &computeInfo;
    options.userDataCount = 8u;
    static_cast<void>(InstructionTranslator{}.Translate(linkedProgram, cfg, options));

    auto readsLink = linked;
    readsLink[8] = 0xbe94030eu;
    ExpectThrow("escapes the constant-offset call/return model", [&] { static_cast<void>(GraphBuilder{}.Build(RdnaInstructionDecoder{}.Decode(readsLink), &swappc)); });
    auto writesInside = linked;
    writesInside[12] = 0xbe8e0300u;
    ExpectThrow("escapes the constant-offset call/return model", [&] { static_cast<void>(GraphBuilder{}.Build(RdnaInstructionDecoder{}.Decode(writesInside), &swappc)); });
    auto sameCopy = linked;
    sameCopy[7] = 0xbb0e0004u;
    ExpectThrow("is shared with another call", [&] { static_cast<void>(GraphBuilder{}.Build(RdnaInstructionDecoder{}.Decode(sameCopy), &swappc)); });
}

static void CheckRejections() {
    ExpectThrow("invalid instruction boundary", [] {
        Build({Call(0u, 8u, 16u), Sopp(4u, 1u)});
    });
    ExpectThrow("invalid instruction boundary", [] {
        const std::array<std::uint32_t, 7> code{0xbb080002u, 0xbf810000u, 0xbe8003ffu, 0u, 0xbe802008u, 0xbf810000u, 0xbf810000u};
        static_cast<void>(GraphBuilder{}.Build(RdnaInstructionDecoder{}.Decode(code)));
    });
    ExpectThrow("code span bounds", [] {
        const std::array<std::uint32_t, 2> outside{0xbb080010u, 0xbf810000u};
        static_cast<void>(RdnaInstructionDecoder{}.Decode(outside));
    });
    ExpectThrow("code span bounds", [] {
        const std::array<std::uint32_t, 2> outside{0xbb08fffeu, 0xbf810000u};
        static_cast<void>(RdnaInstructionDecoder{}.Decode(outside));
    });
    ExpectThrow("no paired s_setpc_b64 return", [] {
        Build({Call(0u, 8u, 0u), Sopp(4u, 1u)});
    });
    for (const auto link : {9u, 105u, 106u, 125u}) {
        ExpectThrow("ordinary aligned scalar register pair", [=] {
            Build({Call(0u, link, 0u), Sopp(4u, 1u)});
        });
    }
    ExpectThrow("escapes the constant-offset call/return model", [] {
        Build({Call(0u, 8u, 1u), Sopp(4u, 1u), Sop1(8u, 8u, 3u, 128u), Sop1(12u, 0u, 0x20u, 8u)});
    });
    ExpectThrow("recursive scalar call", [] {
        Build({Call(0u, 8u, 0xffffu), Sop1(4u, 0u, 0x20u, 8u), Sopp(8u, 1u)});
    });
    ExpectThrow("is shared with another call", [] {
        Build({Call(0u, 8u, 2u), Call(4u, 8u, 1u), Sopp(8u, 1u), Sop1(12u, 0u, 0x20u, 8u)});
    });
    ExpectThrow("multiple s_setpc_b64 returns", [] {
        Build({Call(0u, 8u, 1u), Sopp(4u, 1u), Sop1(8u, 0u, 0x20u, 8u), Sop1(12u, 0u, 0x20u, 8u)});
    });
    ExpectThrow("control flow enters the call region", [] {
        Build({Call(0u, 8u, 2u), Sopp(4u, 2u, 1u), Sopp(8u, 1u), Sopp(12u, 0u), Sop1(16u, 0u, 0x20u, 8u)});
    });
    ExpectThrow("control flow leaves the call region", [] {
        Build({Call(0u, 8u, 1u), Sopp(4u, 1u), Sopp(8u, 2u, 2u), Sop1(12u, 0u, 0x20u, 8u), Sopp(16u, 1u), Sopp(20u, 1u)});
    });
}

static void CheckGuards(const std::string& only) {
    bool checked = false;
    const auto check = [&](const char* name, const char* needle, auto fn) {
        if (only.empty() || only == name) {
            checked = true;
            ExpectThrow(needle, fn);
        }
    };
    check("tuple", "escapes the constant-offset call/return model", [] {
        auto load = Sopp(8u, 0u);
        load.family = RdnaInstructionFamily::SMEM;
        load.op = RdnaOpcode::SLoadDwordx8;
        load.dataDwordCount = 8u;
        load.destination.kind = RdnaOperandKind::ScalarRegister;
        load.destination.reg = 4u;
        Build({Call(0u, 8u, 1u), Sopp(4u, 1u), load, Sop1(12u, 0u, 0x20u, 8u)});
    });
    check("wrong_return", "escapes the constant-offset call/return model", [] {
        Build({Call(0u, 8u, 1u), Sopp(4u, 1u), Sop1(8u, 0u, 0x20u, 9u)});
    });
    check("fallthrough", "control flow enters the call region", [] {
        Build({Call(0u, 8u, 2u), Sopp(4u, 0u), Sopp(8u, 0u), Sopp(12u, 0u), Sop1(16u, 0u, 0x20u, 8u)});
    });
    check("conditional_fallthrough", "control flow enters the call region", [] {
        Build({Call(0u, 8u, 2u), Sopp(4u, 2u), Sopp(8u, 4u, 2u), Sopp(12u, 0u), Sop1(16u, 0u, 0x20u, 8u), Sopp(20u, 1u)});
    });
    check("return_before_target", "return precedes the call target", [] {
        Build({Call(0u, 8u, 2u), Sopp(4u, 1u), Sop1(8u, 0u, 0x20u, 8u), Sopp(12u, 0u), Sopp(16u, 1u)});
    });
    check("descriptor", "escapes the constant-offset call/return model", [] {
        const std::array<std::uint32_t, 2> code{0xe0381000u, 0x80020401u};
        const auto load = DecodeRdnaMubuf(8u, code, 0u);
        Require(load.source1.reg == 8u);
        Build({Call(0u, 10u, 1u), Sopp(4u, 1u), load, Sop1(16u, 0u, 0x20u, 10u)});
    });
    check("relative_read", "escapes the constant-offset call/return model", [] {
        Build({Call(0u, 8u, 1u), Sopp(4u, 1u), Sop1(8u, 0u, 0x2eu, 0u), Sop1(12u, 0u, 0x20u, 8u)});
    });
    if (only.empty()) {
        for (const auto link : {0u, 104u}) {
            const auto cfg = Build({Call(0u, link, 1u), Sopp(4u, 1u), Sop1(8u, 0u, 0x20u, link)});
            Require(cfg.FindBlockByProgramCounter(0u).terminator.kind == TerminatorKind::Branch);
        }
    }
    Require(checked);
}

int main(int argc, char** argv) {
    try {
        if (argc == 1) {
            CheckDecode();
            CheckLink();
            CheckCallAfterEnd();
            CheckRejections();
            CheckUserDataCalls();
            CheckGuards("");
        } else {
            Require(argc == 2);
            CheckGuards(argv[1]);
        }
    } catch (const std::exception& error) {
        std::fprintf(stderr, "scalar call regression: %s\n", error.what());
        return 1;
    }
    return 0;
}
