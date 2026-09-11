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

# The Rust staticlib is not linked here. metadata.json#codegen.rust has the
# builder compile rust-lib/ into lib/libchat_module.a and link it into every
# shape this module builds, each the way that shape needs: plainly into the Qt
# plugin (re-mentioning logos-protocol after it, so single-pass linkers see the
# archive the Rust code's lp_* undefineds resolve against), and whole-archived
# into the Bare module (no Qt glue references the module-impl exports there, so
# nothing would pull the members in). The per-platform link tail — CoreFoundation
# and Security on Apple, pthread/dl elsewhere, and the Windows and Android cases
# — comes from the builder too.
