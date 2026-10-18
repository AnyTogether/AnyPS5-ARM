#include "SceTypes.hpp"
#include <cstdint>
#include <cstdlib>
#include <stdexcept>

extern "C" {
int APS5_VABI sceContentSearchInit(const ContentSearchInitParam* init_param);
int APS5_VABI sceContentSearchTerm(void);
int APS5_VABI sceContentSearchGetContentLastUpdateId(std::int64_t* lastUpdateId);
int APS5_VABI sceContentSearchGetNumOfContent(const ContentSearchContentColumnSet* columnSet, std::uint32_t columnSetLength, std::int64_t* numOfContent, std::int64_t* lastUpdateId);
int APS5_VABI sceContentSearchGetTotalContentSize(const ContentSearchContentColumnSet* columnSet, std::uint32_t columnSetLength, std::int64_t* size, std::int64_t* lastUpdateId);
int APS5_VABI sceContentSearchSearchContent(const ContentSearchContentColumnSet* columnSet, std::uint32_t columnSetLength, const ContentSearchContentOrderByCondition* orderByConditions, std::uint32_t orderByConditionsLength, std::uint32_t offset, std::uint32_t limit, std::int64_t* numOfContent, void* infos, std::int64_t* lastUpdateId);
int APS5_VABI sceContentSearchOpenMetadata(const char* filePath, std::int32_t* metadataId);
int APS5_VABI sceContentSearchOpenMetadataByContentId(std::int64_t contentId, std::int32_t* metadataId);
int APS5_VABI sceContentSearchCloseMetadata(std::int32_t metadataId);
int APS5_VABI sceContentSearchGetMetadataFieldInfo(std::int32_t metadataId, const char* field, std::int32_t* metadataType, std::int32_t* size);
int APS5_VABI sceContentSearchGetMetadataValue(std::int32_t metadataId, const char* field, void* value);
}

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

constexpr int ErrorNotInitialized = static_cast<int>(0x809D1001u);
constexpr int ErrorLimitTooBig = static_cast<int>(0x809D100Au);

struct MetadataValue {
    std::int32_t size;
    std::int32_t type;
    std::int64_t value;
};

}

int main() {
    ContentSearchInitParam param{3 * 1024 * 1024};
    ContentSearchColumnValue photo{8, 1};
    ContentSearchContentColumn column{3, 0, &photo, 2};
    ContentSearchContentColumnSet columnSet{&column, 1, 2};
    ContentSearchContentOrderByCondition orderBy{4, 0};
    unsigned char infos[0x960 * 2] = {};
    std::int64_t count = -1;
    std::int64_t size = -1;
    std::int64_t updateId = -1;
    std::int32_t metadataId = -1;
    std::int32_t metadataType = -1;
    std::int32_t fieldSize = -1;
    MetadataValue value{-1, -1, -1};

    Require(sceContentSearchGetContentLastUpdateId(&updateId) == ErrorNotInitialized);
    Require(sceContentSearchGetNumOfContent(&columnSet, 1, &count, &updateId) == ErrorNotInitialized);
    Require(sceContentSearchGetTotalContentSize(&columnSet, 1, &size, &updateId) == ErrorNotInitialized);
    Require(sceContentSearchSearchContent(&columnSet, 1, &orderBy, 1, 0, 2, &count, infos, &updateId) == ErrorNotInitialized);
    Require(sceContentSearchOpenMetadata("/data/photo.jpg", &metadataId) == ErrorNotInitialized);
    Require(sceContentSearchOpenMetadataByContentId(1, &metadataId) == ErrorNotInitialized);
    Require(sceContentSearchCloseMetadata(1) == ErrorNotInitialized);
    Require(count == -1 && size == -1 && updateId == -1 && metadataId == -1);

    Require(sceContentSearchInit(&param) == 0);

    Require(sceContentSearchGetContentLastUpdateId(&updateId) == 0);
    Require(updateId == 0);
    updateId = -1;
    Require(sceContentSearchGetNumOfContent(&columnSet, 1, &count, &updateId) == 0);
    Require(count == 0 && updateId == 0);
    count = -1;
    updateId = -1;
    Require(sceContentSearchGetNumOfContent(nullptr, 0, &count, &updateId) == 0);
    Require(count == 0 && updateId == 0);
    updateId = -1;
    Require(sceContentSearchGetTotalContentSize(&columnSet, 1, &size, &updateId) == 0);
    Require(size == 0 && updateId == 0);
    count = -1;
    updateId = -1;
    Require(sceContentSearchSearchContent(&columnSet, 1, &orderBy, 1, 0, 92, &count, infos, &updateId) == 0);
    Require(count == 0 && updateId == 0);
    count = -1;
    updateId = -1;
    Require(sceContentSearchSearchContent(&columnSet, 1, &orderBy, 1, 0, 93, &count, infos, &updateId) == ErrorLimitTooBig);
    Require(count == -1 && updateId == -1);

    Require(Throws([&] { sceContentSearchGetContentLastUpdateId(nullptr); }));
    Require(Throws([&] { sceContentSearchGetNumOfContent(&columnSet, 1, nullptr, &updateId); }));
    Require(Throws([&] { sceContentSearchGetNumOfContent(&columnSet, 1, &count, nullptr); }));
    Require(Throws([&] { sceContentSearchGetTotalContentSize(nullptr, 1, &size, &updateId); }));
    Require(Throws([&] { sceContentSearchSearchContent(&columnSet, 1, &orderBy, 1, 0, 2, &count, nullptr, &updateId); }));
    ContentSearchContentColumn unknownColumn{8, 0, &photo, 2};
    ContentSearchContentColumnSet unknownColumnSet{&unknownColumn, 1, 2};
    Require(Throws([&] { sceContentSearchGetNumOfContent(&unknownColumnSet, 1, &count, &updateId); }));
    ContentSearchContentColumn missingValue{3, 0, nullptr, 2};
    ContentSearchContentColumnSet missingValueSet{&missingValue, 1, 2};
    Require(Throws([&] { sceContentSearchGetTotalContentSize(&missingValueSet, 1, &size, &updateId); }));
    ContentSearchContentColumn unknownOperator{3, 6, &photo, 2};
    ContentSearchContentColumnSet unknownOperatorSet{&unknownOperator, 1, 2};
    Require(Throws([&] { sceContentSearchSearchContent(&unknownOperatorSet, 1, &orderBy, 1, 0, 2, &count, infos, &updateId); }));
    ContentSearchContentOrderByCondition unknownSort{3, 0};
    Require(Throws([&] { sceContentSearchSearchContent(&columnSet, 1, &unknownSort, 1, 0, 2, &count, infos, &updateId); }));
    Require(count == -1 && updateId == -1);

    Require(Throws([&] { sceContentSearchOpenMetadata("/data/photo.jpg", &metadataId); }));
    Require(Throws([&] { sceContentSearchOpenMetadataByContentId(1, &metadataId); }));
    Require(metadataId == -1);
    Require(Throws([] { sceContentSearchCloseMetadata(1); }));
    Require(Throws([&] { sceContentSearchGetMetadataFieldInfo(1, "title", &metadataType, &fieldSize); }));
    Require(Throws([&] { sceContentSearchGetMetadataValue(1, "title", &value); }));
    Require(metadataType == -1 && fieldSize == -1 && value.size == -1);

    Require(sceContentSearchTerm() == 0);
    Require(sceContentSearchGetContentLastUpdateId(&updateId) == ErrorNotInitialized);
    Require(updateId == -1);
}
