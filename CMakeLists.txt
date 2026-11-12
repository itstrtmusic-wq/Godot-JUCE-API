cmake_minimum_required(VERSION 3.22)
project(GodotJuceBridge VERSION 0.1.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
include(FetchContent)
FetchContent_Declare(godot_cpp GIT_REPOSITORY https://github.com/godotengine/godot-cpp.git GIT_TAG godot-4.3-stable GIT_SHALLOW TRUE)
FetchContent_Declare(juce GIT_REPOSITORY https://github.com/juce-framework/JUCE.git GIT_TAG 8.0.6 GIT_SHALLOW TRUE)
# No JUCE GUI tools are needed: Godot owns the user interface.
set(JUCE_MODULES_ONLY ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(godot_cpp juce)
# This bridge only derives from RefCounted. Avoid compiling unused engine classes.
option(BRIDGE_MINIMAL_BINDINGS "Build only required Godot class bindings" ON)
if(BRIDGE_MINIMAL_BINDINGS)
 get_target_property(binding_sources godot-cpp SOURCES)
 list(FILTER binding_sources EXCLUDE REGEX "/gen/src/classes/.*")
 list(APPEND binding_sources
  "${godot_cpp_BINARY_DIR}/gen/src/classes/object.cpp"
  "${godot_cpp_BINARY_DIR}/gen/src/classes/ref_counted.cpp"
  "${godot_cpp_BINARY_DIR}/gen/src/classes/class_db_singleton.cpp")
 set_property(TARGET godot-cpp PROPERTY SOURCES "${binding_sources}")
endif()
add_library(juce_bridge SHARED src/bridge.cpp)
target_link_libraries(juce_bridge PRIVATE godot-cpp juce::juce_audio_devices juce::juce_audio_formats)
target_compile_definitions(juce_bridge PRIVATE JUCE_WEB_BROWSER=0 JUCE_USE_CURL=0 JUCE_USE_FLAC=0 JUCE_USE_OGGVORBIS=0 JUCE_ASIO=0)
set_target_properties(juce_bridge PROPERTIES PREFIX "" OUTPUT_NAME "juce_bridge" RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/demo/addons/juce_bridge/bin" LIBRARY_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/demo/addons/juce_bridge/bin")
foreach(config DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
 set_target_properties(juce_bridge PROPERTIES RUNTIME_OUTPUT_DIRECTORY_${config} "${CMAKE_SOURCE_DIR}/demo/addons/juce_bridge/bin")
endforeach()

if(UNIX AND NOT APPLE)
 target_link_options(juce_bridge PRIVATE "-Wl,--no-undefined")
endif()
