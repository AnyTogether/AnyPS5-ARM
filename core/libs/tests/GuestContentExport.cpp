#include "SceTypes.hpp"
#include <cstdlib>
#include <stdexcept>

extern "C" int APS5_VABI sceContentExportInit2(const ContentExportInitParam2* init_param);
extern "C" int APS5_VABI sceContentExportTerm(void);
extern "C" int APS5_VABI sceContentExportStart(void);
extern "C" int APS5_VABI sceContentExportFinish(int exp_id);

namespace {

void Require(bool value) { if (!value) std::abort(); }

template <typename TAction>
bool Throws(TAction action) {
    try {
        action();
    } catch (const std::logic_error&) {
        return true;
    }
    return false;
}

int allocator = 0;

}

int main() {
    ContentExportInitParam2 param{&allocator, &allocator, nullptr, 0x10000, 0, 0};
    Require(Throws([] { sceContentExportInit2(nullptr); }));
    Require(Throws([] { sceContentExportTerm(); }));
    ContentExportInitParam2 missing = param;
    missing.free_func = nullptr;
    Require(Throws([&] { sceContentExportInit2(&missing); }));
    ContentExportInitParam2 reserved = param;
    reserved.reserved1 = 1;
    Require(Throws([&] { sceContentExportInit2(&reserved); }));
    Require(sceContentExportInit2(&param) == 0);
    Require(Throws([&] { sceContentExportInit2(&param); }));
    Require(sceContentExportTerm() == 0);
    Require(Throws([] { sceContentExportTerm(); }));
    Require(Throws([] { sceContentExportStart(); }));
    Require(sceContentExportInit2(&param) == 0);
    int sessions[10];
    for (int& session : sessions) {
        session = sceContentExportStart();
        Require(session > 0);
    }
    Require(sessions[0] != sessions[1]);
    Require(Throws([] { sceContentExportStart(); }));
    Require(sceContentExportFinish(sessions[3]) == 0);
    Require(Throws([&] { sceContentExportFinish(sessions[3]); }));
    Require(sceContentExportStart() > 0);
    Require(sceContentExportTerm() == 0);
    Require(Throws([&] { sceContentExportFinish(sessions[0]); }));
    Require(sceContentExportInit2(&param) == 0);
    Require(Throws([&] { sceContentExportFinish(sessions[0]); }));
    Require(sceContentExportTerm() == 0);
}
