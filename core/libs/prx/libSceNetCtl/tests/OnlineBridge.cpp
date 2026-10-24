#include "FakeLauncher.hpp"
#include "prx/libSceNetCtl/include/OnlineBridge.hpp"
#include "prx/libSceNetCtl/include/OnlineEnvironment.hpp"
#include "prx/libSceNetCtl/include/OnlineObserver.hpp"
#include "prx/libSceNetCtl/include/OnlineWire.hpp"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <fstream>
#include <functional>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <unistd.h>
#include <vector>

using namespace Online;
using namespace std::chrono_literals;

namespace {

void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

Wire::Secret testSecret(std::uint8_t start = 0) {
    Wire::Secret secret{};
    for (std::size_t index = 0; index < secret.size(); ++index) secret[index] = static_cast<std::uint8_t>(start + index);
    return secret;
}

std::string hex(std::span<const std::uint8_t> bytes) {
    static constexpr char digits[] = "0123456789abcdef";
    std::string out;
    for (const auto byte : bytes) {
        out += digits[byte >> 4];
        out += digits[byte & 15];
    }
    return out;
}

Wire::Account signedInAccount() {
    Wire::Account account;
    account.signedIn = true;
    account.accountId = 0x1122334455667788ull;
    account.onlineId = "utku";
    account.country = "tr";
    account.language = "tr-TR";
    account.age = 30;
    account.address = 0xC6120001u;
    account.nat = 2;
    return account;
}

BridgeOptions fastOptions() {
    BridgeOptions options;
    options.retry = 50ms;
    options.firstAccount = 3000ms;
    options.handshake = 2000ms;
    options.build = "test-build";
    return options;
}

template <typename TPredicate>
bool eventually(TPredicate predicate, std::chrono::milliseconds timeout = 3000ms) {
    const auto until = std::chrono::steady_clock::now() + timeout;
    while (std::chrono::steady_clock::now() < until) {
        if (predicate()) return true;
        std::this_thread::sleep_for(5ms);
    }
    return predicate();
}

void headerLayout() {
    const auto bytes = Wire::EncodeHeader({0x00020304u, 0x0201, Wire::FlagReply, 0xA0B0C0D0u});
    const std::vector<std::uint8_t> expected{0x04, 0x03, 0x02, 0x00, 0x01, 0x02, 0x01, 0x00, 0xD0, 0xC0, 0xB0, 0xA0};
    require(std::vector<std::uint8_t>(bytes.begin(), bytes.end()) == expected, "header is little-endian length, type, flags, call");
    const auto decoded = Wire::DecodeHeader(bytes);
    require(decoded && decoded->length == 0x00020304u && decoded->type == 0x0201 && decoded->flags == Wire::FlagReply && decoded->call == 0xA0B0C0D0u,
        "header decodes back");
    require(!Wire::DecodeHeader(std::span(bytes).first(11)), "a short header is rejected");
    const auto big = Wire::EncodeHeader({Wire::MaxPayload + 1, 1, 0, 0});
    require(!Wire::DecodeHeader(big), "a frame over 16 MiB is rejected");
    const auto limit = Wire::EncodeHeader({Wire::MaxPayload, 1, 0, 0});
    require(Wire::DecodeHeader(limit).has_value(), "a frame of exactly 16 MiB is allowed");
}

void payloadEncoding() {
    Wire::Writer writer;
    writer.U8(1).U16(0x0203).U32(0x04050607).U64(0x08090a0b0c0d0e0full).Str("hi").Bytes(std::vector<std::uint8_t>{9, 8}).PairList({{"a", "b"}});
    require(hex(writer.Data()) == "01030207060504" "0f0e0d0c0b0a0908" "02006869" "020000000908" "0100" "010061" "010062", "field encoding is little-endian with u16 string and u32 bytes lengths");
    Wire::Reader reader(writer.Data());
    require(reader.U8() == 1 && reader.U16() == 0x0203 && reader.U32() == 0x04050607 && reader.U64() == 0x08090a0b0c0d0e0full, "integers read back");
    require(reader.Str() == "hi" && reader.Bytes() == std::vector<std::uint8_t>{9, 8}, "string and bytes read back");
    const auto pairs = reader.PairList();
    require(reader.Ok() && pairs.size() == 1 && pairs[0].first == "a" && pairs[0].second == "b" && reader.Remaining() == 0, "pairs read back");
    Wire::Reader past(std::span(writer.Data()).first(3));
    past.U32();
    require(!past.Ok() && past.Str().empty() && past.Remaining() == 0, "reading past the end fails and stays failed");
}

void messageRoundTrips() {
    Wire::Hello hello;
    hello.nonce = Wire::RandomNonce();
    hello.build = "abc123";
    hello.pid = 4242;
    const auto helloBack = Wire::DecodeHello(Wire::Encode(hello));
    require(helloBack && helloBack->protocol == Wire::Protocol && helloBack->nonce == hello.nonce && helloBack->build == "abc123" && helloBack->pid == 4242,
        "hello round trip");

    auto account = signedInAccount();
    auto accountBytes = Wire::Encode(account);
    const auto accountBack = Wire::DecodeAccount(accountBytes);
    require(accountBack && accountBack->signedIn && accountBack->accountId == account.accountId && accountBack->onlineId == "utku" &&
            accountBack->country == "tr" && accountBack->language == "tr-TR" && accountBack->age == 30 && accountBack->address == 0xC6120001u &&
            accountBack->nat == 2,
        "account round trip");
    accountBytes.push_back(0xEE);
    accountBytes.push_back(0xEE);
    require(Wire::DecodeAccount(accountBytes).has_value(), "fields added at the end by a newer launcher are ignored");
    accountBytes.resize(accountBytes.size() - 4);
    require(!Wire::DecodeAccount(accountBytes), "a truncated account is rejected");
    account.onlineId = "seventeen-letters";
    require(!Wire::DecodeAccount(Wire::Encode(account)), "an online ID over 16 letters is rejected");
    account.onlineId.clear();
    require(!Wire::DecodeAccount(Wire::Encode(account)), "a signed-in account without an online ID is rejected");
    require(Wire::DecodeAccount(Wire::Encode(Wire::Account{})).has_value(), "a signed-out account needs no ID");

    Wire::WebRequest request{7, "sessionManager", "/v1/playerSessions?fields=x", "POST", {{"Content-Type", "application/json"}}, {'{', '}'}};
    const auto requestBack = Wire::DecodeWebRequest(Wire::Encode(request));
    require(requestBack && requestBack->userId == 7 && requestBack->apiGroup == "sessionManager" && requestBack->path == request.path &&
            requestBack->method == "POST" && requestBack->headers == request.headers && requestBack->body == request.body,
        "web request round trip");
    Wire::WebReply reply{201, {{"X-Test", "1"}}, {1, 2, 3}};
    const auto replyBack = Wire::DecodeWebReply(Wire::Encode(reply));
    require(replyBack && replyBack->status == 201 && replyBack->headers == reply.headers && replyBack->body == reply.body, "web reply round trip");

    const auto refuseBack = Wire::DecodeRefuse(Wire::Encode(Wire::Refuse{Wire::RefuseReason::NoGame, "no game"}));
    require(refuseBack && refuseBack->reason == Wire::RefuseReason::NoGame && refuseBack->text == "no game", "refuse round trip");

    const auto frame = Wire::Frame(Wire::Type::WebRequest, 0, 5, std::vector<std::uint8_t>{1, 2});
    require(hex(frame) == "02000000" "0102" "0000" "05000000" "0102", "frame is header then payload");
}

void proofs() {
    const auto secret = testSecret();
    Wire::Nonce engine{};
    Wire::Nonce launcher{};
    for (std::size_t index = 0; index < engine.size(); ++index) {
        engine[index] = static_cast<std::uint8_t>(0x10 + index);
        launcher[index] = static_cast<std::uint8_t>(0x20 + index);
    }
    require(hex(Wire::MakeProof(secret, Wire::Side::Launcher, engine, launcher)) == "2f21186674e36ff3b7a3c64d49553ec40d66baf6fb0700e734cc6f09e6af4ab1",
        "launcher proof is HMAC-SHA-256 over its label and both nonces");
    require(hex(Wire::MakeProof(secret, Wire::Side::Engine, engine, launcher)) == "01c14bd9997ca8a60d1c14d1002ad65161b53ba7499fe653d2f73bc4b6641a4d",
        "engine proof is HMAC-SHA-256 over its label and both nonces");
    require(Wire::SameProof(Wire::MakeProof(secret, Wire::Side::Engine, engine, launcher), Wire::MakeProof(secret, Wire::Side::Engine, engine, launcher)),
        "equal proofs compare equal");
    require(!Wire::SameProof(Wire::MakeProof(secret, Wire::Side::Engine, engine, launcher), Wire::MakeProof(secret, Wire::Side::Launcher, engine, launcher)),
        "the two sides' proofs differ");
    require(Wire::RandomNonce() != Wire::RandomNonce(), "nonces are random");
}

void secrets() {
    const std::string lower = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
    require(Wire::ParseSecret(lower) == testSecret(), "lowercase hex secret parses");
    require(Wire::ParseSecret("000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F") == testSecret(), "uppercase hex secret parses");
    require(!Wire::ParseSecret(lower.substr(2)), "a short secret is rejected");
    require(!Wire::ParseSecret(lower + "00"), "a long secret is rejected");
    require(!Wire::ParseSecret("zz" + lower.substr(2)), "a non-hex secret is rejected");
}

void endpoints() {
    const char* secret = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
    require(!ParseEndpoint(nullptr, nullptr) && !ParseEndpoint("", ""), "unset or empty variables leave the bridge off");
    const auto endpoint = ParseEndpoint("127.0.0.1:41234", secret);
    require(endpoint && endpoint->port == 41234 && endpoint->secret == testSecret(), "a loopback port and secret parse");
    for (const char* bad : {"localhost:41234", "127.0.0.2:41234", "0.0.0.0:41234", "127.0.0.1:0", "127.0.0.1:65536", "127.0.0.1:12ab", "127.0.0.1:", "41234"}) {
        bool threw = false;
        try {
            ParseEndpoint(bad, secret);
        } catch (const std::runtime_error& error) {
            threw = std::string(error.what()).find("ANYPS5_ONLINE") != std::string::npos;
        }
        require(threw, std::string("an endpoint of ") + bad + " stops with an error naming the variable");
    }
    for (const auto& pair : std::vector<std::pair<const char*, const char*>>{{"127.0.0.1:41234", nullptr}, {"127.0.0.1:41234", "00ff"}, {nullptr, secret}}) {
        bool threw = false;
        try {
            ParseEndpoint(pair.first, pair.second);
        } catch (const std::runtime_error& error) {
            threw = std::string(error.what()).find("ANYPS5_ONLINE_SECRET") != std::string::npos;
        }
        require(threw, "a missing or malformed secret stops with an error naming the secret variable");
    }
}

void handshakeAndAccount() {
    Testing::FakeLauncher launcher(testSecret());
    launcher.SetAccount(signedInAccount());
    Bridge bridge(launcher.Port(), testSecret(), fastOptions());
    const auto state = bridge.Account();
    require(state.connected && state.account.signedIn && state.account.onlineId == "utku" && state.account.accountId == 0x1122334455667788ull,
        "the first account question waits for the launcher's account");
    require(state.generation == 1, "the first account is generation 1");
    require(launcher.ProvenSessions() == 1, "the launcher accepted the engine's proof");
    const auto hello = launcher.LastHello();
    require(hello && hello->protocol == Wire::Protocol && hello->build == "test-build" && hello->pid == static_cast<std::uint32_t>(::getpid()),
        "hello carries protocol, build and process");

    auto changed = signedInAccount();
    changed.onlineId = "renamed";
    launcher.SetAccount(changed);
    require(eventually([&] { return bridge.Account().account.onlineId == "renamed"; }), "a new account event replaces the cached one");
    require(bridge.Account().generation == 2, "a changed account moves the generation");
    launcher.SetAccount(changed);
    std::this_thread::sleep_for(50ms);
    require(bridge.Account().generation == 2, "an identical account event does not move the generation");
}

void webRequests() {
    Testing::FakeLauncher launcher(testSecret());
    launcher.SetAccount(signedInAccount());
    launcher.SetWebHandler([](const Wire::WebRequest& request) -> std::optional<Wire::WebReply> {
        if (request.apiGroup == "unsupported") return std::nullopt;
        if (request.apiGroup == "slow") {
            std::this_thread::sleep_for(500ms);
            return Wire::WebReply{200, {}, {}};
        }
        const int delay = std::stoi(request.path.substr(1));
        std::this_thread::sleep_for(std::chrono::milliseconds(delay));
        std::vector<std::uint8_t> body(request.path.begin(), request.path.end());
        body.insert(body.end(), request.body.begin(), request.body.end());
        return Wire::WebReply{static_cast<std::uint16_t>(200 + delay / 10), {{"X-Path", request.path}}, body};
    });
    Bridge bridge(launcher.Port(), testSecret(), fastOptions());
    require(bridge.Account().connected, "connected before requests");
    std::vector<std::thread> callers;
    std::vector<std::optional<Wire::WebReply>> replies(4);
    const int delays[] = {200, 10, 120, 60};
    for (int index = 0; index < 4; ++index) {
        callers.emplace_back([&, index] {
            Wire::WebRequest request{1, "group", "/" + std::to_string(delays[index]), "GET", {}, {static_cast<std::uint8_t>('a' + index)}};
            replies[index] = bridge.Web(request, 5000ms);
        });
    }
    for (auto& caller : callers) caller.join();
    for (int index = 0; index < 4; ++index) {
        const auto& reply = replies[index];
        const std::string path = "/" + std::to_string(delays[index]);
        std::string expected = path + static_cast<char>('a' + index);
        require(reply && reply->status == 200 + delays[index] / 10 && std::string(reply->body.begin(), reply->body.end()) == expected &&
                reply->headers.size() == 1 && reply->headers[0].second == path,
            "out-of-order replies reach the caller that asked");
    }
    require(!bridge.Web({1, "unsupported", "/", "GET", {}, {}}, 2000ms), "an unsupported reply is not offered");
    const auto started = std::chrono::steady_clock::now();
    require(!bridge.Web({1, "slow", "/", "GET", {}, {}}, 100ms), "a request that outlives its timeout is not offered");
    require(std::chrono::steady_clock::now() - started < 450ms, "the timeout is kept");
    require(bridge.Web({1, "group", "/0", "GET", {}, {}}, 2000ms).has_value(), "a late reply to a timed-out request is dropped and later ones work");
}

void wrongLauncherSecret() {
    Testing::FakeLauncher launcher(testSecret());
    launcher.SetProofSecret(testSecret(0x40));
    launcher.SetAccount(signedInAccount());
    auto options = fastOptions();
    options.firstAccount = 300ms;
    Bridge bridge(launcher.Port(), testSecret(), options);
    const auto state = bridge.Account();
    require(!state.connected && !state.account.signedIn, "a launcher that cannot prove the secret is not believed");
    require(launcher.Sessions() >= 1 && launcher.ProvenSessions() == 0, "the engine never sends its proof to an impostor");
    require(!bridge.Web({1, "g", "/", "GET", {}, {}}, 200ms), "no request goes to an impostor");
}

void refusedEngine() {
    Testing::FakeLauncher launcher(testSecret());
    launcher.SetRefusal(Wire::Refuse{Wire::RefuseReason::BadProof, "not this game"});
    Bridge bridge(launcher.Port(), testSecret(), fastOptions());
    const auto started = std::chrono::steady_clock::now();
    const auto state = bridge.Account();
    require(!state.connected && std::chrono::steady_clock::now() - started < 1500ms, "a refusal ends the first wait at once");
    const auto refusal = bridge.Refusal();
    require(refusal && refusal->reason == Wire::RefuseReason::BadProof && refusal->text == "not this game", "the refusal is kept");
    std::this_thread::sleep_for(200ms);
    require(launcher.Sessions() == 1, "a bad-proof refusal is final: the engine does not try again");
}

void dropAndReconnect() {
    Testing::FakeLauncher launcher(testSecret());
    launcher.SetAccount(signedInAccount());
    Bridge bridge(launcher.Port(), testSecret(), fastOptions());
    const auto first = bridge.Account();
    require(first.account.signedIn, "signed in before the drop");
    launcher.DropClient();
    require(eventually([&] { return launcher.ProvenSessions() == 2; }), "the engine connects again after the launcher drops it");
    const auto again = bridge.Account();
    require(again.connected && again.account.signedIn && again.generation > first.generation, "signed in again with a newer generation");
}

void signedOutWhileDown() {
    auto launcher = std::make_unique<Testing::FakeLauncher>(testSecret());
    launcher->SetAccount(signedInAccount());
    Bridge bridge(launcher->Port(), testSecret(), fastOptions());
    require(bridge.Account().account.signedIn, "signed in before the launcher quits");
    launcher.reset();
    require(eventually([&] { return !bridge.Account().connected; }), "the launcher quitting signs the user out");
    require(!bridge.Account().account.signedIn && !bridge.Web({1, "g", "/", "GET", {}, {}}, 200ms), "nothing is offered while it is gone");
}

void unknownFrames() {
    Testing::FakeLauncher launcher(testSecret());
    launcher.SetAccount(signedInAccount());
    launcher.SetWebHandler([](const Wire::WebRequest&) { return std::optional<Wire::WebReply>(Wire::WebReply{204, {}, {}}); });
    Bridge bridge(launcher.Port(), testSecret(), fastOptions());
    require(bridge.Account().connected, "connected");
    launcher.Send(static_cast<Wire::Type>(0x7777), 0, 0, {1, 2, 3});
    launcher.Send(static_cast<Wire::Type>(0x7778), 0, 99, {});
    require(launcher.WaitForUnsupported(99, 2000ms), "an unknown request from the launcher is answered unsupported");
    launcher.Send(Wire::Type::Account, 0, 0, {1});
    require(bridge.Account().account.onlineId == "utku", "a malformed account event is ignored");
    require(bridge.Web({1, "g", "/", "GET", {}, {}}, 2000ms).has_value(), "the connection survives unknown events");
    launcher.SendRaw(std::vector<std::uint8_t>{0xff, 0xff, 0xff, 0xff, 1, 0, 0, 0, 0, 0, 0, 0});
    require(eventually([&] { return launcher.ProvenSessions() == 2; }), "an oversized frame drops the connection, which is made again");
}

void observationsForwarded() {
    Testing::FakeLauncher launcher(testSecret());
    launcher.SetAccount(signedInAccount());
    Bridge bridge(launcher.Port(), testSecret(), fastOptions());
    require(bridge.Account().connected, "connected");
    bridge.Observe("{\"fn\":\"sceNpGetState\"}");
    require(launcher.WaitForObservations(1, 2000ms) && launcher.Observations()[0] == "{\"fn\":\"sceNpGetState\"}", "observations reach the launcher");
}

void noLauncher() {
    std::uint16_t port = 0;
    {
        Testing::FakeLauncher closed(testSecret());
        port = closed.Port();
    }
    auto options = fastOptions();
    options.firstAccount = 200ms;
    Bridge bridge(port, testSecret(), options);
    const auto started = std::chrono::steady_clock::now();
    const auto state = bridge.Account();
    const auto waited = std::chrono::steady_clock::now() - started;
    require(!state.connected && !state.account.signedIn, "without a launcher the user is signed out");
    require(waited < 1000ms, "the first wait is bounded");
    const auto again = std::chrono::steady_clock::now();
    bridge.Account();
    require(std::chrono::steady_clock::now() - again < 50ms, "only the first question waits");
}

std::vector<std::string> readLines(const std::string& path) {
    std::ifstream file(path);
    std::vector<std::string> lines;
    for (std::string line; std::getline(file, line);) lines.push_back(line);
    return lines;
}

void observerFile() {
    char pattern[] = "/tmp/online-observer-XXXXXX";
    const int descriptor = ::mkstemp(pattern);
    require(descriptor >= 0, "temporary file");
    ::close(descriptor);
    const std::string path = pattern;
    {
        Observer observer(path, 1000ms);
        std::vector<std::string> forwarded;
        observer.SetForward([&](std::string_view line) { forwarded.emplace_back(line); });
        const auto start = std::chrono::steady_clock::now();
        const std::int64_t signedOut = static_cast<std::int32_t>(0x80550006u);
        const std::int64_t ok = 0;
        observer.Record("libSceNpManager", "sceNpGetState", "{\"userId\":1}", "{\"state\":1}", &ok, start);
        for (int index = 1; index <= 5; ++index)
            observer.Record("libSceNpManager", "sceNpGetState", "{\"userId\":1}", "{\"state\":1}", &ok, start + std::chrono::milliseconds(index * 10));
        observer.Record("libSceNpManager", "sceNpGetState", "{\"userId\":1}", "{\"state\":1}", &ok, start + 1500ms);
        observer.Record("libSceNpManager", "sceNpGetState", "{\"userId\":1}", "{\"state\":1}", &ok, start + 1510ms);
        observer.Record("libSceNpManager", "sceNpGetOnlineId", "{\"userId\":1}", "{}", &signedOut, start + 1520ms);
        observer.Record("libSceNpManager", "sceNpGetState", "{\"userId\":2}", "{}", nullptr, start + 1530ms);
        observer.NotImplemented("sceNpMatching2Initialize");
        require(forwarded.size() == 6, "every written line is forwarded");
    }
    const auto lines = readLines(path);
    std::remove(path.c_str());
    require(lines.size() == 6, "identical calls are folded: " + std::to_string(lines.size()) + " lines");
    require(lines[0].find("\"fn\":\"sceNpGetState\"") != std::string::npos && lines[0].find("\"in\":{\"userId\":1}") != std::string::npos &&
            lines[0].find("\"out\":{\"state\":1}") != std::string::npos && lines[0].find("\"ret\":0") != std::string::npos &&
            lines[0].find("repeats") == std::string::npos,
        "the first call is written in full");
    require(lines[1].find("\"repeats\":5") != std::string::npos && lines[1].find("\"in\"") != std::string::npos, "a repeat after the interval says how many were folded");
    require(lines[2].find("\"ret\":-2141913082") != std::string::npos && lines[2].find("\"err\":\"0x80550006\"") != std::string::npos,
        "an error is written with its hex code");
    require(lines[3].find("\"repeats\":1") != std::string::npos && lines[3].find("\"in\"") == std::string::npos, "a change first closes the folded run");
    require(lines[4].find("\"in\":{\"userId\":2}") != std::string::npos && lines[4].find("\"ret\"") == std::string::npos, "a call without a result has no ret");
    require(lines[5].find("\"not_implemented\":true") != std::string::npos && lines[5].find("sceNpMatching2Initialize") != std::string::npos,
        "unimplemented exports are recorded");
    for (const auto& line : lines) require(line.starts_with("{\"v\":1,\"t_ms\":") && line.ends_with("}"), "every line is a v1 JSON object");
}

}

int main() {
    const std::vector<std::pair<const char*, std::function<void()>>> tests{
        {"header layout", headerLayout},
        {"payload encoding", payloadEncoding},
        {"message round trips", messageRoundTrips},
        {"proofs", proofs},
        {"secrets", secrets},
        {"endpoints", endpoints},
        {"handshake and account", handshakeAndAccount},
        {"web requests", webRequests},
        {"wrong launcher secret", wrongLauncherSecret},
        {"refused engine", refusedEngine},
        {"drop and reconnect", dropAndReconnect},
        {"signed out while down", signedOutWhileDown},
        {"unknown frames", unknownFrames},
        {"observations forwarded", observationsForwarded},
        {"no launcher", noLauncher},
        {"observer file", observerFile},
    };
    int failed = 0;
    for (const auto& [name, test] : tests) {
        try {
            test();
            std::cout << "ok   " << name << '\n';
        } catch (const std::exception& error) {
            ++failed;
            std::cout << "FAIL " << name << ": " << error.what() << '\n';
        }
    }
    return failed == 0 ? 0 : 1;
}
