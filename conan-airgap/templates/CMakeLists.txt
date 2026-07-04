cmake_minimum_required(VERSION 3.20)
project(devkit_conan_example CXX)

# find_package resolves against the CMakeDeps files Conan generated from the
# air-gapped cache — no network, no system packages.
find_package(fmt REQUIRED)

add_executable(app main.cpp)
target_link_libraries(app PRIVATE fmt::fmt)
target_compile_features(app PRIVATE cxx_std_17)
