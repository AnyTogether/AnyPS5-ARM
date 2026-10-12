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

// The console's own message strings are not known; this names the code instead and never returns null,
// as titles pass the result straight to a %s format.
const char* APS5_VABI sceAjmStrError(int error) {
    switch (static_cast<std::uint32_t>(error)) {
    case 0: return "SCE_OK";
    case 0x80930001u: return "SCE_AJM_ERROR_UNKNOWN";
    case 0x80930002u: return "SCE_AJM_ERROR_INVALID_CONTEXT";
    case 0x80930003u: return "SCE_AJM_ERROR_INVALID_INSTANCE";
    case 0x80930004u: return "SCE_AJM_ERROR_INVALID_BATCH";
    case 0x80930005u: return "SCE_AJM_ERROR_INVALID_PARAMETER";
    case 0x80930006u: return "SCE_AJM_ERROR_OUT_OF_MEMORY";
    case 0x80930007u: return "SCE_AJM_ERROR_OUT_OF_RESOURCES";
    case 0x80930008u: return "SCE_AJM_ERROR_CODEC_NOT_SUPPORTED";
    case 0x80930009u: return "SCE_AJM_ERROR_CODEC_ALREADY_REGISTERED";
    case 0x8093000Au: return "SCE_AJM_ERROR_CODEC_NOT_REGISTERED";
    case 0x8093000Bu: return "SCE_AJM_ERROR_WRONG_REVISION_FLAG";
    case 0x8093000Cu: return "SCE_AJM_ERROR_FLAG_NOT_SUPPORTED";
    case 0x8093000Du: return "SCE_AJM_ERROR_BUSY";
    case 0x8093000Eu: return "SCE_AJM_ERROR_BAD_PRIORITY";
    case 0x8093000Fu: return "SCE_AJM_ERROR_IN_PROGRESS";
    case 0x80930010u: return "SCE_AJM_ERROR_RETRY";
    case 0x80930011u: return "SCE_AJM_ERROR_MALFORMED_BATCH";
    case 0x80930012u: return "SCE_AJM_ERROR_JOB_CREATION";
    case 0x80930013u: return "SCE_AJM_ERROR_INVALID_OPCODE";
    case 0x80930014u: return "SCE_AJM_ERROR_PRIORITY_VIOLATION";
    case 0x80930015u: return "SCE_AJM_ERROR_BUFFER_TOO_BIG";
    case 0x80930016u: return "SCE_AJM_ERROR_INVALID_ADDRESS";
    case 0x80930017u: return "SCE_AJM_ERROR_CANCELLED";
    default: return "SCE_AJM_ERROR (unknown code)";
    }
}

int APS5_VABI sceAjmDecWVorbisCreateHeaderPacket(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceAjmDecWVorbisCreateSetupPacket(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}
