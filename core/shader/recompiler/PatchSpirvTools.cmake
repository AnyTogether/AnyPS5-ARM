get_target_property(spirvToolsSourceDir SPIRV-Tools-opt SOURCE_DIR)
set(spirvToolsRedundancySource "${spirvToolsSourceDir}/redundancy_elimination.cpp")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${spirvToolsRedundancySource}")
file(READ "${spirvToolsRedundancySource}" spirvToolsRedundancy)

set(spirvToolsOldTraversal [=[
    for (DominatorTreeNode* child : todo[next_node].node->children_) {
      todo.push_back({child, todo[next_node].value_to_id_map});
    }
]=])
set(spirvToolsNewTraversal [=[
    const auto& children = todo[next_node].node->children_;
    for (size_t child_index = 0; child_index < children.size(); ++child_index) {
      if (child_index + 1 == children.size()) {
        todo.push_back({children[child_index],
                        std::move(todo[next_node].value_to_id_map)});
      } else {
        todo.push_back({children[child_index], todo[next_node].value_to_id_map});
      }
    }
    todo[next_node].value_to_id_map.clear();
]=])
string(FIND "${spirvToolsRedundancy}" "${spirvToolsOldTraversal}" spirvToolsTraversalPosition)
if(spirvToolsTraversalPosition EQUAL -1)
    message(FATAL_ERROR "SPIRV-Tools redundancy traversal has changed; review the local memory fix")
endif()
string(REPLACE "${spirvToolsOldTraversal}" "${spirvToolsNewTraversal}" spirvToolsRedundancy "${spirvToolsRedundancy}")
string(REPLACE "#include \"source/opt/redundancy_elimination.h\"\n"
        "#include \"source/opt/redundancy_elimination.h\"\n\n#include <utility>\n"
        spirvToolsRedundancy "${spirvToolsRedundancy}")

set(spirvToolsPatchedDir "${CMAKE_BINARY_DIR}/3rdparty/SPIRV-Tools/patched")
set(spirvToolsPatchedSource "${spirvToolsPatchedDir}/redundancy_elimination.cpp")
file(MAKE_DIRECTORY "${spirvToolsPatchedDir}")
file(CONFIGURE OUTPUT "${spirvToolsPatchedSource}" CONTENT "${spirvToolsRedundancy}" @ONLY)

get_target_property(spirvToolsSources SPIRV-Tools-opt SOURCES)
set(spirvToolsPatchedSources)
set(spirvToolsReplacements 0)
foreach(source IN LISTS spirvToolsSources)
    get_filename_component(sourcePath "${source}" ABSOLUTE BASE_DIR "${spirvToolsSourceDir}")
    if(sourcePath STREQUAL spirvToolsRedundancySource)
        list(APPEND spirvToolsPatchedSources "${spirvToolsPatchedSource}")
        math(EXPR spirvToolsReplacements "${spirvToolsReplacements} + 1")
    else()
        list(APPEND spirvToolsPatchedSources "${source}")
    endif()
endforeach()
if(NOT spirvToolsReplacements EQUAL 1)
    message(FATAL_ERROR "SPIRV-Tools optimizer sources have changed; review the local memory fix")
endif()
set_property(TARGET SPIRV-Tools-opt PROPERTY SOURCES "${spirvToolsPatchedSources}")
