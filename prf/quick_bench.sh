#!/bin/bash
# Quick Benchmark Runner
# Compares Odin implementation vs standard Lua 5.1

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/.."

echo "==================================================="
echo "  LuaM Benchmark: Odin vs C Implementation"
echo "==================================================="
echo ""

# Run Odin implementation
echo "Running Odin implementation..."
echo "---------------------------------------------------"
bin/luam_odin prf/bench_luam.lua 2>&1 | grep -v "^DEBUG:"
echo ""

# Run C implementation (using system lua5.1)
echo "Running C implementation (lua5.1)..."
echo "---------------------------------------------------"
lua5.1 prf/bench_lua51.lua
echo ""

echo "==================================================="
echo "  Benchmark Complete"
echo "==================================================="
