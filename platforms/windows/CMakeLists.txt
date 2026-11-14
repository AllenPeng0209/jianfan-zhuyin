add_library(JianfanIME SHARED TextService.cpp)
target_link_libraries(JianfanIME PRIVATE JianfanCore msctf ole32 oleaut32 uuid advapi32 shell32 shlwapi user32 gdi32)
target_compile_definitions(JianfanIME PRIVATE UNICODE _UNICODE)
set_target_properties(JianfanIME PROPERTIES PREFIX "" OUTPUT_NAME "JianfanIME")
add_custom_command(TARGET JianfanIME POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:JianfanIME>/Data"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${PROJECT_SOURCE_DIR}/Vendor/McBopomofo/Source/Data/data.txt" "$<TARGET_FILE_DIR:JianfanIME>/Data/"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${PROJECT_SOURCE_DIR}/Vendor/McBopomofo/Source/Data/associated-phrases-v2.txt" "$<TARGET_FILE_DIR:JianfanIME>/Data/")
foreach(DICT TSCharacters TSPhrases STCharacters STPhrases)
    add_custom_command(TARGET JianfanIME POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${PROJECT_SOURCE_DIR}/Vendor/Dependencies/SwiftyOpenCC/Sources/OpenCC/Dictionary/${DICT}.ocd2" "$<TARGET_FILE_DIR:JianfanIME>/Data/")
endforeach()
if(JIANFAN_TESTS)
    add_executable(WindowsCOMTest COMTest.cpp)
    target_link_libraries(WindowsCOMTest PRIVATE GTest::gtest_main ole32 uuid msctf)
    add_dependencies(WindowsCOMTest JianfanIME)
endif()
