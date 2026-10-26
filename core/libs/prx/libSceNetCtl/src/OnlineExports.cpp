#include "prx/libSceNetCtl/include/Online.hpp"
#include "prx/libSceNetCtl/include/OnlineEnvironment.hpp"
#include "prx/libSceNetCtl/include/OnlineObserver.hpp"
#include "prx/libSceAgcDriver/TraceRevision.hpp"
#include "prx/libc/include/General.hpp"
#include <atomic>
#include <memory>
#include <mutex>
#include <unistd.h>

namespace {

struct Services {
    std::unique_ptr<Online::Observer> observer;
    std::unique_ptr<Online::Bridge> bridge;
};

Services& services() {
    static Services* created = [] {
        auto* made = new Services;
        if (const auto path = Online::ObservationPath()) {
            made->observer = std::make_unique<Online::Observer>(*path);
            Online::Fields start;
            start.Uint("pid", static_cast<std::uint64_t>(::getpid())).Text("build", APS5_TRACE_COMMIT);
            made->observer->Record("", "start", start.Json(), {}, nullptr);
        }
        if (const auto endpoint = Online::BridgeEndpoint()) {
            Online::BridgeOptions options;
            options.build = APS5_TRACE_COMMIT;
            made->bridge = std::make_unique<Online::Bridge>(endpoint->port, endpoint->secret, options);
            if (made->observer) {
                auto* bridge = made->bridge.get();
                made->observer->SetForward([bridge](std::string_view line) { bridge->Observe(line); });
            }
        }
        return made;
    }();
    return *created;
}

void observeNotImplemented(const char* function) {
    if (auto* observer = services().observer.get()) observer->NotImplemented(function ? function : "");
}

[[maybe_unused]] const bool hooked = [] {
    if (!Online::ObservationPath()) return false;
    SetNotImplementedObserver_nid_no_patch(observeNotImplemented);
    return true;
}();

}

extern "C" bool OnlineEnabled_nid_no_patch() {
    return services().bridge != nullptr;
}

extern "C" bool OnlineAccount_nid_no_patch(Online::AccountState& out) {
    auto* bridge = services().bridge.get();
    if (!bridge) return false;
    out = bridge->Account();
    return true;
}

extern "C" bool OnlineWeb_nid_no_patch(const Online::Wire::WebRequest& request, std::uint32_t timeoutMilliseconds, Online::Wire::WebReply& reply) {
    auto* bridge = services().bridge.get();
    if (!bridge) return false;
    auto answer = bridge->Web(request, std::chrono::milliseconds(timeoutMilliseconds));
    if (!answer || answer->status == 0) return false;
    reply = std::move(*answer);
    return true;
}

extern "C" bool OnlineObserving_nid_no_patch() {
    return services().observer != nullptr;
}

extern "C" void OnlineObserve_nid_no_patch(const char* library, const char* function, const std::string& in, const std::string& out, const std::int64_t* result) {
    if (auto* observer = services().observer.get()) observer->Record(library ? library : "", function ? function : "", in, out, result);
}

extern "C" bool OnlineSendDatagram_nid_no_patch(const Online::Wire::Datagram& datagram) {
    auto* bridge = services().bridge.get();
    return bridge && bridge->SendDatagram(datagram);
}

extern "C" void OnlineSetDatagramReceiver_nid_no_patch(void (*receiver)(const Online::Wire::Datagram& datagram)) {
    auto* bridge = services().bridge.get();
    if (!bridge) return;
    if (receiver) {
        bridge->SetDatagramReceiver([receiver](const Online::Wire::Datagram& datagram) { receiver(datagram); });
    } else {
        bridge->SetDatagramReceiver({});
    }
}

extern "C" bool OnlineSendStream_nid_no_patch(const Online::Wire::Stream& stream) {
    auto* bridge = services().bridge.get();
    return bridge && bridge->SendStream(stream);
}

extern "C" void OnlineSetStreamReceiver_nid_no_patch(void (*receiver)(const Online::Wire::Stream& stream)) {
    auto* bridge = services().bridge.get();
    if (!bridge) return;
    if (receiver) {
        bridge->SetStreamReceiver([receiver](const Online::Wire::Stream& stream) { receiver(stream); });
    } else {
        bridge->SetStreamReceiver({});
    }
}

namespace {
std::atomic<void (*)()> pushDispatcher{nullptr};
}

extern "C" void OnlineSetPushReceiver_nid_no_patch(void (*receiver)(const Online::Wire::PushEvent& event)) {
    auto* bridge = services().bridge.get();
    if (!bridge) return;
    if (receiver) {
        bridge->SetPushReceiver([receiver](const Online::Wire::PushEvent& event) { receiver(event); });
    } else {
        bridge->SetPushReceiver({});
    }
}

extern "C" void OnlineSetPushDispatcher_nid_no_patch(void (*dispatcher)()) {
    pushDispatcher.store(dispatcher, std::memory_order_release);
}

extern "C" void OnlineDispatchPush_nid_no_patch() {
    if (auto* dispatcher = pushDispatcher.load(std::memory_order_acquire)) dispatcher();
}
