#include <cstdint>
#include <cstddef>
#include <cstring>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"
#include <algorithm>
#include <cstring>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

static constexpr int32_t GESTURE_HANDLE = 1;
static constexpr int SCE_SYSTEM_GESTURE_ERROR_INVALID_ARGUMENT = static_cast<int>(0x80D10002);
static constexpr int SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE = static_cast<int>(0x80D10003);
static constexpr int SCE_SYSTEM_GESTURE_ERROR_INDEX_OUT_OF_ARRAY = static_cast<int>(0x80D10005);

namespace {

constexpr std::uint64_t RECOGNIZER_STATE_MAGIC = 0x41505335'47455354ULL;

struct RecognizerState {
    std::uint64_t magic;
    std::int32_t gestureType;
    std::uint32_t hasRectangle;
    SystemGestureRectangle rectangle;
};

static_assert(sizeof(RecognizerState) <= sizeof(SystemGestureTouchRecognizer));

void storeRecognizerState(SystemGestureTouchRecognizer* recognizer, const RecognizerState& state) {
    std::memcpy(recognizer->reserve, &state, sizeof(state));
}

bool loadRecognizerState(const SystemGestureTouchRecognizer* recognizer, RecognizerState& state) {
    std::memcpy(&state, recognizer->reserve, sizeof(state));
    return state.magic == RECOGNIZER_STATE_MAGIC;
}

constexpr std::int32_t TOUCH_STATE_BEGIN = 1;
constexpr std::int32_t TOUCH_STATE_ACTIVE = 2;
constexpr std::int32_t TOUCH_STATE_END = 3;

struct TrackedTouch {
    std::uint16_t primitiveId;
    std::int32_t eventState;
    bool isUpdated;
    bool sampled;
    SystemGestureVector2 pressedPosition;
    SystemGestureVector2 currentPosition;
    SystemGestureVector2 deltaVector;
    std::uint64_t pressedTime;
    std::uint64_t updatedTime;
    std::uint64_t deltaTime;
};

std::mutex primitiveTouchMutex;
std::vector<TrackedTouch> primitiveTouches;

struct TouchSample {
    std::uint16_t primitiveId;
    SystemGestureVector2 position;
};

std::vector<TouchSample> reportSamples(const PadData& report) {
    std::vector<TouchSample> samples;
    const std::uint8_t count = report.touch_data_touch_num;
    if (count > 0)
        samples.push_back(TouchSample{report.touch_data_touch0_id,
            SystemGestureVector2{static_cast<float>(report.touch_data_touch0_x), static_cast<float>(report.touch_data_touch0_y)}});
    if (count > 1)
        samples.push_back(TouchSample{report.touch_data_touch1_id,
            SystemGestureVector2{static_cast<float>(report.touch_data_touch1_x), static_cast<float>(report.touch_data_touch1_y)}});
    return samples;
}

void sampleReport(const PadData& report) {
    std::erase_if(primitiveTouches, [](const TrackedTouch& touch) { return touch.eventState == TOUCH_STATE_END; });
    for (TrackedTouch& touch : primitiveTouches) {
        touch.sampled = false;
        touch.isUpdated = false;
    }
    const std::uint64_t time = report.timestamp;
    for (const TouchSample& sample : reportSamples(report)) {
        const auto tracked = std::find_if(primitiveTouches.begin(), primitiveTouches.end(),
            [&](const TrackedTouch& touch) { return touch.primitiveId == sample.primitiveId; });
        if (tracked == primitiveTouches.end()) {
            TrackedTouch touch{};
            touch.primitiveId = sample.primitiveId;
            touch.eventState = TOUCH_STATE_BEGIN;
            touch.isUpdated = true;
            touch.sampled = true;
            touch.pressedPosition = sample.position;
            touch.currentPosition = sample.position;
            touch.pressedTime = time;
            touch.updatedTime = time;
            primitiveTouches.push_back(touch);
            continue;
        }
        const SystemGestureVector2 previous = tracked->currentPosition;
        tracked->deltaVector = SystemGestureVector2{sample.position.x - previous.x, sample.position.y - previous.y};
        tracked->currentPosition = sample.position;
        tracked->deltaTime = time >= tracked->updatedTime ? time - tracked->updatedTime : 0;
        tracked->isUpdated = tracked->eventState != TOUCH_STATE_ACTIVE || tracked->deltaVector.x != 0.0f || tracked->deltaVector.y != 0.0f;
        tracked->eventState = TOUCH_STATE_ACTIVE;
        tracked->sampled = true;
        tracked->updatedTime = time;
    }
    for (TrackedTouch& touch : primitiveTouches) {
        if (touch.sampled) continue;
        touch.deltaVector = SystemGestureVector2{0.0f, 0.0f};
        touch.deltaTime = time >= touch.updatedTime ? time - touch.updatedTime : 0;
        touch.eventState = TOUCH_STATE_END;
        touch.isUpdated = true;
        touch.updatedTime = time;
    }
}

SystemGesturePrimitiveTouchEvent buildPrimitiveTouchEvent(const TrackedTouch& touch) {
    SystemGesturePrimitiveTouchEvent event{};
    event.event_state = touch.eventState;
    event.primitive_id = touch.primitiveId;
    event.is_updated = touch.isUpdated ? 1 : 0;
    event.pressed_position = touch.pressedPosition;
    event.current_position = touch.currentPosition;
    event.delta_vector = touch.deltaVector;
    event.delta_time = touch.deltaTime;
    event.elapsed_time = touch.updatedTime - touch.pressedTime;
    return event;
}

}

extern "C" {

int APS5_VABI sceSystemGestureAppendTouchRecognizer(int32_t gesture_handle, SystemGestureTouchRecognizer* recognizer) {
    if (gesture_handle != GESTURE_HANDLE) return SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
    if (!recognizer) return SCE_SYSTEM_GESTURE_ERROR_INVALID_ARGUMENT;
    return 0;
}

int APS5_VABI sceSystemGestureClose(int32_t gesture_handle) {
    return gesture_handle == GESTURE_HANDLE ? 0 : SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
}

int APS5_VABI sceSystemGestureCreateTouchRecognizer(int32_t gesture_handle, SystemGestureTouchRecognizer* recognizer, int32_t type, const SystemGestureRectangle* rectangle, const void* param) {
    (void)param;
    if (gesture_handle != GESTURE_HANDLE) return SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
    if (!recognizer) return SCE_SYSTEM_GESTURE_ERROR_INVALID_ARGUMENT;
    RecognizerState state{};
    state.magic = RECOGNIZER_STATE_MAGIC;
    state.gestureType = type;
    state.hasRectangle = rectangle ? 1 : 0;
    if (rectangle) state.rectangle = *rectangle;
    storeRecognizerState(recognizer, state);
    return 0;
}

int APS5_VABI sceSystemGestureFinalizePrimitiveTouchRecognizer(void) {
    std::lock_guard lock(primitiveTouchMutex);
    primitiveTouches.clear();
    return 0;
}

int APS5_VABI sceSystemGestureGetPrimitiveTouchEventByIndex(int32_t gesture_handle, uint32_t index, SystemGesturePrimitiveTouchEvent* event) {
    if (gesture_handle != GESTURE_HANDLE) return SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
    std::lock_guard lock(primitiveTouchMutex);
    if (index >= primitiveTouches.size()) return SCE_SYSTEM_GESTURE_ERROR_INDEX_OUT_OF_ARRAY;
    if (!event) return SCE_SYSTEM_GESTURE_ERROR_INVALID_ARGUMENT;
    *event = buildPrimitiveTouchEvent(primitiveTouches[index]);
    return 0;
}

// No touch primitive or event ever exists, so a lookup by ID finds nothing, as a lookup by index does.
int APS5_VABI sceSystemGestureGetPrimitiveTouchEventByPrimitiveID(int32_t gesture_handle, uint16_t primitiveId, SystemGesturePrimitiveTouchEvent* event) {
    if (gesture_handle != GESTURE_HANDLE) return SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
    if (!event) return SCE_SYSTEM_GESTURE_ERROR_INVALID_ARGUMENT;
    std::lock_guard lock(primitiveTouchMutex);
    const auto tracked = std::find_if(primitiveTouches.begin(), primitiveTouches.end(),
        [&](const TrackedTouch& touch) { return touch.primitiveId == primitiveId; });
    if (tracked == primitiveTouches.end())
        throw std::runtime_error(std::string(__func__) + ": no primitive touch event with id " + std::to_string(primitiveId));
    *event = buildPrimitiveTouchEvent(*tracked);
    return 0;
}

int APS5_VABI sceSystemGestureGetPrimitiveTouchEvents(int32_t gesture_handle, SystemGesturePrimitiveTouchEvent* event_buffer, uint32_t capacity_of_buffer, uint32_t* number_of_event) {
    if (gesture_handle != GESTURE_HANDLE) return SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
    if (!number_of_event) return SCE_SYSTEM_GESTURE_ERROR_INVALID_ARGUMENT;
    std::lock_guard lock(primitiveTouchMutex);
    const std::uint32_t reported = static_cast<std::uint32_t>(std::min<std::size_t>(primitiveTouches.size(), capacity_of_buffer));
    if (reported > 0 && !event_buffer) return SCE_SYSTEM_GESTURE_ERROR_INVALID_ARGUMENT;
    for (std::uint32_t i = 0; i < reported; ++i) event_buffer[i] = buildPrimitiveTouchEvent(primitiveTouches[i]);
    *number_of_event = reported;
    return 0;
}

int APS5_VABI sceSystemGestureGetPrimitiveTouchEventsCount(int32_t gesture_handle) {
    if (gesture_handle != GESTURE_HANDLE) return SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
    std::lock_guard lock(primitiveTouchMutex);
    return static_cast<int>(primitiveTouches.size());
}

int APS5_VABI sceSystemGestureGetTouchEventByEventID(int32_t gesture_handle, const SystemGestureTouchRecognizer* recognizer, uint32_t eventId, SystemGestureTouchEvent* event) {
    (void)eventId;
    (void)event;
    if (gesture_handle != GESTURE_HANDLE) return SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
    if (!recognizer) return SCE_SYSTEM_GESTURE_ERROR_INVALID_ARGUMENT;
    return SCE_SYSTEM_GESTURE_ERROR_INDEX_OUT_OF_ARRAY;
}

int APS5_VABI sceSystemGestureGetTouchEventByIndex(int32_t gesture_handle, const SystemGestureTouchRecognizer* recognizer, uint32_t index, SystemGestureTouchEvent* event) {
    (void)index;
    (void)event;
    if (gesture_handle != GESTURE_HANDLE) return SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
    if (!recognizer) return SCE_SYSTEM_GESTURE_ERROR_INVALID_ARGUMENT;
    return SCE_SYSTEM_GESTURE_ERROR_INDEX_OUT_OF_ARRAY;
}

int APS5_VABI sceSystemGestureGetTouchEvents(int32_t gesture_handle, const SystemGestureTouchRecognizer* recognizer, SystemGestureTouchEvent* event_buffer, uint32_t capacity_of_buffer, uint32_t* number_of_event) {
    (void)recognizer;
    (void)event_buffer;
    (void)capacity_of_buffer;
    if (gesture_handle != GESTURE_HANDLE) return SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
    if (!number_of_event) return SCE_SYSTEM_GESTURE_ERROR_INVALID_ARGUMENT;
    *number_of_event = 0;
    return 0;
}

int APS5_VABI sceSystemGestureGetTouchEventsCount(int32_t gesture_handle, const SystemGestureTouchRecognizer* recognizer) {
    (void)recognizer;
    return gesture_handle == GESTURE_HANDLE ? 0 : SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
}

int APS5_VABI sceSystemGestureGetTouchRecognizerInformation(int32_t gesture_handle, const SystemGestureTouchRecognizer* recognizer, SystemGestureTouchRecognizerInformation* information) {
    if (gesture_handle != GESTURE_HANDLE) return SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
    if (!recognizer || !information) return SCE_SYSTEM_GESTURE_ERROR_INVALID_ARGUMENT;
    RecognizerState state{};
    if (!loadRecognizerState(recognizer, state))
        throw std::runtime_error(std::string(__func__) + ": recognizer was not created by sceSystemGestureCreateTouchRecognizer");
    if (!state.hasRectangle)
        throw std::runtime_error(std::string(__func__) + ": recognizer was created without a rectangle");
    information->gesture_type = state.gestureType;
    information->rectangle = state.rectangle;
    information->updated_time = 0;
    return 0;
}

int APS5_VABI sceSystemGestureInitializePrimitiveTouchRecognizer(const void* param) {
    (void)param;
    std::lock_guard lock(primitiveTouchMutex);
    primitiveTouches.clear();
    return 0;
}

int32_t APS5_VABI sceSystemGestureOpen(int32_t input_type, const void* param) {
    (void)input_type;
    (void)param;
    return GESTURE_HANDLE;
}

int APS5_VABI sceSystemGestureRemoveTouchRecognizer(int32_t gesture_handle, SystemGestureTouchRecognizer* recognizer) {
    if (gesture_handle != GESTURE_HANDLE) return SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
    if (!recognizer) return SCE_SYSTEM_GESTURE_ERROR_INVALID_ARGUMENT;
    return 0;
}

int APS5_VABI sceSystemGestureResetPrimitiveTouchRecognizer(int32_t gesture_handle) {
    if (gesture_handle != GESTURE_HANDLE) return SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
    std::lock_guard lock(primitiveTouchMutex);
    primitiveTouches.clear();
    return 0;
}

int APS5_VABI sceSystemGestureResetTouchRecognizer(int32_t gesture_handle, SystemGestureTouchRecognizer* recognizer) {
    if (gesture_handle != GESTURE_HANDLE) return SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
    if (!recognizer) return SCE_SYSTEM_GESTURE_ERROR_INVALID_ARGUMENT;
    return 0;
}

int APS5_VABI sceSystemGestureUpdateAllTouchRecognizer(int32_t gesture_handle) {
    if (gesture_handle != GESTURE_HANDLE) return SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
    return 0;
}

int APS5_VABI sceSystemGestureUpdatePrimitiveTouchRecognizer(int32_t gesture_handle, const void* param) {
    if (gesture_handle != GESTURE_HANDLE) return SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
    if (!param) return 0;
    const auto* input = static_cast<const SystemGestureTouchPadData*>(param);
    if (!input->pad_data_buffer || input->report_number <= 0) return 0;
    std::lock_guard lock(primitiveTouchMutex);
    for (std::int32_t i = 0; i < input->report_number; ++i) sampleReport(input->pad_data_buffer[i]);
    return 0;
}

int APS5_VABI sceSystemGestureUpdateTouchRecognizer(int32_t gesture_handle, SystemGestureTouchRecognizer* recognizer) {
    if (gesture_handle != GESTURE_HANDLE) return SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
    if (!recognizer) return SCE_SYSTEM_GESTURE_ERROR_INVALID_ARGUMENT;
    return 0;
}

int APS5_VABI sceSystemGestureUpdateTouchRecognizerRectangle(int32_t gesture_handle, SystemGestureTouchRecognizer* recognizer, const SystemGestureRectangle* rectangle) {
    if (gesture_handle != GESTURE_HANDLE) return SCE_SYSTEM_GESTURE_ERROR_INVALID_HANDLE;
    if (!recognizer) return SCE_SYSTEM_GESTURE_ERROR_INVALID_ARGUMENT;
    if (!rectangle) return SCE_SYSTEM_GESTURE_ERROR_INVALID_ARGUMENT;
    RecognizerState state{};
    if (loadRecognizerState(recognizer, state)) {
        state.hasRectangle = 1;
        state.rectangle = *rectangle;
        storeRecognizerState(recognizer, state);
    }
    return 0;
}

int APS5_VABI sceSystemGestureDebugGetVersion() {
    return 0x6a00;
}

}
