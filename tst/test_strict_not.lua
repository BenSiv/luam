#!/usr/bin/env lua
-- Test for strict 'not' operator (flag/boolean only)

print("=== Testing Strict 'not' Operator ===\n")

-- Test 1: not with booleans (SHOULD WORK)
print("Test 1: 'not' with boolean values")
print("  not true  =", not true)   -- false
print("  not false =", not false)  -- true
print("✓ Boolean operations work\n")

-- Helper to check compile-time error
function assert_compile_error(code, expected_msg)
    f, e = loadstring(code)
    if f then
        print("✗ Expected compile error for: " .. code .. ", but got success")
        os.exit(1)
    else
        -- Lua 5.1 loadstring error format: [string "code"]:1: error
        if string.find(e, expected_msg, 1, true) then
            print("✓ Correctly rejected: " .. code)
        else
            print("✗ Wrong error message for: " .. code)
            print("  Got: " .. e)
            print("  Expected: " .. expected_msg)
            os.exit(1)
        end
    end
end

-- Helper to check runtime error
function assert_runtime_error(f_run, expected_msg)
    status, e = pcall(f_run)
    if status then
        print("✗ Expected runtime error, but got success")
        os.exit(1)
    else
        if string.find(e, expected_msg, 1, true) then
            print("✓ Correctly verified runtime error")
        else
            print("✗ Wrong runtime error message")
            print("  Got: " .. e)
            print("  Expected: " .. expected_msg)
            os.exit(1)
        end
    end
end

-- Test 2: not with nil inputs (Compile Time)
print("\nTest 2: 'not nil' (Compile Time)")
assert_compile_error("print(not nil)", "'not' requires a boolean value, got nil")

-- Test 3: not with literals (Compile Time)
print("\nTest 3: 'not 5' and 'not \"string\"' (Compile Time)")
assert_compile_error("print(not 5)", "'not' requires a boolean value, got number")
assert_compile_error("print(not 'test')", "'not' requires a boolean value, got constant")

-- Test 4: not with variables (Runtime)
print("\nTest 4: Variables (Runtime)")
assert_runtime_error(function()
    x = 5
    y = not x
end, "'not' operator requires a boolean value, got number")

assert_runtime_error(function()
    x = nil
    -- Note: 'not x' where x is nil works like 'not nil' at runtime if not optimized?
    -- Actually 'not x' compiles to OP_NOT. Runtime check for NIL in OP_NOT should error.
    y = not x
end, "'not' operator requires a boolean value, got nil")

-- Test 5: What to use instead
print("\n=== Correct Patterns ===")

-- Instead of 'not x' for nil check, use 'not is x'
x = nil
if not is x then
    print("✓ Use 'not is x' to check if x is nil")
end

-- For boolean operations, use actual booleans
function returns_bool()
    return true
end

result = returns_bool()
if not result then
    print("This won't execute")
else
    print("✓ Use 'not' with actual boolean values")
end

-- Convert to boolean if needed (comparison returns boolean)
value = 5
is_zero = (value == 0)  -- This is a boolean
if not is_zero then
    print("✓ Convert to boolean first: (value == 0)")
end

print("\n=== Summary ===")
print("✓ 'not' ONLY works on flag (boolean) types")
print("✓ 'not true' and 'not false' are valid")
print("✗ 'not nil', 'not 0', 'not \"\"' are ALL errors")
print("→ Use 'not is x' to check for nil")
print("→ Use comparisons to get booleans: (x == 0), (x != nil)")
