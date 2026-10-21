#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

extern "C" {

uint32_t APS5_VABI sceRazorCpuIsCapturing(void) {
 return 0;
}

int APS5_VABI sceRazorCpuJobManagerDispatch(const void* args) {
 (void)args;
 return 0;
}

int APS5_VABI sceRazorCpuJobManagerJob(const void* args) {
 (void)args;
 return 0;
}

int APS5_VABI sceRazorCpuJobManagerSequence(const void* args) {
 (void)args;
 return 0;
}

int APS5_VABI sceRazorCpuPushMarker(const char* label, uint32_t color, uint32_t flags) {
 (void)label;
 (void)color;
 (void)flags;
 return 0;
}

int APS5_VABI sceRazorCpuNamedSync(const char* label) {
 (void)label;
 return 0;
}

int APS5_VABI sceRazorCpuPushMarkerStatic(const char* name, uint32_t color, uint32_t flags) {
 (void)name;
 (void)color;
 (void)flags;
 return 0;
}

int APS5_VABI sceRazorCpuPopMarker(void) {
 return 0;
}

int APS5_VABI sceRazorCpuFlushOccurred(uint64_t* timeSpentInFlush) {
 if (timeSpentInFlush != nullptr) *timeSpentInFlush = 0;
 return 0;
}

int APS5_VABI sceRazorCpuPlotValue(const char* series, float value) {
 (void)series;
 (void)value;
 return 0;
}

int APS5_VABI sceRazorCpuWriteBookmark(const char* label, const char* description) {
 (void)label;
 (void)description;
 return 0;
}

int APS5_VABI sceRazorCpuSync(void) {
 return 0;
}

void APS5_VABI sceRazorCpuDisableFiberUserMarkers(void) {
}

int APS5_VABI sceRazorCpuInitDataTags(void* buffer, size_t size) {
 (void)buffer;
 (void)size;
 return 0;
}

int APS5_VABI sceRazorCpuShutdownDataTags(void) {
 return 0;
}

size_t APS5_VABI sceRazorCpuGetDataTagStorageSize(uint32_t tagCount) {
 (void)tagCount;
 NotImplemented_nid_no_patch(__func__);
}

int APS5_VABI sceRazorCpuTagArray(const char* label, uint32_t category, void* array, size_t bufferSize, size_t elementSize) {
 (void)label;
 (void)category;
 (void)array;
 (void)bufferSize;
 (void)elementSize;
 return 0;
}

int APS5_VABI sceRazorCpuTagBuffer(const char* label, uint32_t category, void* buffer, size_t bufferSize) {
 (void)label;
 (void)category;
 (void)buffer;
 (void)bufferSize;
 return 0;
}

int APS5_VABI sceRazorCpuResizeTaggedBuffer(uint32_t category, void* buffer, size_t newBufferSize) {
 (void)category;
 (void)buffer;
 (void)newBufferSize;
 return 0;
}

int APS5_VABI sceRazorCpuUnTagBuffer(uint32_t category, void* buffer) {
 (void)category;
 (void)buffer;
 return 0;
}

int APS5_VABI sceRazorCpuBeginLogicalFileAccess(const char* filename, uint64_t tag, uint64_t size, uint8_t operation) {
 (void)filename;
 (void)tag;
 (void)size;
 (void)operation;
 return 0;
}

int APS5_VABI sceRazorCpuEndLogicalFileAccess(void) {
 return 0;
}

}
