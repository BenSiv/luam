#!/bin/bash
set -e

# Compile the C library and objects using the existing Makefile
# We just need to make sure 'all' is built
echo "Building C library..."
cd src
make clean
make o a MYCFLAGS=-DLUA_USE_LINUX
cd ..

# Ensure build directory exists
mkdir -p bin

# Build Odin executable
echo "Building Odin executable..."
# We need to link against the objects/libraries created by the C build
# src/Makefile builds liblua.a and lua.o 
# We need to link lua.o (which now has luam_main) and liblua.a

/home/bensiv/Projects/Odin/odin build odin/src -out:bin/luam_odin -extra-linker-flags:"obj/lua.o obj/liblua.a -ldl -lm -lreadline -rdynamic"

echo "Build complete: bin/luam_odin"

# Run tests
echo "Running tests..."
export LUAM_BIN="./bin/luam_odin"
./bld/test.sh
