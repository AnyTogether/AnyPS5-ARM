#ifndef CORE_LIBS_PRX_LIBSCENETCTL_ONLINEOBSERVER_HPP
#define CORE_LIBS_PRX_LIBSCENETCTL_ONLINEOBSERVER_HPP

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <functional>
#include <map>
#include <mutex>
#include <string>
#include <string_view>

namespace Online {

class Observer {
public:
    using Forward = std::function<void(std::string_view line)>;

    explicit Observer(std::string path, std::chrono::milliseconds repeatEvery = std::chrono::seconds(5));
    ~Observer();
    Observer(const Observer&) = delete;
    Observer& operator=(const Observer&) = delete;

    void SetForward(Forward forward);
    void Record(std::string_view library, std::string_view function, std::string_view in, std::string_view out, const std::int64_t* result);
    void Record(std::string_view library, std::string_view function, std::string_view in, std::string_view out, const std::int64_t* result,
        std::chrono::steady_clock::time_point now);
    void NotImplemented(std::string_view function);
    void Flush();

private:
    struct Last {
        std::string key;
        std::string line;
        std::uint64_t repeats = 0;
        std::chrono::steady_clock::time_point written;
    };

    void write(std::string line, std::chrono::steady_clock::time_point now);
    std::string line(std::string_view library, std::string_view function, std::string_view in, std::string_view out, const std::int64_t* result,
        std::chrono::steady_clock::time_point now, std::uint64_t repeats) const;
    void open();

    const std::string path;
    const std::chrono::milliseconds repeatEvery;
    const std::chrono::steady_clock::time_point started;
    std::mutex mutex;
    std::FILE* file = nullptr;
    bool failed = false;
    Forward forward;
    std::map<std::string, Last, std::less<>> last;
};

}

#endif
