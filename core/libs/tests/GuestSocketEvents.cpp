#include "SceTypes.hpp"
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#include <thread>

extern "C" {
int APS5_VABI socket_nid_postfix(int, int, int);
int APS5_VABI bind_nid_postfix(int, const void*, std::uint32_t);
int APS5_VABI listen_nid_postfix(int, int);
int APS5_VABI getsockname_nid_postfix(int, void*, std::uint32_t*);
int APS5_VABI connect_nid_postfix(int, const void*, std::uint32_t);
int APS5_VABI accept_nid_postfix(int, void*, std::uint32_t*);
std::int64_t APS5_VABI send_nid_postfix(int, const void*, std::uint64_t, int);
std::int64_t APS5_VABI recv_nid_postfix(int, void*, std::uint64_t, int);
int APS5_VABI close_nid_postfix(int);
int APS5_VABI sceKernelCreateEqueue(KernelEqueue* eq, const char* name);
int APS5_VABI sceKernelDeleteEqueue(KernelEqueue eq);
int APS5_VABI sceKernelWaitEqueue(KernelEqueue eq, KernelEvent* ev, int num, int* out, const KernelUseconds* timo);
int APS5_VABI sceKernelAddReadEvent(KernelEqueue eq, int fd, std::size_t size, void* udata);
int APS5_VABI sceKernelDeleteReadEvent(KernelEqueue eq, int fd);
int APS5_VABI sceKernelAddWriteEvent(KernelEqueue eq, int fd, std::size_t size, void* udata);
int APS5_VABI sceKernelDeleteWriteEvent(KernelEqueue eq, int fd);
int APS5_VABI sceKernelOpen(const char*, int, std::uint16_t);
int APS5_VABI sceKernelClose(int);
std::int64_t APS5_VABI sceKernelWrite(int, const void*, std::size_t);
std::int64_t APS5_VABI sceKernelLseek(int, std::int64_t, int);
}

static constexpr int SCE_OK = 0;
static constexpr int SCE_KERNEL_ERROR_ENOENT = static_cast<int>(0x80020002);
static constexpr int SCE_KERNEL_ERROR_EBADF = static_cast<int>(0x80020009);
static constexpr int SCE_KERNEL_ERROR_ETIMEDOUT = static_cast<int>(0x8002003c);
static constexpr int EVFILT_READ = -1;
static constexpr int EVFILT_WRITE = -2;
static constexpr std::uint16_t EV_EOF = 0x8000;

static void Require(bool value) { if (!value) std::abort(); }

int main() {
    const int listener = socket_nid_postfix(2, 1, 6);
    Require(listener >= 0);
    std::array<std::uint8_t, 16> address{16, 2, 0, 0, 127, 0, 0, 1};
    Require(bind_nid_postfix(listener, address.data(), address.size()) == 0);
    Require(listen_nid_postfix(listener, 4) == 0);
    std::uint32_t addressSize = address.size();
    Require(getsockname_nid_postfix(listener, address.data(), &addressSize) == 0);

    KernelEqueue eq = 0;
    Require(sceKernelCreateEqueue(&eq, "sockets") == SCE_OK);
    const KernelUseconds shortTimeout = 20000;
    const KernelUseconds timeout = 1000000;
    int marker = 0;
    int count = 0;
    std::array<KernelEvent, 4> events{};

    Require(sceKernelAddReadEvent(eq, listener, 1, &marker) == SCE_OK);
    Require(sceKernelWaitEqueue(eq, events.data(), events.size(), &count, &shortTimeout) == SCE_KERNEL_ERROR_ETIMEDOUT);
    Require(count == 0);

    const int client = socket_nid_postfix(2, 1, 0);
    Require(client >= 0);
    Require(connect_nid_postfix(client, address.data(), address.size()) == 0);
    Require(sceKernelWaitEqueue(eq, events.data(), events.size(), &count, &timeout) == SCE_OK);
    Require(count == 1);
    Require(events[0].ident == static_cast<std::uintptr_t>(listener));
    Require(events[0].filter == EVFILT_READ);
    Require(events[0].udata == &marker);
    const int accepted = accept_nid_postfix(listener, nullptr, nullptr);
    Require(accepted >= 0);
    Require(sceKernelDeleteReadEvent(eq, listener) == SCE_OK);
    Require(sceKernelDeleteReadEvent(eq, listener) == SCE_KERNEL_ERROR_ENOENT);

    Require(sceKernelAddWriteEvent(eq, client, 0, nullptr) == SCE_OK);
    Require(sceKernelWaitEqueue(eq, events.data(), events.size(), &count, &timeout) == SCE_OK);
    Require(count == 1 && events[0].filter == EVFILT_WRITE && events[0].data > 0);
    Require(sceKernelDeleteWriteEvent(eq, client) == SCE_OK);

    Require(sceKernelAddReadEvent(eq, accepted, 1, nullptr) == SCE_OK);
    const char message[] = "ready";
    Require(send_nid_postfix(client, message, sizeof(message), 0) == sizeof(message));
    Require(sceKernelWaitEqueue(eq, events.data(), events.size(), &count, &timeout) == SCE_OK);
    Require(count == 1 && events[0].ident == static_cast<std::uintptr_t>(accepted));
    Require(events[0].data == sizeof(message) && (events[0].flags & EV_EOF) == 0);
    char received[sizeof(message)]{};
    Require(recv_nid_postfix(accepted, received, sizeof(received), 0) == sizeof(received));
    Require(sceKernelWaitEqueue(eq, events.data(), events.size(), &count, &shortTimeout) == SCE_KERNEL_ERROR_ETIMEDOUT);

    Require(close_nid_postfix(client) == 0);
    Require(sceKernelWaitEqueue(eq, events.data(), events.size(), &count, &timeout) == SCE_OK);
    Require(count == 1 && events[0].data == 0 && (events[0].flags & EV_EOF) != 0);

    KernelEqueue blocking = 0;
    Require(sceKernelCreateEqueue(&blocking, "blocking") == SCE_OK);
    const int writer = socket_nid_postfix(2, 1, 0);
    Require(writer >= 0 && connect_nid_postfix(writer, address.data(), address.size()) == 0);
    const int reader = accept_nid_postfix(listener, nullptr, nullptr);
    Require(reader >= 0);
    Require(sceKernelAddReadEvent(blocking, reader, 1, nullptr) == SCE_OK);
    std::thread sender([&] {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        Require(send_nid_postfix(writer, message, sizeof(message), 0) == sizeof(message));
    });
    const auto start = std::chrono::steady_clock::now();
    Require(sceKernelWaitEqueue(blocking, events.data(), events.size(), &count, nullptr) == SCE_OK);
    sender.join();
    Require(std::chrono::steady_clock::now() - start >= std::chrono::milliseconds(40));
    Require(count == 1 && events[0].ident == static_cast<std::uintptr_t>(reader) && events[0].data == sizeof(message));
    Require(recv_nid_postfix(reader, received, sizeof(received), 0) == sizeof(received));

    std::thread waiter([&] {
        std::array<KernelEvent, 4> woken{};
        int wokenCount = 0;
        Require(sceKernelWaitEqueue(blocking, woken.data(), woken.size(), &wokenCount, nullptr) == SCE_OK);
        Require(wokenCount == 1 && woken[0].filter == EVFILT_WRITE && woken[0].ident == static_cast<std::uintptr_t>(writer));
    });
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    Require(sceKernelAddWriteEvent(blocking, writer, 0, nullptr) == SCE_OK);
    waiter.join();
    Require(sceKernelDeleteWriteEvent(blocking, writer) == SCE_OK);

    Require(close_nid_postfix(reader) == 0);
    Require(sceKernelDeleteReadEvent(blocking, reader) == SCE_KERNEL_ERROR_ENOENT);
    Require(close_nid_postfix(writer) == 0);
    Require(sceKernelDeleteEqueue(blocking) == SCE_OK);

    Require(sceKernelAddReadEvent(eq, client, 1, nullptr) == SCE_KERNEL_ERROR_EBADF);
    Require(sceKernelAddReadEvent(eq, 12345, 1, nullptr) == SCE_KERNEL_ERROR_EBADF);
    Require(sceKernelDeleteReadEvent(eq, accepted) == SCE_OK);

    KernelEqueue watermark = 0;
    Require(sceKernelCreateEqueue(&watermark, "watermark") == SCE_OK);
    const int lowWriter = socket_nid_postfix(2, 1, 0);
    Require(lowWriter >= 0 && connect_nid_postfix(lowWriter, address.data(), address.size()) == 0);
    const int lowReader = accept_nid_postfix(listener, nullptr, nullptr);
    Require(lowReader >= 0);
    Require(sceKernelAddReadEvent(watermark, lowReader, 8, nullptr) == SCE_OK);
    Require(send_nid_postfix(lowWriter, "abcd", 4, 0) == 4);
    Require(sceKernelWaitEqueue(watermark, events.data(), events.size(), &count, &shortTimeout) == SCE_KERNEL_ERROR_ETIMEDOUT);
    std::thread rest([&] {
        std::this_thread::sleep_for(std::chrono::milliseconds(30));
        Require(send_nid_postfix(lowWriter, "efgh", 4, 0) == 4);
    });
    Require(sceKernelWaitEqueue(watermark, events.data(), events.size(), &count, &timeout) == SCE_OK);
    rest.join();
    Require(count == 1 && events[0].ident == static_cast<std::uintptr_t>(lowReader) && events[0].data == 8);
    Require(close_nid_postfix(lowWriter) == 0);
    Require(close_nid_postfix(lowReader) == 0);
    Require(sceKernelDeleteEqueue(watermark) == SCE_OK);

    KernelEqueue files = 0;
    Require(sceKernelCreateEqueue(&files, "files") == SCE_OK);
    const int file = sceKernelOpen("socket_events_probe.bin", 0x202, 0644);
    Require(file >= 0);
    Require(sceKernelWrite(file, "0123456789", 10) == 10);
    Require(sceKernelLseek(file, 3, 0) == 3);
    Require(sceKernelAddReadEvent(files, file, 1, &marker) == SCE_OK);
    Require(sceKernelWaitEqueue(files, events.data(), events.size(), &count, &timeout) == SCE_OK);
    Require(count == 1 && events[0].filter == EVFILT_READ && events[0].data == 7 && events[0].udata == &marker);
    Require(sceKernelLseek(file, 0, 2) == 10);
    Require(sceKernelWaitEqueue(files, events.data(), events.size(), &count, &shortTimeout) == SCE_KERNEL_ERROR_ETIMEDOUT);
    Require(sceKernelAddWriteEvent(files, file, 0, nullptr) == SCE_OK);
    Require(sceKernelWaitEqueue(files, events.data(), events.size(), &count, &timeout) == SCE_OK);
    Require(count == 1 && events[0].filter == EVFILT_WRITE && events[0].data == 0);
    Require(sceKernelDeleteReadEvent(files, file) == SCE_OK);
    Require(sceKernelDeleteWriteEvent(files, file) == SCE_OK);
    Require(sceKernelClose(file) == 0);
    Require(sceKernelDeleteEqueue(files) == SCE_OK);
    std::remove("socket_events_probe.bin");

    Require(close_nid_postfix(accepted) == 0);
    Require(close_nid_postfix(listener) == 0);
    Require(sceKernelDeleteEqueue(eq) == SCE_OK);
}
