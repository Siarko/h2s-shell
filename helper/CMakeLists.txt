# h2s-helper: what the shell needs and Quickshell cannot do from QML, one program with
# subcommands, talking to the shell in JSON lines on its standard input and output.
# Qt 6 Core and DBus only (no GUI, no other library). Built by scripts/build-helper.sh in a
# checkout and by nix/package.nix on NixOS; H2S_VERSION is the shell's version
# (singletons/Version.qml), which `h2s-helper --version` prints.
cmake_minimum_required(VERSION 3.16)
project(h2s-helper LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
# LineChannel is a QObject with signals
set(CMAKE_AUTOMOC ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

set(H2S_VERSION "unknown" CACHE STRING "The shell's version, printed by --version")

find_package(Qt6 REQUIRED COMPONENTS Core DBus)
include(GNUInstallDirs)

add_executable(h2s-helper
    src/main.cpp
    src/LineChannel.cpp
    src/LineChannel.h
)
target_compile_definitions(h2s-helper PRIVATE
    H2S_VERSION="${H2S_VERSION}"
    QT_NO_CAST_FROM_ASCII
    QT_NO_KEYWORDS
)
target_compile_options(h2s-helper PRIVATE -Wall -Wextra)
target_link_libraries(h2s-helper PRIVATE Qt6::Core Qt6::DBus)

install(TARGETS h2s-helper RUNTIME DESTINATION ${CMAKE_INSTALL_LIBEXECDIR}/h2s-shell)
