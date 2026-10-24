#include "prx/libSceNetCtl/include/OnlineObserver.hpp"
#include "prx/libSceNetCtl/include/Online.hpp"
#include <cerrno>
#include <cstring>

namespace Online {

Observer::Observer(std::string path, std::chrono::milliseconds repeatEvery)
    : path(std::move(path)), repeatEvery(repeatEvery), started(std::chrono::steady_clock::now()) {}

Observer::~Observer() {
    Flush();
    std::lock_guard lock(mutex);
    if (file) std::fclose(file);
}

void Observer::SetForward(Forward value) {
    std::lock_guard lock(mutex);
    forward = std::move(value);
}

void Observer::open() {
    if (file || failed) return;
    file = std::fopen(path.c_str(), "a");
    if (!file) {
        failed = true;
        std::fprintf(stderr, "online observation: cannot open %s: %s\n", path.c_str(), std::strerror(errno));
    }
}

std::string Observer::line(std::string_view library, std::string_view function, std::string_view in, std::string_view out, const std::int64_t* result,
    std::chrono::steady_clock::time_point now, std::uint64_t repeats) const {
    const auto milliseconds = std::chrono::duration_cast<std::chrono::milliseconds>(now - started).count();
    std::string text = "{\"v\":1,\"t_ms\":" + std::to_string(milliseconds);
    if (!library.empty()) text += ",\"lib\":" + Fields::quote(library);
    text += ",\"fn\":" + Fields::quote(function);
    if (!in.empty() && in != "{}") text += ",\"in\":" + std::string(in);
    if (!out.empty() && out != "{}") text += ",\"out\":" + std::string(out);
    if (result) {
        text += ",\"ret\":" + std::to_string(*result);
        if (*result < 0) {
            char hex[16];
            std::snprintf(hex, sizeof(hex), "0x%08x", static_cast<unsigned>(static_cast<std::uint32_t>(*result)));
            text += ",\"err\":\"" + std::string(hex) + "\"";
        }
    }
    if (repeats != 0) text += ",\"repeats\":" + std::to_string(repeats);
    text += "}";
    return text;
}

void Observer::write(std::string text, std::chrono::steady_clock::time_point) {
    open();
    if (file) {
        text += '\n';
        std::fwrite(text.data(), 1, text.size(), file);
        std::fflush(file);
        text.pop_back();
    }
    if (forward) forward(text);
}

void Observer::Record(std::string_view library, std::string_view function, std::string_view in, std::string_view out, const std::int64_t* result) {
    Record(library, function, in, out, result, std::chrono::steady_clock::now());
}

void Observer::Record(std::string_view library, std::string_view function, std::string_view in, std::string_view out, const std::int64_t* result,
    std::chrono::steady_clock::time_point now) {
    std::string key(in);
    key += '\x1f';
    key += out;
    key += '\x1f';
    if (result) key += std::to_string(*result);
    std::string name(library);
    name += '/';
    name += function;
    std::lock_guard lock(mutex);
    auto& entry = last[name];
    if (!entry.key.empty() && entry.key == key) {
        if (now - entry.written < repeatEvery) {
            ++entry.repeats;
            return;
        }
        write(line(library, function, in, out, result, now, entry.repeats), now);
        entry.repeats = 0;
        entry.written = now;
        return;
    }
    if (entry.repeats != 0) write(line(library, function, {}, {}, nullptr, now, entry.repeats), now);
    entry.key = std::move(key);
    entry.repeats = 0;
    entry.written = now;
    write(line(library, function, in, out, result, now, 0), now);
}

void Observer::NotImplemented(std::string_view function) {
    const auto now = std::chrono::steady_clock::now();
    const auto milliseconds = std::chrono::duration_cast<std::chrono::milliseconds>(now - started).count();
    std::lock_guard lock(mutex);
    write("{\"v\":1,\"t_ms\":" + std::to_string(milliseconds) + ",\"fn\":" + Fields::quote(function) + ",\"not_implemented\":true}", now);
}

void Observer::Flush() {
    const auto now = std::chrono::steady_clock::now();
    std::lock_guard lock(mutex);
    for (auto& [name, entry] : last) {
        if (entry.repeats == 0) continue;
        const auto slash = name.find('/');
        write(line(std::string_view(name).substr(0, slash), std::string_view(name).substr(slash + 1), {}, {}, nullptr, now, entry.repeats), now);
        entry.repeats = 0;
    }
}

}
