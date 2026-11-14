cmake_minimum_required(VERSION 3.16)
project(essentia_tempo_engine LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_path(ESSENTIA_INCLUDE_DIR essentia/algorithmfactory.h
  PATH_SUFFIXES essentia)
find_library(ESSENTIA_LIBRARY NAMES essentia)

if(NOT ESSENTIA_INCLUDE_DIR OR NOT ESSENTIA_LIBRARY)
  message(FATAL_ERROR "Essentia C++ development library not found. Build/install Essentia first, then set ESSENTIA_INCLUDE_DIR and ESSENTIA_LIBRARY.")
endif()

add_executable(essentia_tempo src/tempo_engine.cpp)
target_include_directories(essentia_tempo PRIVATE ${ESSENTIA_INCLUDE_DIR})
target_link_libraries(essentia_tempo PRIVATE ${ESSENTIA_LIBRARY})
target_compile_options(essentia_tempo PRIVATE -O2 -Wall -Wextra -Wpedantic)
