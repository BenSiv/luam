#!/bin/bash
# bld/test.sh
# Run the Luam test suite

# Ensure we are in the project root
cd "$(dirname "$0")/.."

export LUA_PATH="lib/?.lua;lib/?/init.lua;tst/?.lua"
export LUA_CPATH="lib/?.so;lib/yaml/?.so;lib/luafilesystem/src/?.so;bld/?.so;;"

# Allow overriding the executable
LUAM_BIN=${LUAM_BIN:-./bin/luam}

echo ">>> Running Unit Tests (Lua) using $LUAM_BIN <<<"
TEST_FILES=$(find tst/unit -name "test_*.lua" -o -name "*_test.lua")
$LUAM_BIN tst/run_all.lua $TEST_FILES
UNIT_EXIT=$?

echo ""
echo ">>> Running REPL Tests (Bash) <<<"
./tst/repl/test_repl.sh
REPL_EXIT=$?

if [ $UNIT_EXIT -eq 0 ] && [ $REPL_EXIT -eq 0 ]; then
    echo ""
    echo ">>> ALL TESTS PASSED <<<"
    exit 0
else
    echo ""
    echo ">>> TESTS FAILED <<<"
    exit 1
fi
