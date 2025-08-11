# Copyright (c) 2014 The Chromium Embedded Framework Authors. All rights
# reserved. Use of this source code is governed by a BSD-style license that
# can be found in the LICENSE file.

#
# Source files.
#
cmake_minimum_required(VERSION 4.0)
project(test_cef)

set_property(GLOBAL PROPERTY USE_FOLDERS ON)

find_library(COCOA_FRAMEWORK Cocoa)
#find_library(FOUNDATION_FRAMEWORK Foundation)
find_library(QUARTZCORE_FRAMEWORK QuartzCore)
find_library(METAL_FRAMEWORK Metal)
find_library(METALKIT_FRAMEWORK MetalKit)
find_library(GAMECONTROLLER_FRAMEWORK GameController)

set(CEF_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/cef_binary_138.0.26+g84f2d27+chromium-138.0.7204.158_macosarm64")
#set(CEF_ROOT "/Users/shiy/code/chromium_git/chromium/src/cef/binary_distrib/cef_binary_139.0.0-master.3247+g0638405+chromium-139.0.7258.0_macosarm64")

set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CEF_ROOT}/cmake;${CMAKE_SOURCE_DIR}/cmake")
message(STATUS "--- Before CEF: CMAKE_CXX_FLAGS = ${CMAKE_CXX_FLAGS}")

find_package(CEF REQUIRED)
message(STATUS "--- After CEF find_package: CMAKE_CXX_FLAGS = ${CMAKE_CXX_FLAGS}")

add_subdirectory(${CEF_LIBCEF_DLL_WRAPPER_PATH} libcef_dll_wrapper)
message(STATUS "--- After libcef_dll_wrapper: CMAKE_CXX_FLAGS = ${CMAKE_CXX_FLAGS}")



# Display configuration settings.
PRINT_CEF_CONFIG()
string(REPLACE "-Werror" "" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")
string(REPLACE "-Werror" "" CMAKE_C_FLAGS "${CMAKE_C_FLAGS}")

include (FetchContent)

FetchContent_Populate(
  imgui
  GIT_REPOSITORY https://github.com/ocornut/imgui.git
  GIT_TAG docking
  GIT_SHALLOW TRUE
)

FetchContent_Populate(
    metal-cpp
    URL https://developer.apple.com/metal/cpp/files/metal-cpp_macOS15.2_iOS18.2.zip
)

include(ExternalProject)
include(CheckLanguage)

macro(print_all_variables)
    message(STATUS "print_all_variables------------------------------------------{")
    get_cmake_property(_variableNames VARIABLES)
    foreach (_variableName ${_variableNames})
        message(STATUS "${_variableName}=${${_variableName}}")
    endforeach()
    message(STATUS "print_all_variables------------------------------------------}")
endmacro()

print_all_variables()
# SHROME sources.
set(SHROME_SRCS

  )
set(SHROME_SRCS_LINUX
  cefsimple_linux.cc
  simple_handler_linux.cc
  )
set(SHROME_SRCS_MAC
  ${imgui_SOURCE_DIR}/backends/imgui_impl_metal.mm 
  ${imgui_SOURCE_DIR}/backends/imgui_impl_osx.mm
  ${imgui_SOURCE_DIR}/imgui.cpp 
  ${imgui_SOURCE_DIR}/imgui_widgets.cpp 
  ${imgui_SOURCE_DIR}/imgui_draw.cpp 
  ${imgui_SOURCE_DIR}/imgui_tables.cpp 
  ${imgui_SOURCE_DIR}/imgui_demo.cpp
  ${imgui_SOURCE_DIR}/imgui_demo.cpp
 # keycode_conversion.cpp
  main.mm
  metal_view.mm
  mycef.mm
  )
set(SHROME_SRCS_WINDOWS
  cefsimple_win.cc
  resource.h
  simple_handler_win.cc
  )
APPEND_PLATFORM_SOURCES(SHROME_SRCS)
source_group(shrome FILES ${SHROME_SRCS})

set(SHROME_WIN_SRCS_WINDOWS
  win/cefsimple.rc
  )
APPEND_PLATFORM_SOURCES(SHROME_WIN_SRCS)
source_group(shrome\\\\win FILES ${SHROME_WIN_SRCS})

set(SHROME_SRCS
  ${SHROME_SRCS}
  ${SHROME_WIN_SRCS}
  )

# SHROME helper sources.
set(SHROME_HELPER_SRCS_MAC
  process_helper_mac.cc
  )
APPEND_PLATFORM_SOURCES(SHROME_HELPER_SRCS)
source_group(shrome FILES ${SHROME_HELPER_SRCS})

# SHROME resources.
set(SHROME_RESOURCES_MAC_SRCS_MAC
  mac/Info.plist.in
  mac/shrome.icns
  )
APPEND_PLATFORM_SOURCES(SHROME_RESOURCES_MAC_SRCS)
source_group(shrome\\\\mac FILES ${SHROME_RESOURCES_MAC_SRCS})

set(SHROME_RESOURCES_MAC_ENGLISH_LPROJ_SRCS_MAC
  mac/English.lproj/InfoPlist.strings
  mac/English.lproj/MainMenu.xib
  )
APPEND_PLATFORM_SOURCES(SHROME_RESOURCES_MAC_ENGLISH_LPROJ_SRCS)
source_group(shrome\\\\mac\\\\English.lproj FILES ${SHROME_RESOURCES_MAC_ENGLISH_LPROJ_SRCS})

set(SHROME_RESOURCES_SRCS
  ${SHROME_RESOURCES_MAC_SRCS}
  ${SHROME_RESOURCES_MAC_ENGLISH_LPROJ_SRCS}
  )


#
# Shared configuration.
#

# Target executable names.
set(CEF_TARGET "shrome")
if(OS_MAC)
  set(CEF_HELPER_TARGET "shrome_Helper")
  set(CEF_HELPER_OUTPUT_NAME "shrome Helper")
else()
  # Logical target used to link the libcef library.
  ADD_LOGICAL_TARGET("libcef_lib" "${CEF_LIB_DEBUG}" "${CEF_LIB_RELEASE}")
endif()

# Determine the target output directory.
SET_CEF_TARGET_OUT_DIR()


#
# Linux configuration.
#

if(OS_LINUX)
  # Executable target.
  add_executable(${CEF_TARGET} ${SHROME_SRCS})
  SET_EXECUTABLE_TARGET_PROPERTIES(${CEF_TARGET})
  add_dependencies(${CEF_TARGET} libcef_dll_wrapper)
  target_link_libraries(${CEF_TARGET} libcef_lib libcef_dll_wrapper ${CEF_STANDARD_LIBS})

  # Set rpath so that libraries can be placed next to the executable.
  set_target_properties(${CEF_TARGET} PROPERTIES INSTALL_RPATH "$ORIGIN")
  set_target_properties(${CEF_TARGET} PROPERTIES BUILD_WITH_INSTALL_RPATH TRUE)
  set_target_properties(${CEF_TARGET} PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CEF_TARGET_OUT_DIR})

  # Copy binary and resource files to the target output directory.
  COPY_FILES("${CEF_TARGET}" "${CEF_BINARY_FILES}" "${CEF_BINARY_DIR}" "${CEF_TARGET_OUT_DIR}")
  COPY_FILES("${CEF_TARGET}" "${CEF_RESOURCE_FILES}" "${CEF_RESOURCE_DIR}" "${CEF_TARGET_OUT_DIR}")
  if (EXISTS "${CEF_BINARY_DIR}/libminigbm.so")
    COPY_FILES("${CEF_TARGET}" "libminigbm.so" "${CEF_BINARY_DIR}" "${CEF_TARGET_OUT_DIR}")
  endif()

  # Set SUID permissions on the chrome-sandbox target.
  SET_LINUX_SUID_PERMISSIONS("${CEF_TARGET}" "${CEF_TARGET_OUT_DIR}/chrome-sandbox")
endif()


#
# Mac OS X configuration.
#

if(OS_MAC)
include(MetalShaderSupport)

execute_process(
    COMMAND xcrun -find metal
    OUTPUT_VARIABLE METAL_COMPILER_PATH
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
)

if(METAL_COMPILER_PATH)
    set(CMAKE_Metal_COMPILER "${METAL_COMPILER_PATH}")
    message(STATUS "Found Metal compiler at: ${CMAKE_Metal_COMPILER}")
else()
    message(WARNING "Could not explicitly find Metal compiler path.")
endif()

check_language(Metal)
if(CMAKE_Metal_COMPILER)
    enable_language(Metal)
    message(STATUS "Metal is supported")
else()
    message(WARNING "Metal is not supported")
endif()

  option(OPTION_USE_ARC "Build with ARC (automatic Reference Counting) on macOS." ON)
  if(OPTION_USE_ARC)
    list(APPEND CEF_COMPILER_FLAGS
      -fobjc-arc
      )
    set_target_properties(${target} PROPERTIES
      CLANG_ENABLE_OBJC_ARC "YES"
      )
  endif()

  # Output path for the main app bundle.
  set(CEF_APP "${CEF_TARGET_OUT_DIR}/${CEF_TARGET}.app")

  # Variables referenced from the main Info.plist file.
  set(EXECUTABLE_NAME "${CEF_TARGET}")
  set(PRODUCT_NAME "${CEF_TARGET}")

string(REPLACE "-Werror" "" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")
string(REPLACE "-Werror" "" CMAKE_C_FLAGS "${CMAKE_C_FLAGS}")

  # Main app bundle target.
  add_executable(${CEF_TARGET} MACOSX_BUNDLE ${SHROME_RESOURCES_SRCS} ${SHROME_SRCS})
  set_target_properties(${CEF_TARGET}  PROPERTIES
    CXX_STANDARD 23
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
    COMPILE_WARNING_AS_ERROR OFF
    XCODE_ATTRIBUTE_GCC_TREAT_WARNINGS_AS_ERRORS OFF
  )
  target_compile_options(${CEF_TARGET}  PRIVATE
    -Wno-unused-variable
 )
  SET_EXECUTABLE_TARGET_PROPERTIES(${CEF_TARGET})
  target_include_directories(${CEF_TARGET} PRIVATE
  ${imgui_SOURCE_DIR}  
  ${imgui_SOURCE_DIR}/backends
  ${metal-cpp_SOURCE_DIR}
  )

  add_dependencies(${CEF_TARGET} libcef_dll_wrapper)

  target_link_libraries(${CEF_TARGET} libcef_dll_wrapper ${CEF_STANDARD_LIBS}
  ${COCOA_FRAMEWORK} ${METAL_FRAMEWORK} ${METALKIT_FRAMEWORK}
  ${QUARTZCORE_FRAMEWORK}
  ${GAMECONTROLLER_FRAMEWORK}
  )
  set_target_properties(${CEF_TARGET} PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/mac/Info.plist.in
  )
if (XCODE)
    set_target_properties( ${CEF_TARGET} PROPERTIES
        XCODE_GENERATE_SCHEME ON
        XCODE_SCHEME_ENABLE_GPU_FRAME_CAPTURE_MODE "Metal"
    )
endif()

add_metal_shader_library(default
    cef.metal
)

target_embed_metal_shader_libraries(${CEF_TARGET} 
    default
)

  # Copy the CEF framework into the Frameworks directory.
  add_custom_command(
    TARGET ${CEF_TARGET}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CEF_BINARY_DIR}/Chromium Embedded Framework.framework"
            "${CEF_APP}/Contents/Frameworks/Chromium Embedded Framework.framework"
    VERBATIM
    )

  # Create the multiple Helper app bundle targets.
  foreach(_suffix_list ${CEF_HELPER_APP_SUFFIXES})
    # Convert to a list and extract the suffix values.
    string(REPLACE ":" ";" _suffix_list ${_suffix_list})
    list(GET _suffix_list 0 _name_suffix)
    list(GET _suffix_list 1 _target_suffix)
    list(GET _suffix_list 2 _plist_suffix)

    # Define Helper target and output names.
    set(_helper_target "${CEF_HELPER_TARGET}${_target_suffix}")
    set(_helper_output_name "${CEF_HELPER_OUTPUT_NAME}${_name_suffix}")

    # Create Helper-specific variants of the helper-Info.plist file. Do this
    # manually because the configure_file command (which is executed as part of
    # MACOSX_BUNDLE_INFO_PLIST) uses global env variables and would insert the
    # wrong values with multiple targets.
    set(_helper_info_plist "${CMAKE_CURRENT_BINARY_DIR}/helper-Info${_target_suffix}.plist")
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/mac/helper-Info.plist.in" _plist_contents)
    string(REPLACE "\${EXECUTABLE_NAME}" "${_helper_output_name}" _plist_contents ${_plist_contents})
    string(REPLACE "\${PRODUCT_NAME}" "${_helper_output_name}" _plist_contents ${_plist_contents})
    string(REPLACE "\${BUNDLE_ID_SUFFIX}" "${_plist_suffix}" _plist_contents ${_plist_contents})
    file(WRITE ${_helper_info_plist} ${_plist_contents})

    # Create Helper executable target.
    add_executable(${_helper_target} MACOSX_BUNDLE ${SHROME_HELPER_SRCS})
    SET_EXECUTABLE_TARGET_PROPERTIES(${_helper_target})
    add_dependencies(${_helper_target} libcef_dll_wrapper)
    target_link_libraries(${_helper_target} libcef_dll_wrapper ${CEF_STANDARD_LIBS})
    set_target_properties(${_helper_target} PROPERTIES
      MACOSX_BUNDLE_INFO_PLIST ${_helper_info_plist}
      OUTPUT_NAME ${_helper_output_name}
      )

    # Add the Helper as a dependency of the main executable target.
    add_dependencies(${CEF_TARGET} "${_helper_target}")

    # Copy the Helper app bundle into the Frameworks directory.
    add_custom_command(
      TARGET ${CEF_TARGET}
      POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_directory
              "${CEF_TARGET_OUT_DIR}/${_helper_output_name}.app"
              "${CEF_APP}/Contents/Frameworks/${_helper_output_name}.app"
      VERBATIM
      )
  endforeach()

  # Manually process and copy over resource files.
  # The Xcode generator can support this via the set_target_properties RESOURCE
  # directive but that doesn't properly handle nested resource directories.
  # Remove these prefixes from input file paths.
  set(PREFIXES "mac/")
  COPY_MAC_RESOURCES("${SHROME_RESOURCES_SRCS}" "${PREFIXES}" "${CEF_TARGET}" "${CMAKE_CURRENT_SOURCE_DIR}" "${CEF_APP}")
endif()


#
# Windows configuration.
#

if(OS_WINDOWS)
  if(USE_SANDBOX)
    # Shared library (DLL) target.
    add_library(${CEF_TARGET} SHARED ${SHROME_SRCS})
    SET_LIBRARY_TARGET_PROPERTIES(${CEF_TARGET})

    # Copy and rename the bootstrap binary.
    COPY_SINGLE_FILE(${CEF_TARGET} ${CEF_BINARY_DIR}/bootstrap.exe ${CEF_TARGET_OUT_DIR}/${CEF_TARGET}.exe)

    if (CMAKE_GENERATOR MATCHES "Visual Studio")
      # Make the bootstrap binary the default command for the Visual Studio debugger.
      set_target_properties(${CEF_TARGET} PROPERTIES
        VS_DEBUGGER_COMMAND "$<TARGET_FILE_DIR:${CEF_TARGET}>/${CEF_TARGET}.exe"
      )
    endif()
  else()
    # Executable target.
    add_executable(${CEF_TARGET} WIN32 ${SHROME_SRCS})
    SET_EXECUTABLE_TARGET_PROPERTIES(${CEF_TARGET})

    # Add the custom manifest files to the executable.
    ADD_WINDOWS_MANIFEST("${CMAKE_CURRENT_SOURCE_DIR}/win" "${CEF_TARGET}" "exe")
  endif()

  add_dependencies(${CEF_TARGET} libcef_dll_wrapper)
  target_link_libraries(${CEF_TARGET} libcef_lib libcef_dll_wrapper ${CEF_STANDARD_LIBS})

  # Copy binary and resource files to the target output directory.
  COPY_FILES("${CEF_TARGET}" "${CEF_BINARY_FILES}" "${CEF_BINARY_DIR}" "${CEF_TARGET_OUT_DIR}")
  COPY_FILES("${CEF_TARGET}" "${CEF_RESOURCE_FILES}" "${CEF_RESOURCE_DIR}" "${CEF_TARGET_OUT_DIR}")

  if(USE_SANDBOX)
    # Set LPAC ACLs required for Windows sandbox support.
    SET_LPAC_ACLS("${CEF_TARGET}")
  endif()
endif()
