#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"
#include <atomic>
#include <cstdio>

// Entry points this library does not implement: reported before the unimplemented-call exception so an
// APS5_TRACE_AJM run shows which one a title reached.
static void AjmStub(const char* name) {
    std::fprintf(stderr, "[ajm] unimplemented %s called\n", name);
    NotImplemented_nid_no_patch(name);
}

struct WVorbisHeaderPacketParameter {
    std::size_t size;
    std::int32_t channels;
    std::uint32_t sampleRate;
    std::int32_t bytesPerSecond;
    std::int32_t shortBlockExponent;
    std::int32_t longBlockExponent;
    std::uint32_t reserved;
    const void* setupPacket;
    std::size_t setupPacketSize;
    void* output;
    std::size_t outputCapacity;
    std::size_t outputSize;
};

struct WVorbisSetupPacketParameter {
    std::size_t size;
    std::int32_t channels;
    std::uint32_t reserved;
    const void* input;
    std::size_t inputSize;
    void* output;
    std::size_t outputCapacity;
    std::size_t outputSize;
};

static_assert(sizeof(WVorbisHeaderPacketParameter) == 72);
static_assert(offsetof(WVorbisHeaderPacketParameter, setupPacket) == 32);
static_assert(sizeof(WVorbisSetupPacketParameter) == 56);
static_assert(offsetof(WVorbisSetupPacketParameter, input) == 16);

extern "C" {

int APS5_VABI sceAjmBatchJobEncode(AjmBatchInfo* info, uint32_t instance, const void* pcm_input, size_t pcm_input_size, void* bitstream_output, size_t bitstream_output_size, void* result) {
 (void)info;
 (void)instance;
 (void)pcm_input;
 (void)pcm_input_size;
 (void)bitstream_output;
 (void)bitstream_output_size;
 (void)result;
 AjmStub(__func__);
 return 0;
}

const char* APS5_VABI sceAjmStrError(int error) {
 (void)error;
 AjmStub(__func__);
 return nullptr;
}

int APS5_VABI sceAjmDecWVorbisCreateHeaderPacket(WVorbisHeaderPacketParameter* parameter) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceAjmDecWVorbisCreateSetupPacket(WVorbisSetupPacketParameter* parameter) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceAjmBatchGetLog() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceAjmInstanceAvailable() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

uint32_t APS5_VABI sceAjmInstanceCodecType(uint32_t instance_id) {
    return instance_id >> 14;
}

int APS5_VABI sceAjmInstanceExtend(uint32_t context, uint32_t codec, uint64_t flags, uint32_t instance) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceAjmInstanceSwitch(uint32_t context, uint32_t codec, uint64_t flags, uint32_t instance) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}
