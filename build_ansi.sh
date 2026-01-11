#!/bin/bash
set -e

echo "Cleaning build..."
make clean

echo "Building with ANSI checks..."
# Use 'ansi' target but override CFLAGS to ensure strict ANSI compliance
make ansi CFLAGS="-O2 -Wall -ansi -pedantic -DLUA_ANSI"
