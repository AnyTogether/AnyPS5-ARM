#include "SceTypes.hpp"
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <initializer_list>
#include <stdexcept>

struct NpWebApi2MemoryPoolStats {
    std::size_t pool_size;
    std::size_t max_inuse_size;
    std::size_t current_inuse_size;
    std::int32_t reserved;
};

extern "C" {
int APS5_VABI sceNpWebApi2Initialize(int, std::size_t);
int APS5_VABI sceNpWebApi2InitializeForPresence(int, std::uint64_t);
int APS5_VABI sceNpWebApi2IntInitialize(const NpWebApi2IntInitializeArgs*);
int APS5_VABI sceNpWebApi2IntInitialize2(const NpWebApi2IntInitialize2Args*);
int APS5_VABI sceNpWebApi2Terminate(int);
int APS5_VABI sceNpWebApi2GetMemoryPoolStats(int, NpWebApi2MemoryPoolStats*);
int APS5_VABI sceNpWebApi2PushEventCreateHandle(int);
int APS5_VABI sceNpWebApi2PushEventAbortHandle(int, int);
int APS5_VABI sceNpWebApi2PushEventSetHandleTimeout(int, int, std::uint32_t);
int APS5_VABI sceNpWebApi2CreateUserContext(int, int);
int APS5_VABI sceNpWebApi2CreateRequest(int, const char*, const char*, const char*, const void*, std::int64_t*);
int APS5_VABI sceNpWebApi2SetRequestTimeout(std::int64_t, std::uint32_t);
int APS5_VABI sceNpWebApi2AddWebTraceTag(std::int64_t, const char*);
int APS5_VABI sceNpWebApi2DeleteRequest(std::int64_t);
}

static void Require(bool value) { if (!value) std::abort(); }

template <typename TCall>
static bool Throws(TCall call) {
    try {
        call();
    } catch (const std::exception&) {
        return true;
    }
    return false;
}

int main() {
    const int context = sceNpWebApi2Initialize(1, 0x20000);
    const int other = sceNpWebApi2Initialize(1, 0x8000);
    Require(context > 0 && other > 0 && context != other);
    NpWebApi2MemoryPoolStats stats{1, 1, 1, 1};
    Require(sceNpWebApi2GetMemoryPoolStats(context, &stats) == 0);
    Require(stats.pool_size == 0x20000 && stats.max_inuse_size == 0 && stats.current_inuse_size == 0 && stats.reserved == 0);
    Require(sceNpWebApi2GetMemoryPoolStats(other, &stats) == 0 && stats.pool_size == 0x8000);
    Require(Throws([&] { sceNpWebApi2GetMemoryPoolStats(context, nullptr); }));
    const int handle = sceNpWebApi2PushEventCreateHandle(context);
    Require(handle > 0);
    Require(sceNpWebApi2PushEventAbortHandle(context, handle) == 0);
    Require(sceNpWebApi2PushEventAbortHandle(context, handle + 1000) == 0);
    Require(sceNpWebApi2PushEventSetHandleTimeout(context, handle, 30000) == 0);
    const int user = sceNpWebApi2CreateUserContext(context, 1);
    std::int64_t request = 0;
    Require(user > 0 && sceNpWebApi2CreateRequest(user, "sessionManager", "/v1/sessions", "GET", nullptr, &request) == 0);
    Require(sceNpWebApi2SetRequestTimeout(request, 30000000) == 0);
    Require(sceNpWebApi2AddWebTraceTag(request, "trace-tag-1") == 0);
    Require(sceNpWebApi2AddWebTraceTag(request, nullptr) == static_cast<int>(0x80553402));
    Require(sceNpWebApi2DeleteRequest(request) == 0);
    Require(sceNpWebApi2Terminate(context) == 0);
    Require(Throws([&] { sceNpWebApi2GetMemoryPoolStats(context, &stats); }));
    Require(Throws([&] { sceNpWebApi2PushEventAbortHandle(context, handle); }));
    Require(Throws([&] { sceNpWebApi2PushEventSetHandleTimeout(context, handle, 30000); }));
    Require(sceNpWebApi2Terminate(other) == 0);

    constexpr int invalidArgument = static_cast<int>(0x80553402);
    NpWebApi2IntInitializeArgs args{1, 0, 0x4000, "anyps5", sizeof(NpWebApi2IntInitializeArgs)};
    const int internal = sceNpWebApi2IntInitialize(&args);
    Require(internal > 0 && sceNpWebApi2GetMemoryPoolStats(internal, &stats) == 0 && stats.pool_size == 0x4000);
    args.struct_size = sizeof(NpWebApi2IntInitializeArgs) - 8;
    Require(sceNpWebApi2IntInitialize(&args) == invalidArgument && sceNpWebApi2IntInitialize(nullptr) == invalidArgument);
    NpWebApi2IntInitialize2Args args2{1, 0, 0x6000, nullptr, 1, 0, sizeof(NpWebApi2IntInitialize2Args)};
    const int internal2 = sceNpWebApi2IntInitialize2(&args2);
    Require(internal2 > 0 && internal2 != internal && sceNpWebApi2GetMemoryPoolStats(internal2, &stats) == 0 && stats.pool_size == 0x6000);
    args2.struct_size = sizeof(NpWebApi2IntInitializeArgs);
    Require(sceNpWebApi2IntInitialize2(&args2) == invalidArgument && sceNpWebApi2IntInitialize2(nullptr) == invalidArgument);
    const int presence = sceNpWebApi2InitializeForPresence(1, 0x2000);
    Require(presence > 0 && sceNpWebApi2GetMemoryPoolStats(presence, &stats) == 0 && stats.pool_size == 0x2000);
    for (const int created : {internal, internal2, presence}) {
        Require(sceNpWebApi2Terminate(created) == 0);
        Require(Throws([&] { sceNpWebApi2GetMemoryPoolStats(created, &stats); }));
    }
    return 0;
}
