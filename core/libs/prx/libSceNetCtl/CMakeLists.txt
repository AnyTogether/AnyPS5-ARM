set(onlineBridgeSources
        ${CMAKE_CURRENT_SOURCE_DIR}/src/OnlineWire.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/src/OnlineBridge.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/src/OnlineObserver.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/src/OnlineEnvironment.cpp
)
add_library(libSceNetCtl SHARED EXCLUDE_FROM_ALL Export.cpp ${onlineBridgeSources} ${CMAKE_CURRENT_SOURCE_DIR}/src/OnlineExports.cpp)
target_include_directories(libSceNetCtl PRIVATE ${LIBS_INCLUDE_DIR} ${CMAKE_BINARY_DIR}/core/libs/prx/libSceAgcDriver/generated)
add_dependencies(libSceNetCtl agc_trace_revision)
target_link_libraries(libSceNetCtl PRIVATE mbedcrypto)
configure_windows_unwind(libSceNetCtl)

if(BUILD_TESTING)
    add_test_executable(online_bridge_tests tests/OnlineBridge.cpp tests/FakeLauncher.cpp ${onlineBridgeSources})
    target_include_directories(online_bridge_tests PRIVATE ${LIBS_INCLUDE_DIR})
    target_link_libraries(online_bridge_tests PRIVATE mbedcrypto)
    set_target_properties(online_bridge_tests PROPERTIES CXX_EXTENSIONS OFF)
    add_test(NAME online_bridge COMMAND online_bridge_tests)
    set_tests_properties(online_bridge PROPERTIES TIMEOUT 60)

    add_test_executable(online_observation_tests tests/OnlineObservation.cpp)
    target_include_directories(online_observation_tests PRIVATE ${LIBS_INCLUDE_DIR})
    target_link_libraries(online_observation_tests PRIVATE libSceNpManager libSceNpWebApi2 libSceNpMatching2 libSceNetCtl libc)
    add_test(NAME online_observation COMMAND online_observation_tests)
    set_tests_properties(online_observation PROPERTIES TIMEOUT 30
        ENVIRONMENT "ANYPS5_ONLINE_LOG=${CMAKE_CURRENT_BINARY_DIR}/online_observation.jsonl")

    add_test_executable(online_np_manager_tests tests/OnlineNpManager.cpp tests/FakeLauncher.cpp src/OnlineWire.cpp)
    target_include_directories(online_np_manager_tests PRIVATE ${LIBS_INCLUDE_DIR})
    target_link_libraries(online_np_manager_tests PRIVATE libSceNpManager libSceNetCtl libc mbedcrypto)
    add_test(NAME online_np_manager COMMAND online_np_manager_tests)
    set_tests_properties(online_np_manager PROPERTIES TIMEOUT 60)

    add_test_executable(online_web_api2_tests tests/OnlineWebApi2.cpp tests/FakeLauncher.cpp src/OnlineWire.cpp)
    target_include_directories(online_web_api2_tests PRIVATE ${LIBS_INCLUDE_DIR})
    target_link_libraries(online_web_api2_tests PRIVATE libSceNpWebApi2 libSceNpManager libSceNetCtl libc mbedcrypto)
    add_test(NAME online_web_api2 COMMAND online_web_api2_tests)
    set_tests_properties(online_web_api2 PROPERTIES TIMEOUT 60)

    add_test_executable(online_net_p2p_tests tests/OnlineNetP2p.cpp tests/FakeLauncher.cpp src/OnlineWire.cpp)
    target_include_directories(online_net_p2p_tests PRIVATE ${LIBS_INCLUDE_DIR})
    target_link_libraries(online_net_p2p_tests PRIVATE libSceNet libSceNetCtl libkernel libc mbedcrypto)
    add_test(NAME online_net_p2p COMMAND online_net_p2p_tests)
    set_tests_properties(online_net_p2p PROPERTIES TIMEOUT 60)

    # A stand-in game for the launcher's interop tests (OnlineEngineInteropTests, and
    # OnlineEngineP2pTests with two of them); here it only has to show the offline answers.
    add_test_executable(online_probe tests/OnlineProbe.cpp)
    target_include_directories(online_probe PRIVATE ${LIBS_INCLUDE_DIR})
    target_link_libraries(online_probe PRIVATE libSceNpManager libSceNpWebApi2 libSceNet libSceNetCtl libkernel libc)
    add_test(NAME online_probe_offline COMMAND online_probe)
    set_tests_properties(online_probe_offline PROPERTIES TIMEOUT 30
        PASS_REGULAR_EXPRESSION "state=1\nonline_id_error=0x80550006\n.*friends_error=0x80553406\n")

    if(WIN32)
        # Winsock for the bridge and the fake launcher; the libraries' objects use DWARF
        # unwinding, so the C++ personality comes from libc, as for the other tests.
        target_link_libraries(online_bridge_tests PRIVATE ws2_32 libc)
        foreach(onlineTest IN ITEMS online_np_manager_tests online_web_api2_tests online_net_p2p_tests online_probe)
            target_link_libraries(${onlineTest} PRIVATE ws2_32)
        endforeach()
        foreach(onlineTest IN ITEMS online_bridge_tests online_observation_tests online_np_manager_tests online_web_api2_tests online_net_p2p_tests online_probe)
            configure_windows_unwind(${onlineTest})
        endforeach()
        set_tests_properties(online_bridge online_np_manager online_web_api2 online_net_p2p online_probe_offline PROPERTIES
            ENVIRONMENT_MODIFICATION "PATH=path_list_prepend:$<TARGET_FILE_DIR:libSceNetCtl>")
        set_tests_properties(online_observation PROPERTIES
            ENVIRONMENT "ANYPS5_ONLINE_LOG=${CMAKE_CURRENT_BINARY_DIR}/online_observation.jsonl"
            ENVIRONMENT_MODIFICATION "PATH=path_list_prepend:$<TARGET_FILE_DIR:libSceNetCtl>")
    endif()
endif()

if(BUILD_TESTING)
    add_test_executable(guest_net_ctl_v6_callbacks_tests tests/V6Callbacks.cpp)
    target_include_directories(guest_net_ctl_v6_callbacks_tests PRIVATE ${LIBS_INCLUDE_DIR})
    target_link_libraries(guest_net_ctl_v6_callbacks_tests PRIVATE libSceNetCtl libc)
    configure_windows_unwind(guest_net_ctl_v6_callbacks_tests)
    add_test(NAME guest_net_ctl_v6_callbacks COMMAND guest_net_ctl_v6_callbacks_tests)
    set_tests_properties(guest_net_ctl_v6_callbacks PROPERTIES TIMEOUT 20)
    if(WIN32)
        set_tests_properties(guest_net_ctl_v6_callbacks PROPERTIES ENVIRONMENT_MODIFICATION
            "PATH=path_list_prepend:$<TARGET_FILE_DIR:libSceNetCtl>")
    endif()
    add_test_executable(guest_net_ctl_tests ${LIBS_INCLUDE_DIR}/tests/GuestNetCtl.cpp)
    target_include_directories(guest_net_ctl_tests PRIVATE ${LIBS_INCLUDE_DIR})
    target_link_libraries(guest_net_ctl_tests PRIVATE libSceNetCtl libc)
    configure_windows_unwind(guest_net_ctl_tests)
    add_test(NAME guest_net_ctl COMMAND guest_net_ctl_tests)
    set_tests_properties(guest_net_ctl PROPERTIES TIMEOUT 20 SKIP_RETURN_CODE 77)
    if(WIN32)
        target_link_libraries(guest_net_ctl_tests PRIVATE ws2_32)
        set_tests_properties(guest_net_ctl PROPERTIES ENVIRONMENT_MODIFICATION
            "PATH=path_list_prepend:$<TARGET_FILE_DIR:libSceNetCtl>")
    endif()
endif()
