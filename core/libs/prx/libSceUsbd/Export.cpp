#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <stdexcept>
#include <string>
#include <thread>

namespace {

constexpr std::int32_t SCE_USBD_ERROR_INVALID_ARG = static_cast<std::int32_t>(0x80240002);
constexpr std::int32_t SCE_USBD_ERROR_NOT_FOUND = static_cast<std::int32_t>(0x80240005);
constexpr std::uint8_t TRANSFER_TYPE_INTERRUPT = 3;

struct UsbdIsoPacketDescriptor {
    std::uint32_t length;
    std::uint32_t actualLength;
    std::int32_t status;
};

struct UsbdTransfer;
using UsbdTransferCallback = void (APS5_VABI*)(UsbdTransfer* transfer);

struct UsbdTransfer {
    void* deviceHandle;
    std::uint8_t flags;
    std::uint8_t endpoint;
    std::uint8_t type;
    std::uint32_t timeout;
    std::int32_t status;
    std::int32_t length;
    std::int32_t actualLength;
    UsbdTransferCallback callback;
    void* userData;
    std::uint8_t* buffer;
    std::int32_t numIsoPackets;
};

// The isochronous packet descriptors follow numIsoPackets without padding.
constexpr std::size_t ISO_PACKET_DESC_OFFSET = offsetof(UsbdTransfer, numIsoPackets) + sizeof(std::int32_t);

// The device list is always empty, so no device, device handle or configuration descriptor can
// have reached the caller.
[[noreturn]] void RejectForeign(const char* function, const char* object) {
    throw std::invalid_argument(std::string(function) + ": " + object + " was not obtained from this library (no USB device is attached)");
}

struct UsbdTimeval {
    std::int64_t seconds;
    std::int64_t microseconds;
};

void* g_emptyDeviceList[1] = {nullptr};

std::string AbsentDevice(const char* function) {
    return std::string(function) + ": the device list is always empty, so the device was not returned by sceUsbdGetDeviceList";
}

std::string UnopenedHandle(const char* function) {
    return std::string(function) + ": no device can be opened, so the handle was not returned by sceUsbdOpen";
}

}

extern "C" {

std::int32_t APS5_VABI sceUsbdInit() {
    return 0;
}

void APS5_VABI sceUsbdExit() {
}

std::int64_t APS5_VABI sceUsbdGetDeviceList(void*** list) {
    if (list == nullptr) return SCE_USBD_ERROR_INVALID_ARG;
    *list = g_emptyDeviceList;
    return 0;
}

void APS5_VABI sceUsbdFreeDeviceList(void** list, std::int32_t unrefDevices) {
    (void)unrefDevices;
    if (list != nullptr && list != g_emptyDeviceList) throw std::runtime_error(std::string(__func__) + ": list was not returned by sceUsbdGetDeviceList");
}

std::int32_t APS5_VABI sceUsbdHandleEventsTimeout(const UsbdTimeval* timeout) {
    if (timeout == nullptr || timeout->seconds < 0 || timeout->microseconds < 0 || timeout->microseconds >= 1000000) return SCE_USBD_ERROR_INVALID_ARG;
    std::this_thread::sleep_for(std::chrono::seconds(timeout->seconds) + std::chrono::microseconds(timeout->microseconds));
    return 0;
}

UsbdTransfer* APS5_VABI sceUsbdAllocTransfer(std::int32_t isoPackets) {
    if (isoPackets < 0) return nullptr;
    const std::size_t size = ISO_PACKET_DESC_OFFSET + static_cast<std::size_t>(isoPackets) * sizeof(UsbdIsoPacketDescriptor);
    auto* transfer = static_cast<UsbdTransfer*>(std::calloc(1, std::max(size, sizeof(UsbdTransfer))));
    if (transfer == nullptr) return nullptr;
    transfer->numIsoPackets = isoPackets;
    return transfer;
}

// The buffer belongs to the guest allocator, so a FREE_BUFFER flag is not honoured here.
void APS5_VABI sceUsbdFreeTransfer(UsbdTransfer* transfer) {
    std::free(transfer);
}

void APS5_VABI sceUsbdFillInterruptTransfer(UsbdTransfer* transfer, void* deviceHandle, std::uint8_t endpoint, std::uint8_t* buffer,
    std::int32_t length, UsbdTransferCallback callback, void* userData, std::uint32_t timeout) {
    if (transfer == nullptr) throw std::invalid_argument(std::string(__func__) + ": null transfer");
    transfer->deviceHandle = deviceHandle;
    transfer->endpoint = endpoint;
    transfer->type = TRANSFER_TYPE_INTERRUPT;
    transfer->timeout = timeout;
    transfer->buffer = buffer;
    transfer->length = length;
    transfer->callback = callback;
    transfer->userData = userData;
}

// Submission always fails, so no transfer is ever in flight.
std::int32_t APS5_VABI sceUsbdCancelTransfer(UsbdTransfer* transfer) {
    if (transfer == nullptr) return SCE_USBD_ERROR_INVALID_ARG;
    return SCE_USBD_ERROR_NOT_FOUND;
}

std::int32_t APS5_VABI sceUsbdEventHandlingOk() {
    return 1;
}

void APS5_VABI sceUsbdFreeConfigDescriptor(void* config) {
    if (config != nullptr) RejectForeign(__func__, "configuration descriptor");
}

std::int32_t APS5_VABI sceUsbdAttachKernelDriver(void* deviceHandle, std::int32_t interfaceNumber) {
    (void)interfaceNumber;
    if (deviceHandle == nullptr) return SCE_USBD_ERROR_INVALID_ARG;
    throw std::runtime_error(UnopenedHandle(__func__));
}

std::int32_t APS5_VABI sceUsbdCheckConnected(void* deviceHandle) {
    if (deviceHandle == nullptr) return SCE_USBD_ERROR_INVALID_ARG;
    throw std::runtime_error(UnopenedHandle(__func__));
}

std::int32_t APS5_VABI sceUsbdClaimInterface(void* deviceHandle, std::int32_t interfaceNumber) {
    (void)interfaceNumber;
    if (deviceHandle == nullptr) return SCE_USBD_ERROR_INVALID_ARG;
    throw std::runtime_error(UnopenedHandle(__func__));
}

void APS5_VABI sceUsbdClose(void* deviceHandle) {
    if (deviceHandle != nullptr) throw std::runtime_error(UnopenedHandle(__func__));
}

std::int32_t APS5_VABI sceUsbdControlTransfer(void* deviceHandle, std::uint8_t requestType, std::uint8_t request, std::uint16_t value, std::uint16_t index, std::uint8_t* data, std::uint16_t length, std::uint32_t timeout) {
    (void)requestType;
    (void)request;
    (void)value;
    (void)index;
    (void)timeout;
    if (deviceHandle == nullptr || (length != 0 && data == nullptr)) return SCE_USBD_ERROR_INVALID_ARG;
    throw std::runtime_error(UnopenedHandle(__func__));
}

std::int32_t APS5_VABI sceUsbdGetActiveConfigDescriptor(void* device, void** config) {
    (void)config;
    if (device == nullptr) throw std::runtime_error(std::string(__func__) + ": null device");
    throw std::runtime_error(AbsentDevice(__func__));
}

std::uint8_t APS5_VABI sceUsbdGetBusNumber(void* device) {
    if (device == nullptr) return 0;
    throw std::runtime_error(AbsentDevice(__func__));
}

std::int32_t APS5_VABI sceUsbdGetConfigDescriptor(void* device, std::uint8_t configIndex, void** config) {
    (void)configIndex;
    if (device == nullptr || config == nullptr) return SCE_USBD_ERROR_INVALID_ARG;
    throw std::runtime_error(AbsentDevice(__func__));
}

std::uint8_t APS5_VABI sceUsbdGetDeviceAddress(void* device) {
    if (device == nullptr) return 0;
    throw std::runtime_error(AbsentDevice(__func__));
}

std::int32_t APS5_VABI sceUsbdGetDeviceDescriptor(void* device, void* descriptor) {
    if (device == nullptr || descriptor == nullptr) return SCE_USBD_ERROR_INVALID_ARG;
    throw std::runtime_error(AbsentDevice(__func__));
}

std::int32_t APS5_VABI sceUsbdGetStringDescriptor(void* deviceHandle, std::uint8_t descriptorIndex, std::uint16_t languageId, std::uint8_t* data, std::int32_t length) {
    (void)descriptorIndex;
    (void)languageId;
    if (deviceHandle == nullptr || data == nullptr || length < 1) return SCE_USBD_ERROR_INVALID_ARG;
    throw std::runtime_error(UnopenedHandle(__func__));
}

std::int32_t APS5_VABI sceUsbdKernelDriverActive(void* deviceHandle, std::int32_t interfaceNumber) {
    (void)interfaceNumber;
    if (deviceHandle == nullptr) return SCE_USBD_ERROR_INVALID_ARG;
    throw std::runtime_error(UnopenedHandle(__func__));
}

std::int32_t APS5_VABI sceUsbdOpen(void* device, void** deviceHandle) {
    if (device == nullptr) throw std::runtime_error(std::string(__func__) + ": null device");
    if (deviceHandle == nullptr) return SCE_USBD_ERROR_INVALID_ARG;
    throw std::runtime_error(AbsentDevice(__func__));
}

void* APS5_VABI sceUsbdRefDevice(void* device) {
    if (device == nullptr) return nullptr;
    throw std::runtime_error(AbsentDevice(__func__));
}

std::int32_t APS5_VABI sceUsbdReleaseInterface(void* deviceHandle, std::int32_t interfaceNumber) {
    (void)interfaceNumber;
    if (deviceHandle == nullptr) return SCE_USBD_ERROR_INVALID_ARG;
    throw std::runtime_error(UnopenedHandle(__func__));
}

std::int32_t APS5_VABI sceUsbdResetDevice(void* deviceHandle) {
    if (deviceHandle == nullptr) return SCE_USBD_ERROR_INVALID_ARG;
    throw std::runtime_error(UnopenedHandle(__func__));
}

std::int32_t APS5_VABI sceUsbdSetConfiguration(void* deviceHandle, std::int32_t configuration) {
    (void)configuration;
    if (deviceHandle == nullptr) return SCE_USBD_ERROR_INVALID_ARG;
    throw std::runtime_error(UnopenedHandle(__func__));
}

std::int32_t APS5_VABI sceUsbdSubmitTransfer(UsbdTransfer* transfer) {
    if (transfer == nullptr || transfer->deviceHandle == nullptr) return SCE_USBD_ERROR_INVALID_ARG;
    throw std::runtime_error(UnopenedHandle(__func__));
}

void APS5_VABI sceUsbdUnrefDevice(void* device) {
    if (device != nullptr) throw std::runtime_error(AbsentDevice(__func__));
}

}
