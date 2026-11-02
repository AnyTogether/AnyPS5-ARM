#ifndef CORE_LIBS_PRX_LIBSCEAGCDRIVER_EXECUTION_INCLUDE_WORKERSAMPLER_HPP
#define CORE_LIBS_PRX_LIBSCEAGCDRIVER_EXECUTION_INCLUDE_WORKERSAMPLER_HPP

#include <cstdint>

namespace AgcDriver {

void StartWorkerSampler(std::uint32_t queue = 0);
void StartCommitterSampler();
void StopWorkerSampler();
// macOS: also samples the calling thread under APS5_SAMPLE_WORKER (the draw committer names itself).
void SampleCurrentThread(const char* name);
bool ReadableStackRegion(std::uint64_t address, std::uint64_t& low, std::uint64_t& high);

}

#endif
