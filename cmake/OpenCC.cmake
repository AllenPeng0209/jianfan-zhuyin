set(OPENCC_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/Vendor/Dependencies/SwiftyOpenCC/OpenCC)
file(GLOB_RECURSE MARISA_SOURCES CONFIGURE_DEPENDS ${OPENCC_ROOT}/deps/marisa-0.2.6/lib/*.cc)
set(OPENCC_SOURCES
    BinaryDict Conversion ConversionChain Converter DartsDict Dict DictConverter
    DictEntry DictGroup Lexicon MarisaDict MaxMatchSegmentation Segmentation
    SerializedValues TextDict UTF8StringSlice UTF8Util)
list(TRANSFORM OPENCC_SOURCES PREPEND "${OPENCC_ROOT}/src/")
list(TRANSFORM OPENCC_SOURCES APPEND ".cpp")
add_library(JianfanOpenCC STATIC ${OPENCC_SOURCES} ${MARISA_SOURCES})
target_include_directories(JianfanOpenCC PUBLIC ${OPENCC_ROOT}/src PRIVATE
    ${OPENCC_ROOT}/deps/marisa-0.2.6/include ${OPENCC_ROOT}/deps/marisa-0.2.6/lib
    ${OPENCC_ROOT}/deps/darts-clone)
target_compile_definitions(JianfanOpenCC PUBLIC Opencc_BUILT_AS_STATIC PRIVATE ENABLE_DARTS)
set_target_properties(JianfanOpenCC PROPERTIES POSITION_INDEPENDENT_CODE ON)
