#!/usr/bin/env lua
-- Test suite for 'is' keyword error handling improvements

print("=== Testing 'is' Keyword Error Handling ===\n")

-- Test 1: Basic 'is' keyword functionality
print("Test 1: Basic 'is' keyword with nil values")
x = nil
if not is x then
    print("✓ 'not is nil' correctly returns true")
else
    print("✗ FAILED: 'not is nil' should return true")
end

y = "value"
if is y then
    print("✓ 'is value' correctly returns true")
else
    print("✗ FAILED: 'is value' should return true")
end

-- Test 2: Critical boolean logic test
print("\nTest 2: Boolean logic (ensuring we didn't reverse logic)")
success = false  -- This is a boolean false, NOT nil

if not success then
    print("✓ 'not false' correctly returns true (standard boolean check)")
else
    print("✗ FAILED: 'not false' should return true")
end

-- THIS IS THE CRITICAL TEST
if not is success then
    print("✗ FAILED: 'not is false' incorrectly returned true!")
    print("  ERROR: Boolean logic was reversed - 'is false' should return true")
else
    print("✓ 'not is false' correctly returns false")
    print("  CORRECT: false exists (is not nil), so 'is false' is true")
end

-- Test 3: File handle nil check pattern
print("\nTest 3: File handle nil check (simulated)")
function open_file(path)
    if path == "/nonexistent" then
        return nil
    else
        return { name = path, data = "content" }
    end
end

file = open_file("/nonexistent")
if not is file then
    print("✓ File handle nil check works correctly")
else
    print("✗ FAILED: nil file handle check failed")
end

file = open_file("/exists")
if is file then
    print("✓ Valid file handle check works correctly")
else
    print("✗ FAILED: valid file handle check failed")
end

-- Test 4: Table lookup nil check pattern  
print("\nTest 4: Table lookup nil check")
config = { debug = true, timeout = 30 }

value = config.debug
if is value then
    print("✓ Table lookup for existing key works")
else
    print("✗ FAILED: existing key check failed")
end

value = config.nonexistent
if not is value then
    print("✓ Table lookup for missing key works")
else
    print("✗ FAILED: missing key check failed")
end

-- Test 5: Function return nil pattern
print("\nTest 5: Function returning nil")
function find_item(tbl, val)
    for _,v in pairs(tbl) do
        if v == val then return v end
    end
    return nil
end

items = {10, 20, 30}
result = find_item(items, 20)
if is result then
    print("✓ Found item check works")
else
    print("✗ FAILED: found item check failed")
end

result = find_item(items, 99)
if not is result then
    print("✓ Not found (nil) check works")
else
    print("✗ FAILED: not found check failed")
end

-- Test 6: pcall pattern (should NOT use 'is' keyword)
print("\nTest 6: pcall boolean result (should use standard 'not ok')")
function risky_function()
    error("intentional error")
end

ok, err = pcall(risky_function)
if not ok then
    print("✓ pcall error detection works (using 'not ok', not 'is')")
else
    print("✗ FAILED: pcall error not detected")
end

-- Test 7: Multiple nil checks
print("\nTest 7: Multiple nil checks")
a = nil
b = "exists"
c = nil

if not is a and is b and not is c then
    print("✓ Multiple nil checks work correctly")
else
    print("✗ FAILED: multiple nil checks failed")
end

-- Test 8: Edge case - number zero
print("\nTest 8: Edge case - zero value")
count = 0

if is count then
    print("✓ 'is 0' correctly returns true (0 is not nil)")
else
    print("✗ FAILED: 0 should not be considered nil")
end

-- In Lua, 0 is TRUTHY (only nil and false are falsy)
if count then
    print("✓ '0' correctly evaluates as truthy in Lua")
else
    print("✗ FAILED: 0 should be truthy in Lua")
end

-- Test 9: Edge case - empty string
print("\nTest 9: Edge case - empty string")
str = ""

if is str then
    print("✓ 'is \"\"' correctly returns true (empty string is not nil)")
else
    print("✗ FAILED: empty string should not be considered nil")
end

print("\n=== All Tests Complete ===")
