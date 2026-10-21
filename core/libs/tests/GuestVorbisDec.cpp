#include "SceTypes.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>

extern "C" {
int APS5_VABI sceVorbisDecOpenCallbacks(void);
int APS5_VABI sceVorbisDecClear(void);
int APS5_VABI sceVorbisDecBitrate(void);
int APS5_VABI sceVorbisDecBitrateInstant(void);
int APS5_VABI sceVorbisDecStreams(void);
int APS5_VABI sceVorbisDecSeekable(void);
int APS5_VABI sceVorbisDecSerialNumber(void);
int APS5_VABI sceVorbisDecRawTotal(void);
int APS5_VABI sceVorbisDecPcmTotal(void);
int APS5_VABI sceVorbisDecTimeTotal(void);
int APS5_VABI sceVorbisDecRawSeek(void);
int APS5_VABI sceVorbisDecPcmSeek(void);
int APS5_VABI sceVorbisDecPcmSeekPage(void);
int APS5_VABI sceVorbisDecTimeSeek(void);
int APS5_VABI sceVorbisDecTimeSeekPage(void);
int APS5_VABI sceVorbisDecRawSeekLap(void);
int APS5_VABI sceVorbisDecPcmSeekLap(void);
int APS5_VABI sceVorbisDecPcmSeekPageLap(void);
int APS5_VABI sceVorbisDecTimeSeekLap(void);
int APS5_VABI sceVorbisDecTimeSeekPageLap(void);
int APS5_VABI sceVorbisDecRawTell(void);
int APS5_VABI sceVorbisDecPcmTell(void);
int APS5_VABI sceVorbisDecTimeTell(void);
int APS5_VABI sceVorbisDecInfo(void);
int APS5_VABI sceVorbisDecComment(void);
int APS5_VABI sceVorbisDecRead(void);
int APS5_VABI sceVorbisDecReadFloat(void);
int APS5_VABI sceVorbisDecReadFilter(void);
int APS5_VABI sceVorbisDecCrossLap(void);
int APS5_VABI sceVorbisDecHalfrate(void);
int APS5_VABI sceVorbisDecHalfrateP(void);
int APS5_VABI sceVorbisDecGetDecodePriority(void);
int APS5_VABI sceVorbisDecSetDecodePriority(void);
int APS5_VABI sceVorbisDecGetLastDecodeError(void);
}

template <typename TCall>
static bool Throws(TCall call) {
    try {
        call();
    } catch (const std::runtime_error&) {
        return true;
    }
    return false;
}

static void Require(bool value, const char* what) {
    if (value) return;
    std::printf("VorbisDec test failed: %s\n", what);
    std::abort();
}

int main() {
    Require(Throws([] { sceVorbisDecOpenCallbacks(); }), "sceVorbisDecOpenCallbacks must throw");
    Require(Throws([] { sceVorbisDecClear(); }), "sceVorbisDecClear must throw");
    Require(Throws([] { sceVorbisDecBitrate(); }), "sceVorbisDecBitrate must throw");
    Require(Throws([] { sceVorbisDecBitrateInstant(); }), "sceVorbisDecBitrateInstant must throw");
    Require(Throws([] { sceVorbisDecStreams(); }), "sceVorbisDecStreams must throw");
    Require(Throws([] { sceVorbisDecSeekable(); }), "sceVorbisDecSeekable must throw");
    Require(Throws([] { sceVorbisDecSerialNumber(); }), "sceVorbisDecSerialNumber must throw");
    Require(Throws([] { sceVorbisDecRawTotal(); }), "sceVorbisDecRawTotal must throw");
    Require(Throws([] { sceVorbisDecPcmTotal(); }), "sceVorbisDecPcmTotal must throw");
    Require(Throws([] { sceVorbisDecTimeTotal(); }), "sceVorbisDecTimeTotal must throw");
    Require(Throws([] { sceVorbisDecRawSeek(); }), "sceVorbisDecRawSeek must throw");
    Require(Throws([] { sceVorbisDecPcmSeek(); }), "sceVorbisDecPcmSeek must throw");
    Require(Throws([] { sceVorbisDecPcmSeekPage(); }), "sceVorbisDecPcmSeekPage must throw");
    Require(Throws([] { sceVorbisDecTimeSeek(); }), "sceVorbisDecTimeSeek must throw");
    Require(Throws([] { sceVorbisDecTimeSeekPage(); }), "sceVorbisDecTimeSeekPage must throw");
    Require(Throws([] { sceVorbisDecRawSeekLap(); }), "sceVorbisDecRawSeekLap must throw");
    Require(Throws([] { sceVorbisDecPcmSeekLap(); }), "sceVorbisDecPcmSeekLap must throw");
    Require(Throws([] { sceVorbisDecPcmSeekPageLap(); }), "sceVorbisDecPcmSeekPageLap must throw");
    Require(Throws([] { sceVorbisDecTimeSeekLap(); }), "sceVorbisDecTimeSeekLap must throw");
    Require(Throws([] { sceVorbisDecTimeSeekPageLap(); }), "sceVorbisDecTimeSeekPageLap must throw");
    Require(Throws([] { sceVorbisDecRawTell(); }), "sceVorbisDecRawTell must throw");
    Require(Throws([] { sceVorbisDecPcmTell(); }), "sceVorbisDecPcmTell must throw");
    Require(Throws([] { sceVorbisDecTimeTell(); }), "sceVorbisDecTimeTell must throw");
    Require(Throws([] { sceVorbisDecInfo(); }), "sceVorbisDecInfo must throw");
    Require(Throws([] { sceVorbisDecComment(); }), "sceVorbisDecComment must throw");
    Require(Throws([] { sceVorbisDecRead(); }), "sceVorbisDecRead must throw");
    Require(Throws([] { sceVorbisDecReadFloat(); }), "sceVorbisDecReadFloat must throw");
    Require(Throws([] { sceVorbisDecReadFilter(); }), "sceVorbisDecReadFilter must throw");
    Require(Throws([] { sceVorbisDecCrossLap(); }), "sceVorbisDecCrossLap must throw");
    Require(Throws([] { sceVorbisDecHalfrate(); }), "sceVorbisDecHalfrate must throw");
    Require(Throws([] { sceVorbisDecHalfrateP(); }), "sceVorbisDecHalfrateP must throw");
    Require(Throws([] { sceVorbisDecGetDecodePriority(); }), "sceVorbisDecGetDecodePriority must throw");
    Require(Throws([] { sceVorbisDecSetDecodePriority(); }), "sceVorbisDecSetDecodePriority must throw");
    Require(Throws([] { sceVorbisDecGetLastDecodeError(); }), "sceVorbisDecGetLastDecodeError must throw");

    std::puts("All VorbisDec guest tests passed");
    return 0;
}
