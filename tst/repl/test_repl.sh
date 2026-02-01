#!/bin/bash

LUAM=${LUAM_BIN:-"./bin/luam_odin"}

run_test() {
  local input="$1"
  local expected="$2"
  local name="$3"
  
  echo -n "Test: $name ... "
  output=$(echo -e "$input" | $LUAM -i 2>&1)
  
  if echo "$output" | grep -q "$expected"; then
    echo "PASS"
  else
    echo "FAIL"
    echo "Expected substring: '$expected'"
    echo "Actual output:"
    echo "$output"
    exit 1
  fi
}

echo "Running REPL Tests..."

# 1. Implicit Return
run_test "10+10" "20" "Implicit Return (Expression)"

# 2. Assignment (Should NOT print 'return x=5')
# The user reported 'return x=6' being printed. We expect NO output for assignment, or just prompts.
# We verify that 'x' is set correctly afterwards.
run_test "x=5\nx" "5" "Assignment and Retrieval"

# 3. Implicit Return Error (Leaking 'return ...')
# If we feed an assignment, we should NOT see "return x=5" in the output
input="x=5"
output=$(echo -e "$input" | $LUAM -i 2>&1)
if echo "$output" | grep -q "return x=5"; then
  echo "Test: Clean Output ... FAIL (Found leaked 'return x=5')"
  echo "$output"
  exit 1
else
  echo "Test: Clean Output ... PASS"
fi

# 4. Incomplete Input
run_test "if true then" ">>" "Incomplete Input Prompt"

# 5. Persistence Check (Global assignment in REPL)
run_test "x=6\nx" "6" "Variable Persistence (x=6; x -> 6)"

# 6. Syntax Error
run_test "error('fail')" "fail" "Syntax Error Reporting"

echo "All tests passed!"
