#!/bin/bash
set -e

echo "Cleaning build..."
make clean

echo "Building with S checks..."
# Use 'ansi' target but override CFLS to ensure strict S compliance
make ansi CFLS="-O2 -Wall -ansi -pedantic -DLU_S"
