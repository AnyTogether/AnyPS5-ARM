add_test_executable(agc_upscaler_tests EXCLUDE_FROM_ALL
        tests/Upscaler.cpp
)
target_include_directories(agc_upscaler_tests PRIVATE
        ${LIBS_INCLUDE_DIR}
        ${CMAKE_SOURCE_DIR}/core/shader/recompiler
        ${ANYPS5_VULKAN_HEADERS_INCLUDE_DIR}
)
target_link_libraries(agc_upscaler_tests PRIVATE
        libSceAgcDriver
        SDL2-static
        libc
)
set_target_properties(agc_upscaler_tests PROPERTIES CXX_EXTENSIONS OFF)
configure_windows_unwind(agc_upscaler_tests)

if(BUILD_TESTING)
    set_target_properties(agc_upscaler_tests PROPERTIES EXCLUDE_FROM_ALL OFF)
    add_test(NAME agc_upscaler COMMAND agc_upscaler_tests)
    set_tests_properties(agc_upscaler PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 60 WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
    if(WIN32)
        set_tests_properties(agc_upscaler PROPERTIES ENVIRONMENT_MODIFICATION
            "PATH=path_list_prepend:$<TARGET_FILE_DIR:libc>;PATH=path_list_prepend:$<TARGET_FILE_DIR:libSceAgcDriver>")
    endif()
endif()
