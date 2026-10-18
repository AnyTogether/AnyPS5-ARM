# The native arm64 translator (docs/dev/NATIVE_ARM64.md). It needs LLVM and Capstone, so it builds on
# its own: cmake -S tools/translator -B build-translator -DLLVM_DIR=$(brew --prefix llvm)/lib/cmake/llvm
cmake_minimum_required(VERSION 3.20)
project(Aps5Translator C CXX ASM)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(LLVM REQUIRED CONFIG)
find_path(CAPSTONE_INCLUDE_DIR capstone/capstone.h HINTS /opt/homebrew/opt/capstone/include REQUIRED)
find_library(CAPSTONE_LIBRARY NAMES libcapstone.a capstone HINTS /opt/homebrew/opt/capstone/lib REQUIRED)

llvm_map_components_to_libnames(translatorLlvmLibraries core support passes target transformutils aarch64codegen aarch64desc aarch64info)

add_executable(aps5-translator src/Main.cpp src/Lifter.cpp src/LiftVector.cpp src/LiftFloat.cpp src/LiftBits.cpp src/Elf.cpp)
target_include_directories(aps5-translator SYSTEM PRIVATE ${LLVM_INCLUDE_DIRS} ${CAPSTONE_INCLUDE_DIR})
target_compile_definitions(aps5-translator PRIVATE ${LLVM_DEFINITIONS})
target_link_libraries(aps5-translator PRIVATE ${translatorLlvmLibraries} ${CAPSTONE_LIBRARY})

# Linked into every translated executable together with the object aps5-translator writes.
add_library(aps5-translator-runtime STATIC runtime/Runtime.cpp runtime/HostBridge.S)
set_target_properties(aps5-translator-runtime PROPERTIES OSX_ARCHITECTURES arm64)
