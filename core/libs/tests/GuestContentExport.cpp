#include "SceTypes.hpp"
#include <cstdint>
#include <cstdlib>
#include <set>
#include <stdexcept>

extern "C" int APS5_VABI sceContentExportAddToFavorites(void);
extern "C" int APS5_VABI sceContentExportDataProvideFunction(void);
extern "C" int APS5_VABI sceContentExportFree(void);
extern "C" int APS5_VABI sceContentExportFrom(void);
extern "C" int APS5_VABI sceContentExportFromFileForSf(void);
extern "C" int APS5_VABI sceContentExportFromFileWithContentIdList(void);
extern "C" int APS5_VABI sceContentExportFromFileWithTitleIdList(void);
extern "C" int APS5_VABI sceContentExportInit(void);
extern "C" int APS5_VABI sceContentExportMalloc(void);
extern "C" int APS5_VABI sceContentExportRemoveFromFavorites(void);
extern "C" int APS5_VABI sceContentExportRenameContent(void);
extern "C" int APS5_VABI sceContentExportValidateContents(void);

extern "C" int APS5_VABI sceContentExportInit2(const ContentExportInitParam2* init_param);
extern "C" int APS5_VABI sceContentExportTerm(void);
extern "C" int APS5_VABI sceContentExportStart(void);
extern "C" int APS5_VABI sceContentExportFinish(std::int32_t expId);
extern "C" int APS5_VABI sceContentExportGetProgress(std::int32_t expId);
extern "C" int APS5_VABI sceContentExportCancel(std::int32_t expId);
extern "C" int APS5_VABI sceContentExportFromDataWithThumbnail(std::int32_t expId, const ContentExportParam* param, const ContentExportCallbackParam* contentCallbackParam,
    const char* thumbnailType, const ContentExportCallbackParam* thumbnailCallbackParam, char* path, std::size_t pathBufferLength);

namespace {

void Require(bool value) { if (!value) std::abort(); }

template <typename TException = std::logic_error, typename TAction>
bool Throws(TAction action) {
    try {
        action();
    } catch (const TException&) {
        return true;
    }
    return false;
}

int allocator = 0;
char path[1024]{};

void Export(std::int32_t expId) {
    ContentExportParam param{};
    ContentExportCallbackParam content{};
    ContentExportCallbackParam thumbnail{};
    sceContentExportFromDataWithThumbnail(expId, &param, &content, "image/png", &thumbnail, path, sizeof(path));
}

}

int main() {
    ContentExportInitParam2 param{&allocator, &allocator, nullptr, 0x10000, 0, 0};
    Require(Throws([] { sceContentExportInit2(nullptr); }));
    Require(Throws([] { sceContentExportTerm(); }));
    Require(Throws([] { sceContentExportStart(); }));
    Require(Throws([] { sceContentExportFinish(1); }));
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
    Require(sceContentExportInit2(&param) == 0);

    std::set<int> sessions;
    for (int i = 0; i < 10; ++i) {
        int session = sceContentExportStart();
        Require(session > 0);
        Require(sessions.insert(session).second);
    }
    Require(Throws<std::runtime_error>([] { sceContentExportStart(); }));
    Require(Throws<std::runtime_error>([] { sceContentExportTerm(); }));
    int first = *sessions.begin();
    Require(Throws<std::runtime_error>([&] { sceContentExportGetProgress(first); }));
    Require(Throws<std::runtime_error>([&] { sceContentExportCancel(first); }));
    Require(Throws<std::runtime_error>([&] { Export(first); }));
    Require(path[0] == 0);
    Require(sceContentExportFinish(first) == 0);
    Require(Throws<std::invalid_argument>([&] { sceContentExportFinish(first); }));
    Require(Throws<std::invalid_argument>([&] { sceContentExportGetProgress(first); }));
    Require(Throws<std::invalid_argument>([&] { sceContentExportCancel(first); }));
    Require(Throws<std::invalid_argument>([&] { Export(first); }));
    Require(Throws<std::invalid_argument>([] { sceContentExportFinish(0); }));
    Require(Throws<std::invalid_argument>([] { sceContentExportFinish(-1); }));
    sessions.erase(first);
    int reopened = sceContentExportStart();
    Require(reopened > 0 && reopened != first);
    Require(sessions.insert(reopened).second);
    for (int session : sessions) Require(sceContentExportFinish(session) == 0);
    Require(sceContentExportTerm() == 0);
    Require(Throws([] { sceContentExportStart(); }));
    Require(Throws([&] { sceContentExportFinish(reopened); }));
    Require(Throws<std::runtime_error>([] { sceContentExportAddToFavorites(); }));
    Require(Throws<std::runtime_error>([] { sceContentExportDataProvideFunction(); }));
    Require(Throws<std::runtime_error>([] { sceContentExportFree(); }));
    Require(Throws<std::runtime_error>([] { sceContentExportFrom(); }));
    Require(Throws<std::runtime_error>([] { sceContentExportFromFileForSf(); }));
    Require(Throws<std::runtime_error>([] { sceContentExportFromFileWithContentIdList(); }));
    Require(Throws<std::runtime_error>([] { sceContentExportFromFileWithTitleIdList(); }));
    Require(Throws<std::runtime_error>([] { sceContentExportInit(); }));
    Require(Throws<std::runtime_error>([] { sceContentExportMalloc(); }));
    Require(Throws<std::runtime_error>([] { sceContentExportRemoveFromFavorites(); }));
    Require(Throws<std::runtime_error>([] { sceContentExportRenameContent(); }));
    Require(Throws<std::runtime_error>([] { sceContentExportValidateContents(); }));
}

