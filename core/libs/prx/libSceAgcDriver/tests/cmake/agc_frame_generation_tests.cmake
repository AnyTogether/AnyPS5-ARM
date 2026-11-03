add_test_executable(agc_frame_generation_tests EXCLUDE_FROM_ALL
        tests/FrameGeneration.cpp
)
target_include_directories(agc_frame_generation_tests PRIVATE
        ${LIBS_INCLUDE_DIR}
        ${CMAKE_SOURCE_DIR}/core/shader/recompiler
        ${ANYPS5_VULKAN_HEADERS_INCLUDE_DIR}
)
target_link_libraries(agc_frame_generation_tests PRIVATE
        libSceAgcDriver
        SDL2-static
        libc
)
set_target_properties(agc_frame_generation_tests PROPERTIES CXX_EXTENSIONS OFF)
configure_windows_unwind(agc_frame_generation_tests)

if(BUILD_TESTING)
    set_target_properties(agc_frame_generation_tests PROPERTIES EXCLUDE_FROM_ALL OFF)
    add_test(NAME agc_frame_generation COMMAND agc_frame_generation_tests)
    set_tests_properties(agc_frame_generation PROPERTIES SKIP_RETURN_CODE 77 WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
endif()
