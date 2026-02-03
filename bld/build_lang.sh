#!/bin/bash
set -e

VERBOSE=0
for arg in "$@"; do
    case $arg in
        -v|--verbose)
            VERBOSE=1
            break
            ;;
    esac
done

if [ "$VERBOSE" -eq 1 ]; then
    echo "Cleaning build (verbose)"
    make clean V=1
    
    echo "Building with strict checks (verbose)"
    # Use 'ansi' target but override CFLAGS to ensure strict ANSI compliance
    make ansi CFLAGS="-O2 -Wall -ansi -pedantic -DLUA_ANSI" V=1
else
    echo "Cleaning build"
    make clean
    
    echo "Building with strict checks"
    # Use 'ansi' target but override CFLAGS to ensure strict ANSI compliance
    make ansi CFLAGS="-O2 -Wall -ansi -pedantic -DLUA_ANSI"
fi
