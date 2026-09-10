cmake_minimum_required(VERSION 3.14)
project(ChatModulePlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. LOGOS_MODULE_BUILDER_ROOT is not set.")
endif()

configure_file(${CMAKE_CURRENT_SOURCE_DIR}/metadata.json
               ${CMAKE_CURRENT_BINARY_DIR}/metadata.json COPYONLY)

logos_module(
    NAME chat_module
)

# The Rust staticlib is NOT linked here. metadata.json#codegen.rust makes the
# builder compile rust-lib to lib/libchat_module.a and link it -- into the Qt
# plugin AND into the Bare artifact, each the way that shape needs (the plugin
# links it plainly and re-mentions logos-protocol after it; the Bare module
# whole-archives it, because there is no Qt glue to reference the module-impl
# exports and nothing would pull the members in). The hand-rolled
# find_library + target_link_libraries block that used to live here named
# `chat_module_module_plugin` unconditionally, and under LOGOS_MODULE_BARE that
# target does not exist -- `logos_module()` returns after building the Bare
# library -- so `nix build .#bare` failed at configure time with "Cannot specify
# link libraries for target ... which is not built by this project". The
# per-platform tail (CoreFoundation/Security, pthread/dl) is the builder's too,
# and it knows Windows and Android, which this file did not.
