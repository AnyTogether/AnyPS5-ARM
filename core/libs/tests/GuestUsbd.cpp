#include "prx/libc/include/general/VabiMacros.hpp"

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>

namespace {

struct UsbdTimeval {
    std::int64_t seconds;
    std::int64_t microseconds;
};

}

extern "C" {
std::int32_t APS5_VABI sceUsbdInit();
void APS5_VABI sceUsbdExit();
std::int64_t APS5_VABI sceUsbdGetDeviceList(void*** list);
void APS5_VABI sceUsbdFreeDeviceList(void** list, std::int32_t unrefDevices);
std::int32_t APS5_VABI sceUsbdHandleEventsTimeout(const UsbdTimeval* timeout);
std::int32_t APS5_VABI sceUsbdOpen(void* device, void** deviceHandle);
void APS5_VABI sceUsbdClose(void* deviceHandle);
void* APS5_VABI sceUsbdRefDevice(void* device);
void APS5_VABI sceUsbdUnrefDevice(void* device);
std::uint8_t APS5_VABI sceUsbdGetBusNumber(void* device);
std::uint8_t APS5_VABI sceUsbdGetDeviceAddress(void* device);
std::int32_t APS5_VABI sceUsbdGetDeviceDescriptor(void* device, void* descriptor);
std::int32_t APS5_VABI sceUsbdGetConfigDescriptor(void* device, std::uint8_t configIndex, void** config);
std::int32_t APS5_VABI sceUsbdGetActiveConfigDescriptor(void* device, void** config);
std::int32_t APS5_VABI sceUsbdClaimInterface(void* deviceHandle, std::int32_t interfaceNumber);
std::int32_t APS5_VABI sceUsbdReleaseInterface(void* deviceHandle, std::int32_t interfaceNumber);
std::int32_t APS5_VABI sceUsbdSetConfiguration(void* deviceHandle, std::int32_t configuration);
std::int32_t APS5_VABI sceUsbdResetDevice(void* deviceHandle);
std::int32_t APS5_VABI sceUsbdCheckConnected(void* deviceHandle);
std::int32_t APS5_VABI sceUsbdKernelDriverActive(void* deviceHandle, std::int32_t interfaceNumber);
std::int32_t APS5_VABI sceUsbdAttachKernelDriver(void* deviceHandle, std::int32_t interfaceNumber);
std::int32_t APS5_VABI sceUsbdControlTransfer(void* deviceHandle, std::uint8_t requestType, std::uint8_t request, std::uint16_t value, std::uint16_t index, std::uint8_t* data, std::uint16_t length, std::uint32_t timeout);
std::int32_t APS5_VABI sceUsbdGetStringDescriptor(void* deviceHandle, std::uint8_t descriptorIndex, std::uint16_t languageId, std::uint8_t* data, std::int32_t length);
std::int32_t APS5_VABI sceUsbdSubmitTransfer(void* transfer);
void* APS5_VABI sceUsbdAllocTransfer(std::int32_t isoPackets);
void APS5_VABI sceUsbdFreeTransfer(void* transfer);
void APS5_VABI sceUsbdFillInterruptTransfer(void* transfer, void* deviceHandle, std::uint8_t endpoint, std::uint8_t* buffer, std::int32_t length, void* callback, void* userData, std::uint32_t timeout);
std::int32_t APS5_VABI sceUsbdCancelTransfer(void* transfer);
std::int32_t APS5_VABI sceUsbdEventHandlingOk();
void APS5_VABI sceUsbdFreeConfigDescriptor(void* config);
}

namespace {

constexpr std::int32_t invalidArgument = static_cast<std::int32_t>(0x80240002);

void Require(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "USBD: %s\n", message);
        std::abort();
    }
}

template<typename TCall>
bool Throws(TCall call) {
    try {
        call();
    } catch (const std::runtime_error&) {
        return true;
    }
    return false;
}

}

int main() {
    Require(sceUsbdInit() == 0, "initialization failed");
    void** list = nullptr;
    Require(sceUsbdGetDeviceList(&list) == 0, "a device was listed");
    Require(list != nullptr && list[0] == nullptr, "device list is not an empty null-terminated array");
    sceUsbdFreeDeviceList(list, 1);
    Require(sceUsbdGetDeviceList(nullptr) == invalidArgument, "null list accepted");
    Require(sceUsbdHandleEventsTimeout(nullptr) == invalidArgument, "null timeout accepted");
    const UsbdTimeval invalid{0, 1000000};
    Require(sceUsbdHandleEventsTimeout(&invalid) == invalidArgument, "out-of-range microseconds accepted");
    const UsbdTimeval timeout{0, 50000};
    const auto start = std::chrono::steady_clock::now();
    Require(sceUsbdHandleEventsTimeout(&timeout) == 0, "event handling failed");
    Require(std::chrono::steady_clock::now() - start >= std::chrono::milliseconds(45), "event handling returned before the timeout");
    int foreign = 0;
    void* handle = &foreign;
    Require(sceUsbdOpen(&foreign, nullptr) == invalidArgument, "null handle output accepted");
    Require(Throws([&] { sceUsbdOpen(nullptr, &handle); }), "opening a null device did not throw");
    Require(Throws([&] { sceUsbdOpen(&foreign, &handle); }), "opening a device that was never listed did not throw");
    sceUsbdClose(nullptr);
    Require(Throws([&] { sceUsbdClose(&foreign); }), "closing a handle that was never opened did not throw");
    Require(sceUsbdRefDevice(nullptr) == nullptr, "null device was referenced");
    sceUsbdUnrefDevice(nullptr);
    Require(Throws([&] { sceUsbdRefDevice(&foreign); }), "referencing a device that was never listed did not throw");
    Require(Throws([&] { sceUsbdUnrefDevice(&foreign); }), "unreferencing a device that was never listed did not throw");
    Require(sceUsbdGetBusNumber(nullptr) == 0 && sceUsbdGetDeviceAddress(nullptr) == 0, "null device reported a bus or address");
    Require(Throws([&] { sceUsbdGetBusNumber(&foreign); }), "bus number of a device that was never listed did not throw");
    std::uint8_t descriptor[18] = {};
    void* config = &foreign;
    Require(sceUsbdGetDeviceDescriptor(nullptr, descriptor) == invalidArgument, "null device descriptor accepted");
    Require(sceUsbdGetDeviceDescriptor(&foreign, nullptr) == invalidArgument, "null descriptor output accepted");
    Require(sceUsbdGetConfigDescriptor(nullptr, 0, &config) == invalidArgument, "null config device accepted");
    Require(sceUsbdGetConfigDescriptor(&foreign, 0, nullptr) == invalidArgument, "null config output accepted");
    Require(Throws([&] { sceUsbdGetConfigDescriptor(&foreign, 0, &config); }), "config of a device that was never listed did not throw");
    Require(Throws([&] { sceUsbdGetActiveConfigDescriptor(nullptr, &config); }), "active config of a null device did not throw");
    Require(sceUsbdClaimInterface(nullptr, 0) == invalidArgument && sceUsbdReleaseInterface(nullptr, 0) == invalidArgument, "null handle interface call accepted");
    Require(sceUsbdSetConfiguration(nullptr, 1) == invalidArgument && sceUsbdResetDevice(nullptr) == invalidArgument, "null handle configuration or reset accepted");
    Require(sceUsbdCheckConnected(nullptr) == invalidArgument, "null handle connection check accepted");
    Require(sceUsbdKernelDriverActive(nullptr, 0) == invalidArgument && sceUsbdAttachKernelDriver(nullptr, 0) == invalidArgument, "null handle kernel driver call accepted");
    Require(sceUsbdControlTransfer(nullptr, 0x80, 6, 0x100, 0, descriptor, 18, 1000) == invalidArgument, "null handle control transfer accepted");
    Require(sceUsbdControlTransfer(&foreign, 0x80, 6, 0x100, 0, nullptr, 18, 1000) == invalidArgument, "control transfer without data accepted");
    Require(Throws([&] { sceUsbdControlTransfer(&foreign, 0x80, 6, 0x100, 0, descriptor, 18, 1000); }), "control transfer on a handle that was never opened did not throw");
    Require(sceUsbdGetStringDescriptor(nullptr, 1, 0x409, descriptor, 18) == invalidArgument, "null handle string descriptor accepted");
    Require(sceUsbdGetStringDescriptor(&foreign, 1, 0x409, descriptor, 0) == invalidArgument, "empty string descriptor buffer accepted");
    Require(Throws([&] { sceUsbdClaimInterface(&foreign, 0); }), "claiming on a handle that was never opened did not throw");
    auto* transfer = static_cast<std::uint8_t*>(sceUsbdAllocTransfer(2));
    Require(transfer != nullptr, "transfer allocation failed");
    Require(*reinterpret_cast<std::int32_t*>(transfer + 56) == 2, "iso packet count not stored");
    Require(sceUsbdAllocTransfer(-1) == nullptr, "negative iso packet count accepted");
    std::uint8_t buffer[8] = {};
    int user = 0;
    sceUsbdFillInterruptTransfer(transfer, nullptr, 0x81, buffer, 8, reinterpret_cast<void*>(&Require), &user, 250);
    Require(transfer[9] == 0x81 && transfer[10] == 3, "endpoint or interrupt type not filled");
    Require(*reinterpret_cast<std::uint32_t*>(transfer + 12) == 250 && *reinterpret_cast<std::int32_t*>(transfer + 20) == 8, "timeout or length not filled");
    Require(*reinterpret_cast<void**>(transfer + 40) == &user && *reinterpret_cast<std::uint8_t**>(transfer + 48) == buffer, "user data or buffer not filled");
    Require(sceUsbdCancelTransfer(transfer) == static_cast<std::int32_t>(0x80240005), "cancelling an unsubmitted transfer did not report not found");
    Require(sceUsbdSubmitTransfer(nullptr) == invalidArgument, "null transfer submitted");
    Require(sceUsbdSubmitTransfer(transfer) == invalidArgument, "transfer without a handle submitted");
    sceUsbdFillInterruptTransfer(transfer, &foreign, 0x81, buffer, 8, reinterpret_cast<void*>(&Require), &user, 250);
    Require(Throws([&] { sceUsbdSubmitTransfer(transfer); }), "submitting on a handle that was never opened did not throw");
    sceUsbdFreeTransfer(transfer);
    sceUsbdFreeTransfer(nullptr);
    Require(sceUsbdEventHandlingOk() == 1, "event handling not allowed");
    sceUsbdFreeConfigDescriptor(nullptr);
    sceUsbdExit();
    std::puts("USBD tests passed");
    return 0;
}
