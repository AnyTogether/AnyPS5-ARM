#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

struct Value { void* node; };
struct String { void* text; };
struct Array { void* items; };
struct Object { void* items; };
struct Iterator { void* position; };
struct Pair {
    String key;
    std::uint64_t reserved;
    Value value;
};
using NullAccessCallback = const Value& (APS5_VABI*)(std::int32_t, const Value*, void*);
using SetNullAccessCallback = int (APS5_VABI*)(void*, NullAccessCallback, void*);

extern "C" {
int APS5_VABI _ZN3sce4Json11InitializerC1Ev(void*);
int APS5_VABI _ZN3sce4Json11InitializerD1Ev(void*);
int APS5_VABI _ZN3sce4Json11Initializer10initializeEPKNS0_13InitParameterE(void*, const void*);
int APS5_VABI _ZN3sce4Json11Initializer9terminateEv(void*);
int APS5_VABI _ZN3sce4Json11Initializer27setGlobalNullAccessCallBackEPFRKNS0_5ValueENS0_9ValueTypeEPS3_PvES7_(void*, NullAccessCallback, void*);
int APS5_VABI _ZN3sce4Json11Initializer27setGlobalNullAccessCallbackEPFRKNS0_5ValueENS0_9ValueTypeEPS3_PvES7_(void*, NullAccessCallback, void*);
void APS5_VABI _ZN3sce4Json6StringC1Ev(String*);
void APS5_VABI _ZN3sce4Json6StringC1EPKc(String*, const char*);
void APS5_VABI _ZN3sce4Json6StringD1Ev(String*);
const char* APS5_VABI _ZNK3sce4Json6String5c_strEv(const String*);
std::size_t APS5_VABI _ZNK3sce4Json6String6lengthEv(const String*);
void APS5_VABI _ZN3sce4Json5ArrayC1Ev(Array*);
void APS5_VABI _ZN3sce4Json5ArrayC1ERKS1_(Array*, const Array*);
void APS5_VABI _ZN3sce4Json5Array5clearEv(Array*);
const Value* APS5_VABI _ZNK3sce4Json5Array5frontEv(const Array*);
Value* APS5_VABI _ZNK3sce4Json5Array8iteratorptEv(const Iterator*);
void APS5_VABI _ZN3sce4Json5ArrayD1Ev(Array*);
void APS5_VABI _ZN3sce4Json5Array9push_backERKNS0_5ValueE(Array*, const Value*);
Iterator* APS5_VABI _ZNK3sce4Json5Array5beginEv(Iterator*, const Array*);
Iterator* APS5_VABI _ZNK3sce4Json5Array3endEv(Iterator*, const Array*);
std::size_t APS5_VABI _ZNK3sce4Json5Array4sizeEv(const Array*);
const Value* APS5_VABI _ZNK3sce4Json5Array4backEv(const Array*);
void APS5_VABI _ZN3sce4Json5Array8iteratorD1Ev(Iterator*);
Iterator* APS5_VABI _ZN3sce4Json5Array8iteratorppEv(Iterator*);
Value* APS5_VABI _ZNK3sce4Json5Array8iteratordeEv(const Iterator*);
bool APS5_VABI _ZNK3sce4Json5Array8iteratorneERKS2_(const Iterator*, const Iterator*);
void APS5_VABI _ZN3sce4Json6ObjectC1Ev(Object*);
void APS5_VABI _ZN3sce4Json6ObjectD1Ev(Object*);
Value* APS5_VABI _ZN3sce4Json6ObjectixERKNS0_6StringE(Object*, const String*);
Iterator* APS5_VABI _ZNK3sce4Json6Object5beginEv(Iterator*, const Object*);
Iterator* APS5_VABI _ZNK3sce4Json6Object3endEv(Iterator*, const Object*);
void APS5_VABI _ZN3sce4Json6Object8iteratorD1Ev(Iterator*);
Iterator* APS5_VABI _ZN3sce4Json6Object8iteratorppEv(Iterator*);
Pair* APS5_VABI _ZNK3sce4Json6Object8iteratordeEv(const Iterator*);
Pair* APS5_VABI _ZNK3sce4Json6Object8iteratorptEv(const Iterator*);
Iterator* APS5_VABI _ZNK3sce4Json6Object4findERKNS0_6StringE(Iterator*, const Object*, const String*);
int APS5_VABI _ZNK3sce4Json6String7compareEPKc(const String*, const char*);
bool APS5_VABI _ZNK3sce4Json6Object8iteratorneERKS2_(const Iterator*, const Iterator*);
void APS5_VABI _ZN3sce4Json5ValueC1Ev(Value*);
void APS5_VABI _ZN3sce4Json5ValueC1Eb(Value*, bool);
void APS5_VABI _ZN3sce4Json5ValueC1Ed(Value*, double);
void APS5_VABI _ZN3sce4Json5ValueC1ERKNS0_6ObjectE(Value*, const Object*);
void APS5_VABI _ZN3sce4Json5ValueD1Ev(Value*);
void APS5_VABI _ZN3sce4Json5Value5clearEv(Value*);
int APS5_VABI _ZN3sce4Json5Value3setEl(Value*, std::int64_t);
int APS5_VABI _ZN3sce4Json5Value3setEPKc(Value*, const char*);
std::int32_t APS5_VABI _ZNK3sce4Json5Value7getTypeEv(const Value*);
const bool* APS5_VABI _ZNK3sce4Json5Value10getBooleanEv(const Value*);
const std::int64_t* APS5_VABI _ZNK3sce4Json5Value10getIntegerEv(const Value*);
const std::uint64_t* APS5_VABI _ZNK3sce4Json5Value11getUIntegerEv(const Value*);
const double* APS5_VABI _ZNK3sce4Json5Value7getRealEv(const Value*);
const String* APS5_VABI _ZNK3sce4Json5Value9getStringEv(const Value*);
const Array* APS5_VABI _ZNK3sce4Json5Value8getArrayEv(const Value*);
std::size_t APS5_VABI _ZNK3sce4Json5Value5countEv(const Value*);
const Value* APS5_VABI _ZNK3sce4Json5ValueixEPKc(const Value*, const char*);
Value* APS5_VABI _ZN3sce4Json5Value10referValueERKNS0_6StringE(Value*, const String*);
const Value* APS5_VABI _ZNK3sce4Json5ValueixEm(const Value*, std::size_t);
int APS5_VABI _ZN3sce4Json5Value9serializeERNS0_6StringE(Value*, String*);
int APS5_VABI _ZN3sce4Json6Parser5parseERNS0_5ValueEPKcm(Value*, const char*, std::size_t);
int APS5_VABI _ZN3sce4Json6Parser5parseERNS0_5ValueEPFiRcPvES5_(Value*, int (APS5_VABI*)(char&, void*), void*);
bool APS5_VABI _ZNK3sce4Json6Object5emptyEv(const Object*);
std::size_t APS5_VABI _ZNK3sce4Json6Object4sizeEv(const Object*);
const Object* APS5_VABI _ZNK3sce4Json5Value9getObjectEv(const Value*);
void APS5_VABI _ZN3sce4Json5ValueC1ENS0_9ValueTypeE(Value*, std::int32_t);
const Value* APS5_VABI _ZNK3sce4Json5Value8getValueEm(const Value*, std::size_t);
const Value* APS5_VABI _ZNK3sce4Json5Value8getValueERKNS0_6StringE(const Value*, const String*);
Value* APS5_VABI _ZN3sce4Json5Value10referValueEm(Value*, std::size_t);
void APS5_VABI _ZN3sce4Json14InitParameter2C1Ev(void*);
void APS5_VABI _ZN3sce4Json14InitParameter2C2Ev(void*);
void APS5_VABI _ZN3sce4Json14InitParameter212setAllocatorEPNS0_12MemAllocatorEPv(void*, void*, void*);
void APS5_VABI _ZN3sce4Json14InitParameter217setFileBufferSizeEm(void*, std::size_t);
int APS5_VABI _ZN3sce4Json11Initializer10initializeEPKNS0_14InitParameter2E(void*, const void*);
void APS5_VABI _ZN3sce4Json14InitParameter2C2Ev(void*);
void APS5_VABI _ZN3sce4Json17InitParameterRttiC1EPNS0_14AllocParamRttiEPvm(void*, void*, void*, std::size_t);
void APS5_VABI _ZN3sce4Json18InitParameterRtti216setAllocatorRttiEPNS0_14AllocParamRttiEPv(void*, void*, void*);
void APS5_VABI _ZN3sce4Json12MemAllocator11notifyErrorEimPv(void*, int, std::size_t, void*);
}

static void Check(bool value, int line) {
    if (!value) {
        std::fprintf(stderr, "Json check failed at line %d\n", line);
        std::abort();
    }
}
#define Require(value) Check((value), __LINE__)

enum : std::int32_t { TypeNull, TypeBoolean, TypeInteger, TypeUInteger, TypeReal, TypeString, TypeArray, TypeObject };

static Value fallback{};
static int callbackCalls = 0;
static std::int32_t lastRequested = -1;
static const Value* lastParent = nullptr;
static void* lastContext = nullptr;

static const Value& APS5_VABI OnNullAccess(std::int32_t requested, const Value* parent, void* context) {
    ++callbackCalls;
    lastRequested = requested;
    lastParent = parent;
    lastContext = context;
    return fallback;
}

static std::string Serialize(Value& value) {
    String out{};
    _ZN3sce4Json6StringC1Ev(&out);
    Require(_ZN3sce4Json5Value9serializeERNS0_6StringE(&value, &out) == 0);
    std::string text(_ZNK3sce4Json6String5c_strEv(&out), _ZNK3sce4Json6String6lengthEv(&out));
    _ZN3sce4Json6StringD1Ev(&out);
    return text;
}

static const Value& Member(const Value& value, const char* key) {
    return *_ZNK3sce4Json5ValueixEPKc(&value, key);
}

static void ParseAndRoundTrip() {
    const std::string text =
        "{ \"name\" : \"x\\u00e9\\n\", \"count\": 3, \"big\": 18446744073709551615, \"neg\": -5,"
        " \"pi\": 1.5, \"ok\": true, \"none\": null, \"list\": [1, \"two\", [3]] }";
    Value root{};
    _ZN3sce4Json5ValueC1Ev(&root);
    Require(_ZN3sce4Json6Parser5parseERNS0_5ValueEPKcm(&root, text.c_str(), text.size()) == 0);
    Require(_ZNK3sce4Json5Value7getTypeEv(&root) == TypeObject);
    Require(_ZNK3sce4Json5Value5countEv(&root) == 8);
    Require(std::strcmp(_ZNK3sce4Json6String5c_strEv(_ZNK3sce4Json5Value9getStringEv(&Member(root, "name"))), "x\xc3\xa9\n") == 0);
    Require(_ZNK3sce4Json5Value7getTypeEv(&Member(root, "count")) == TypeInteger);
    Require(*_ZNK3sce4Json5Value10getIntegerEv(&Member(root, "count")) == 3);
    Require(*_ZNK3sce4Json5Value11getUIntegerEv(&Member(root, "count")) == 3);
    Require(*_ZNK3sce4Json5Value7getRealEv(&Member(root, "count")) == 3.0);
    Require(_ZNK3sce4Json5Value7getTypeEv(&Member(root, "big")) == TypeUInteger);
    Require(*_ZNK3sce4Json5Value11getUIntegerEv(&Member(root, "big")) == std::numeric_limits<std::uint64_t>::max());
    Require(*_ZNK3sce4Json5Value10getIntegerEv(&Member(root, "neg")) == -5);
    Require(*_ZNK3sce4Json5Value7getRealEv(&Member(root, "pi")) == 1.5);
    Require(*_ZNK3sce4Json5Value10getBooleanEv(&Member(root, "ok")));
    Require(_ZNK3sce4Json5Value7getTypeEv(&Member(root, "none")) == TypeNull);
    String present{};
    String absent{};
    _ZN3sce4Json6StringC1EPKc(&present, "ok");
    _ZN3sce4Json6StringC1EPKc(&absent, "applyToAll");
    Require(_ZN3sce4Json5Value10referValueERKNS0_6StringE(&root, &present) == &Member(root, "ok"));
    Require(_ZN3sce4Json5Value10referValueERKNS0_6StringE(&root, &absent) == nullptr);
    Require(_ZNK3sce4Json5Value5countEv(&root) == 8);
    _ZN3sce4Json6StringD1Ev(&present);
    _ZN3sce4Json6StringD1Ev(&absent);

    const Value& list = Member(root, "list");
    const Array* array = _ZNK3sce4Json5Value8getArrayEv(&list);
    Require(_ZNK3sce4Json5Array4sizeEv(array) == 3);
    std::vector<std::int32_t> types;
    Iterator it{}, end{};
    _ZNK3sce4Json5Array5beginEv(&it, array);
    _ZNK3sce4Json5Array3endEv(&end, array);
    for (; _ZNK3sce4Json5Array8iteratorneERKS2_(&it, &end); _ZN3sce4Json5Array8iteratorppEv(&it))
        types.push_back(_ZNK3sce4Json5Value7getTypeEv(_ZNK3sce4Json5Array8iteratordeEv(&it)));
    _ZN3sce4Json5Array8iteratorD1Ev(&it);
    _ZN3sce4Json5Array8iteratorD1Ev(&end);
    Require((types == std::vector<std::int32_t>{TypeInteger, TypeString, TypeArray}));
    Require(*_ZNK3sce4Json5Value10getIntegerEv(_ZNK3sce4Json5ValueixEm(_ZNK3sce4Json5ValueixEm(&list, 2), 0)) == 3);

    const std::string serialized = Serialize(root);
    Require(serialized == "{\"name\":\"x\xc3\xa9\\n\",\"count\":3,\"big\":18446744073709551615,\"neg\":-5,"
                          "\"pi\":1.5,\"ok\":true,\"none\":null,\"list\":[1,\"two\",[3]]}");
    Value reparsed{};
    _ZN3sce4Json5ValueC1Ev(&reparsed);
    Require(_ZN3sce4Json6Parser5parseERNS0_5ValueEPKcm(&reparsed, serialized.c_str(), serialized.size()) == 0);
    Require(Serialize(reparsed) == serialized);
    _ZN3sce4Json5ValueD1Ev(&reparsed);

    for (const char* invalid : {"{\"a\":}", "[1,]", "\"open", "tru", "{} x", "01"}) {
        Require(_ZN3sce4Json6Parser5parseERNS0_5ValueEPKcm(&root, invalid, std::strlen(invalid)) < 0);
        Require(_ZNK3sce4Json5Value7getTypeEv(&root) == TypeObject && _ZNK3sce4Json5Value5countEv(&root) == 8);
    }
    for (const char* overflow : {"1e309", "[-1e309]", "{\"a\":[1,1e400]}"}) {
        bool unverified = false;
        try {
            _ZN3sce4Json6Parser5parseERNS0_5ValueEPKcm(&root, overflow, std::strlen(overflow));
        } catch (const std::runtime_error& error) {
            unverified = std::string(error.what()).find("unverified") != std::string::npos;
        }
        Require(unverified);
        Require(_ZNK3sce4Json5Value7getTypeEv(&root) == TypeObject && _ZNK3sce4Json5Value5countEv(&root) == 8);
    }
    _ZN3sce4Json5ValueD1Ev(&root);
}

static std::string Nested(std::size_t depth, bool objects) {
    std::string text;
    for (std::size_t i = 0; i < depth; ++i) text += objects ? "{\"a\":" : "[";
    text += "1";
    for (std::size_t i = 0; i < depth; ++i) text += objects ? "}" : "]";
    return text;
}

static void NestingDepth() {
    Value root{};
    _ZN3sce4Json5ValueC1Ev(&root);
    for (const bool objects : {false, true}) {
        const std::string accepted = Nested(512, objects);
        Require(_ZN3sce4Json6Parser5parseERNS0_5ValueEPKcm(&root, accepted.c_str(), accepted.size()) == 0);
        for (const std::size_t depth : {std::size_t{513}, std::size_t{100000}}) {
            const std::string rejected = Nested(depth, objects);
            Require(_ZN3sce4Json6Parser5parseERNS0_5ValueEPKcm(&root, rejected.c_str(), rejected.size()) < 0);
        }
    }
    _ZN3sce4Json5ValueD1Ev(&root);
}

static void ObjectsAndArrays() {
    Object object{};
    _ZN3sce4Json6ObjectC1Ev(&object);
    String alpha{}, beta{};
    _ZN3sce4Json6StringC1EPKc(&alpha, "alpha");
    _ZN3sce4Json6StringC1EPKc(&beta, "beta");
    Require(_ZNK3sce4Json6Object5emptyEv(&object));
    Value* first = _ZN3sce4Json6ObjectixERKNS0_6StringE(&object, &alpha);
    Require(!_ZNK3sce4Json6Object5emptyEv(&object));
    Require(_ZNK3sce4Json5Value7getTypeEv(first) == TypeNull);
    Require(_ZN3sce4Json5Value3setEl(first, 1) == 0);
    Require(_ZN3sce4Json5Value3setEPKc(_ZN3sce4Json6ObjectixERKNS0_6StringE(&object, &beta), "b") == 0);
    Require(_ZN3sce4Json6ObjectixERKNS0_6StringE(&object, &alpha) == first);

    std::vector<std::string> keys;
    Iterator it{}, end{};
    _ZNK3sce4Json6Object5beginEv(&it, &object);
    _ZNK3sce4Json6Object3endEv(&end, &object);
    for (; _ZNK3sce4Json6Object8iteratorneERKS2_(&it, &end); _ZN3sce4Json6Object8iteratorppEv(&it)) {
        const Pair* pair = _ZNK3sce4Json6Object8iteratordeEv(&it);
        keys.emplace_back(_ZNK3sce4Json6String5c_strEv(&pair->key));
        if (keys.size() == 1) Require(&pair->value == first);
    }
    _ZN3sce4Json6Object8iteratorD1Ev(&it);
    _ZN3sce4Json6Object8iteratorD1Ev(&end);
    Require((keys == std::vector<std::string>{"alpha", "beta"}));

    Value wrapped{};
    _ZN3sce4Json5ValueC1ERKNS0_6ObjectE(&wrapped, &object);
    Require(Serialize(wrapped) == "{\"alpha\":1,\"beta\":\"b\"}");
    _ZN3sce4Json5ValueD1Ev(&wrapped);
    _ZN3sce4Json6StringD1Ev(&alpha);
    _ZN3sce4Json6StringD1Ev(&beta);
    _ZN3sce4Json6ObjectD1Ev(&object);

    Array array{};
    _ZN3sce4Json5ArrayC1Ev(&array);
    Value flag{}, real{};
    _ZN3sce4Json5ValueC1Eb(&flag, true);
    _ZN3sce4Json5ValueC1Ed(&real, 2.5);
    _ZN3sce4Json5Array9push_backERKNS0_5ValueE(&array, &flag);
    _ZN3sce4Json5Array9push_backERKNS0_5ValueE(&array, &real);
    _ZN3sce4Json5ValueD1Ev(&flag);
    _ZN3sce4Json5ValueD1Ev(&real);
    Require(_ZNK3sce4Json5Array4sizeEv(&array) == 2);
    Require(*_ZNK3sce4Json5Value7getRealEv(_ZNK3sce4Json5Array4backEv(&array)) == 2.5);
    int visited = 0;
    _ZNK3sce4Json5Array5beginEv(&it, &array);
    _ZNK3sce4Json5Array3endEv(&end, &array);
    for (; _ZNK3sce4Json5Array8iteratorneERKS2_(&it, &end); _ZN3sce4Json5Array8iteratorppEv(&it)) ++visited;
    Require(visited == 2);
    Require(*_ZNK3sce4Json5Value10getBooleanEv(_ZNK3sce4Json5Array5frontEv(&array)));
    _ZNK3sce4Json5Array5beginEv(&it, &array);
    Require(_ZNK3sce4Json5Array8iteratorptEv(&it) == _ZNK3sce4Json5Array8iteratordeEv(&it));
    Array copy{};
    _ZN3sce4Json5ArrayC1ERKS1_(&copy, &array);
    _ZN3sce4Json5Array5clearEv(&array);
    Require(_ZNK3sce4Json5Array4sizeEv(&array) == 0);
    bool threw = false;
    try {
        _ZNK3sce4Json5Array5frontEv(&array);
    } catch (const std::out_of_range&) {
        threw = true;
    }
    Require(threw);
    Require(_ZNK3sce4Json5Array4sizeEv(&copy) == 2);
    Require(*_ZNK3sce4Json5Value10getBooleanEv(_ZNK3sce4Json5Array5frontEv(&copy)));
    Require(*_ZNK3sce4Json5Value7getRealEv(_ZNK3sce4Json5Array4backEv(&copy)) == 2.5);
    _ZN3sce4Json5ArrayD1Ev(&copy);
    _ZN3sce4Json5ArrayD1Ev(&array);
}

static void ObjectFind() {
    Object object{};
    _ZN3sce4Json6ObjectC1Ev(&object);
    String alpha{}, beta{}, gamma{};
    _ZN3sce4Json6StringC1EPKc(&alpha, "alpha");
    _ZN3sce4Json6StringC1EPKc(&beta, "beta");
    _ZN3sce4Json6StringC1EPKc(&gamma, "gamma");
    Iterator found{}, end{};
    _ZNK3sce4Json6Object3endEv(&end, &object);
    _ZNK3sce4Json6Object4findERKNS0_6StringE(&found, &object, &alpha);
    Require(!_ZNK3sce4Json6Object8iteratorneERKS2_(&found, &end));
    _ZN3sce4Json6Object8iteratorD1Ev(&found);
    _ZN3sce4Json6Object8iteratorD1Ev(&end);

    Require(_ZN3sce4Json5Value3setEl(_ZN3sce4Json6ObjectixERKNS0_6StringE(&object, &alpha), 1) == 0);
    Value* second = _ZN3sce4Json6ObjectixERKNS0_6StringE(&object, &beta);
    Require(_ZN3sce4Json5Value3setEPKc(second, "b") == 0);
    _ZNK3sce4Json6Object3endEv(&end, &object);
    Iterator* returned = _ZNK3sce4Json6Object4findERKNS0_6StringE(&found, &object, &beta);
    Require(returned == &found);
    Require(_ZNK3sce4Json6Object8iteratorneERKS2_(&found, &end));
    const Pair* pair = _ZNK3sce4Json6Object8iteratorptEv(&found);
    Require(pair == _ZNK3sce4Json6Object8iteratordeEv(&found));
    Require(&pair->value == second);
    Require(std::strcmp(_ZNK3sce4Json6String5c_strEv(&pair->key), "beta") == 0);
    _ZN3sce4Json6Object8iteratorppEv(&found);
    Require(!_ZNK3sce4Json6Object8iteratorneERKS2_(&found, &end));
    _ZNK3sce4Json6Object4findERKNS0_6StringE(&found, &object, &gamma);
    Require(!_ZNK3sce4Json6Object8iteratorneERKS2_(&found, &end));
    Require(_ZNK3sce4Json6Object4sizeEv(&object) == 2);
    _ZN3sce4Json6Object8iteratorD1Ev(&found);
    _ZN3sce4Json6Object8iteratorD1Ev(&end);

    Require(_ZNK3sce4Json6String7compareEPKc(&beta, "beta") == 0);
    Require(_ZNK3sce4Json6String7compareEPKc(&beta, "betb") < 0);
    Require(_ZNK3sce4Json6String7compareEPKc(&beta, "bet") > 0);
    Require(_ZNK3sce4Json6String7compareEPKc(&beta, "alpha") > 0);
    bool threw = false;
    try {
        static_cast<void>(_ZNK3sce4Json6String7compareEPKc(&beta, nullptr));
    } catch (const std::invalid_argument&) {
        threw = true;
    }
    Require(threw);
    _ZN3sce4Json6StringD1Ev(&alpha);
    _ZN3sce4Json6StringD1Ev(&beta);
    _ZN3sce4Json6StringD1Ev(&gamma);
    _ZN3sce4Json6ObjectD1Ev(&object);
}

static void NullAccess(SetNullAccessCallback setCallback) {
    callbackCalls = 0;
    lastRequested = -1;
    lastParent = nullptr;
    lastContext = nullptr;
    alignas(16) std::uint8_t initializer[16]{};
    alignas(16) std::uint8_t parameter[64]{};
    Require(_ZN3sce4Json11InitializerC1Ev(initializer) == 0);
    Require(_ZN3sce4Json11Initializer10initializeEPKNS0_13InitParameterE(initializer, parameter) == 0);
    int context = 0;
    Require(setCallback(initializer, OnNullAccess, &context) == 0);
    _ZN3sce4Json5ValueC1Ev(&fallback);
    Require(_ZN3sce4Json5Value3setEl(&fallback, 99) == 0);

    Value root{};
    _ZN3sce4Json5ValueC1Ev(&root);
    const char text[] = "{\"present\":\"text\"}";
    Require(_ZN3sce4Json6Parser5parseERNS0_5ValueEPKcm(&root, text, sizeof(text) - 1) == 0);
    Require(&Member(root, "missing") == &fallback);
    Require(callbackCalls == 1 && lastRequested == TypeNull && lastParent == &root && lastContext == &context);
    Require(*_ZNK3sce4Json5Value10getIntegerEv(&Member(root, "present")) == 99);
    Require(callbackCalls == 2 && lastRequested == TypeInteger && lastParent == &Member(root, "present"));
    Require(!*_ZNK3sce4Json5Value10getBooleanEv(&Member(root, "present")));
    Require(callbackCalls == 3 && lastRequested == TypeBoolean);
    Require(_ZNK3sce4Json5Value7getTypeEv(_ZNK3sce4Json5ValueixEm(&root, 0)) == TypeInteger);

    Require(_ZN3sce4Json11Initializer9terminateEv(initializer) == 0);
    const Value& unhandled = Member(root, "missing");
    Require(&unhandled != &fallback && _ZNK3sce4Json5Value7getTypeEv(&unhandled) == TypeNull);
    Require(callbackCalls == 4);
    _ZN3sce4Json5ValueD1Ev(&root);
    _ZN3sce4Json5ValueD1Ev(&fallback);
    Require(_ZN3sce4Json11InitializerD1Ev(initializer) == 0);
}

static void ValueAccess() {
    for (std::int32_t type = TypeNull; type <= TypeObject; ++type) {
        Value typed{};
        _ZN3sce4Json5ValueC1ENS0_9ValueTypeE(&typed, type);
        Require(_ZNK3sce4Json5Value7getTypeEv(&typed) == type);
        Require(_ZNK3sce4Json5Value5countEv(&typed) == 0);
        _ZN3sce4Json5ValueD1Ev(&typed);
    }

    Value root{};
    _ZN3sce4Json5ValueC1Ev(&root);
    const char text[] = "{\"list\":[10,20,30],\"name\":\"value\",\"flag\":true}";
    Require(_ZN3sce4Json6Parser5parseERNS0_5ValueEPKcm(&root, text, sizeof(text) - 1) == 0);
    Require(_ZNK3sce4Json6Object4sizeEv(_ZNK3sce4Json5Value9getObjectEv(&root)) == 3);

    String key{};
    _ZN3sce4Json6StringC1EPKc(&key, "list");
    const Value* list = _ZNK3sce4Json5Value8getValueERKNS0_6StringE(&root, &key);
    Require(_ZNK3sce4Json5Value7getTypeEv(list) == TypeArray);
    Require(*_ZNK3sce4Json5Value10getIntegerEv(_ZNK3sce4Json5Value8getValueEm(list, 1)) == 20);
    Require(_ZNK3sce4Json5Value8getValueEm(list, 2) == _ZNK3sce4Json5ValueixEm(list, 2));
    Require(_ZNK3sce4Json5Value7getTypeEv(_ZNK3sce4Json5Value8getValueEm(list, 3)) == TypeNull);

    Value* mutableList = _ZN3sce4Json5Value10referValueERKNS0_6StringE(&root, &key);
    Value* element = _ZN3sce4Json5Value10referValueEm(mutableList, 0);
    Require(element != nullptr);
    Require(_ZN3sce4Json5Value3setEl(element, 15) == 0);
    Require(*_ZNK3sce4Json5Value10getIntegerEv(_ZNK3sce4Json5Value8getValueEm(list, 0)) == 15);
    Require(_ZN3sce4Json5Value10referValueEm(mutableList, 3) == nullptr);
    Require(_ZN3sce4Json5Value10referValueEm(&root, 0) == nullptr);
    _ZN3sce4Json6StringD1Ev(&key);

    String missing{};
    _ZN3sce4Json6StringC1EPKc(&missing, "missing");
    Require(_ZNK3sce4Json5Value7getTypeEv(_ZNK3sce4Json5Value8getValueERKNS0_6StringE(&root, &missing)) == TypeNull);
    _ZN3sce4Json6StringD1Ev(&missing);
    _ZN3sce4Json5ValueD1Ev(&root);

    alignas(16) std::uint8_t parameter[40];
    std::memset(parameter, 0xff, sizeof(parameter));
    _ZN3sce4Json14InitParameter2C1Ev(parameter);
    int allocator = 0;
    int userData = 0;
    _ZN3sce4Json14InitParameter212setAllocatorEPNS0_12MemAllocatorEPv(parameter, &allocator, &userData);
    _ZN3sce4Json14InitParameter217setFileBufferSizeEm(parameter, 4096);
    void* stored[3]{};
    std::memcpy(stored, parameter, sizeof(stored));
    Require(stored[0] == &allocator && stored[1] == &userData && reinterpret_cast<std::uintptr_t>(stored[2]) == 4096);
    alignas(16) std::uint8_t initializer[16]{};
    Require(_ZN3sce4Json11InitializerC1Ev(initializer) == 0);
    Require(_ZN3sce4Json11Initializer10initializeEPKNS0_14InitParameter2E(initializer, parameter) == 0);
    Require(_ZN3sce4Json11Initializer9terminateEv(initializer) == 0);
    Require(_ZN3sce4Json11InitializerD1Ev(initializer) == 0);

    std::memset(parameter, 0xff, sizeof(parameter));
    _ZN3sce4Json14InitParameter2C2Ev(parameter);
    std::memcpy(stored, parameter, sizeof(stored));
    Require(stored[0] == nullptr && stored[1] == nullptr && stored[2] == nullptr);

    int allocParam = 0;
    _ZN3sce4Json17InitParameterRttiC1EPNS0_14AllocParamRttiEPvm(parameter, &allocParam, &userData, 8192);
    std::memcpy(stored, parameter, sizeof(stored));
    Require(stored[0] == &allocParam && stored[1] == &userData && reinterpret_cast<std::uintptr_t>(stored[2]) == 8192);
    int otherParam = 0;
    _ZN3sce4Json18InitParameterRtti216setAllocatorRttiEPNS0_14AllocParamRttiEPv(parameter, &otherParam, nullptr);
    std::memcpy(stored, parameter, sizeof(stored));
    Require(stored[0] == &otherParam && stored[1] == nullptr && reinterpret_cast<std::uintptr_t>(stored[2]) == 8192);
    _ZN3sce4Json12MemAllocator11notifyErrorEimPv(&allocator, -1, 64, &userData);
}

static void InitParameter2BaseConstructor() {
    alignas(16) std::uint8_t parameter[40];
    std::memset(parameter, 0xff, sizeof(parameter));
    _ZN3sce4Json14InitParameter2C1Ev(parameter);
    alignas(16) std::uint8_t baseStorage[72];
    std::memset(baseStorage, 0xff, sizeof(baseStorage));
    auto* baseParameter = baseStorage + 16;
    _ZN3sce4Json14InitParameter2C2Ev(baseParameter);
    Require(std::memcmp(parameter, baseParameter, sizeof(parameter)) == 0);
    void* defaultAllocator;
    void* defaultUserData;
    std::size_t defaultFileBufferSize;
    std::memcpy(&defaultAllocator, baseParameter, sizeof(defaultAllocator));
    std::memcpy(&defaultUserData, baseParameter + sizeof(void*), sizeof(defaultUserData));
    std::memcpy(&defaultFileBufferSize, baseParameter + 2 * sizeof(void*), sizeof(defaultFileBufferSize));
    Require(defaultAllocator == nullptr && defaultUserData == nullptr && defaultFileBufferSize == 0);
    int allocator = 0;
    int userData = 0;
    _ZN3sce4Json14InitParameter212setAllocatorEPNS0_12MemAllocatorEPv(baseParameter, &allocator, &userData);
    _ZN3sce4Json14InitParameter217setFileBufferSizeEm(baseParameter, 4096);
    void* storedAllocator;
    void* storedUserData;
    std::size_t storedFileBufferSize;
    std::memcpy(&storedAllocator, baseParameter, sizeof(storedAllocator));
    std::memcpy(&storedUserData, baseParameter + sizeof(void*), sizeof(storedUserData));
    std::memcpy(&storedFileBufferSize, baseParameter + 2 * sizeof(void*), sizeof(storedFileBufferSize));
    Require(storedAllocator == &allocator && storedUserData == &userData && storedFileBufferSize == 4096);
    for (std::size_t i = 0; i < 16; ++i) Require(baseStorage[i] == 0xff);
    for (std::size_t i = 16 + sizeof(parameter); i < sizeof(baseStorage); ++i)
        Require(baseStorage[i] == 0xff);
    alignas(16) std::uint8_t initializer[16]{};
    Require(_ZN3sce4Json11InitializerC1Ev(initializer) == 0);
    Require(_ZN3sce4Json11Initializer10initializeEPKNS0_14InitParameter2E(initializer, baseParameter) == 0);
    Require(_ZN3sce4Json11Initializer9terminateEv(initializer) == 0);
    Require(_ZN3sce4Json11InitializerD1Ev(initializer) == 0);
}

static void ValueClear() {
    Value value{};
    _ZN3sce4Json5ValueC1Ev(&value);
    Require(_ZNK3sce4Json5Value7getTypeEv(&value) == TypeNull);
    _ZN3sce4Json5Value5clearEv(&value);
    Require(_ZNK3sce4Json5Value7getTypeEv(&value) == TypeNull);

    Require(_ZN3sce4Json5Value3setEl(&value, 12345) == 0);
    Require(_ZNK3sce4Json5Value7getTypeEv(&value) == TypeInteger);
    _ZN3sce4Json5Value5clearEv(&value);
    Require(_ZNK3sce4Json5Value7getTypeEv(&value) == TypeNull);

    Require(_ZN3sce4Json5Value3setEPKc(&value, "test string") == 0);
    Require(_ZNK3sce4Json5Value7getTypeEv(&value) == TypeString);
    _ZN3sce4Json5Value5clearEv(&value);
    Require(_ZNK3sce4Json5Value7getTypeEv(&value) == TypeNull);

    Object obj{};
    _ZN3sce4Json6ObjectC1Ev(&obj);
    String key{};
    _ZN3sce4Json6StringC1EPKc(&key, "prop");
    Value* item = _ZN3sce4Json6ObjectixERKNS0_6StringE(&obj, &key);
    _ZN3sce4Json5Value3setEl(item, 999);
    _ZN3sce4Json5ValueC1ERKNS0_6ObjectE(&value, &obj);
    Require(_ZNK3sce4Json5Value7getTypeEv(&value) == TypeObject);
    _ZN3sce4Json5Value5clearEv(&value);
    Require(_ZNK3sce4Json5Value7getTypeEv(&value) == TypeNull);
    _ZN3sce4Json6StringD1Ev(&key);
    _ZN3sce4Json6ObjectD1Ev(&obj);

    Require(_ZN3sce4Json5Value3setEl(&value, 777) == 0);
    Require(_ZNK3sce4Json5Value7getTypeEv(&value) == TypeInteger);
    Require(*_ZNK3sce4Json5Value10getIntegerEv(&value) == 777);

    _ZN3sce4Json5ValueD1Ev(&value);
}

struct ReadState {
    const char* text;
    std::size_t position;
    int calls;
};

static int APS5_VABI ReadNext(char& ch, void* context) {
    auto* state = static_cast<ReadState*>(context);
    ++state->calls;
    if (state->text[state->position] == '\0') {
        ch = '\0';
        return -1;
    }
    ch = state->text[state->position++];
    return 0;
}

static void StreamParse() {
    Value root{};
    _ZN3sce4Json5ValueC1Ev(&root);
    ReadState valid{"{\"list\": [1, 2.5, true]}", 0, 0};
    Require(_ZN3sce4Json6Parser5parseERNS0_5ValueEPFiRcPvES5_(&root, ReadNext, &valid) == 0);
    Require(valid.calls == static_cast<int>(std::strlen(valid.text)) + 1);
    Require(_ZNK3sce4Json5Value7getTypeEv(&root) == TypeObject);
    ReadState invalid{"{\"list\": [1, 2.5", 0, 0};
    Require(_ZN3sce4Json6Parser5parseERNS0_5ValueEPFiRcPvES5_(&root, ReadNext, &invalid) < 0);
    ReadState trailing{"[1] 2", 0, 0};
    Require(_ZN3sce4Json6Parser5parseERNS0_5ValueEPFiRcPvES5_(&root, ReadNext, &trailing) < 0);
    _ZN3sce4Json5ValueD1Ev(&root);
}

int main() {
    ParseAndRoundTrip();
    NestingDepth();
    ObjectsAndArrays();
    ObjectFind();
    NullAccess(_ZN3sce4Json11Initializer27setGlobalNullAccessCallBackEPFRKNS0_5ValueENS0_9ValueTypeEPS3_PvES7_);
    NullAccess(_ZN3sce4Json11Initializer27setGlobalNullAccessCallbackEPFRKNS0_5ValueENS0_9ValueTypeEPS3_PvES7_);
    ValueAccess();
    InitParameter2BaseConstructor();
    ValueClear();
    StreamParse();
}
