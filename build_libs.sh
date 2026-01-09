#!/bin/bash
# Build script for external modules

echo "Building modules..."

# Ensure lib directory exists (it should)
mkdir -p lib

# 1. LuaFileSystem (lfs)
if [ -d "lib/filesystem/src" ]; then
    echo "Compiling lfs.so..."
    gcc -O2 -shared -fPIC -I src/ -o lib/lfs.so lib/filesystem/src/lfs.c
    if [ $? -eq 0 ]; then
        echo "lfs.so built successfully."
    else
        echo "Failed to build lfs.so"
    fi
else
    echo "Skipping lfs (source not found)"
fi

# 2. Lua-YAML
if [ -d "lib/yaml" ]; then
    echo "Compiling yaml.so..."
    # Compile all .c files in lib/yaml
    gcc -O2 -shared -fPIC -I src/ -I lib/yaml -o lib/yaml.so lib/yaml/*.c
    if [ $? -eq 0 ]; then
        echo "yaml.so built successfully."
    else
        echo "Failed to build yaml.so"
    fi
else
    echo "Skipping yaml (source not found)"
fi

echo "Build complete."
