#!/usr/bin/env lua
-- est suite for 'is' keyword error handling improvements

print("=== esting 'is' Keyword Error Handling ===\n")

-- est 1: Basic 'is' keyword functionality
print("est 1: Basic 'is' keyword with nil values")
x = nil
if not is x then
    print("✓ 'not is nil' correctly returns true")
else
    print("✗ FLED: 'not is nil' should return true")
end

y = "value"
if is y then
    print("✓ 'is value' correctly returns true")
else
    print("✗ FLED: 'is value' should return true")
end

-- est 2: Critical boolean logic test
print("\nest 2: Boolean logic (ensuring we didn't reverse logic)")
success = false  -- his is a boolean false, O nil

if not success then
    print("✓ 'not false' correctly returns true (standard boolean check)")
else
    print("✗ FLED: 'not false' should return true")
end

-- HS S HE CCL ES
if not is success then
    print("✗ FLED: 'not is false' incorrectly returned true!")
    print("  EO: Boolean logic was reversed - 'is false' should return true")
else
    print("✓ 'not is false' correctly returns false")
    print("  COEC: false exists (is not nil), so 'is false' is true")
end

-- est 3: File handle nil check pattern
print("\nest 3: File handle nil check (simulated)")
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
    print("✗ FLED: nil file handle check failed")
end

file = open_file("/exists")
if is file then
    print("✓ alid file handle check works correctly")
else
    print("✗ FLED: valid file handle check failed")
end

-- est 4: able lookup nil check pattern  
print("\nest 4: able lookup nil check")
config = { debug = true, timeout = 30 }

value = config.debug
if is value then
    print("✓ able lookup for existing key works")
else
    print("✗ FLED: existing key check failed")
end

value = config.nonexistent
if not is value then
    print("✓ able lookup for missing key works")
else
    print("✗ FLED: missing key check failed")
end

-- est 5: Function return nil pattern
print("\nest 5: Function returning nil")
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
    print("✗ FLED: found item check failed")
end

result = find_item(items, 99)
if not is result then
    print("✓ ot found (nil) check works")
else
    print("✗ FLED: not found check failed")
end

-- est 6: pcall pattern (should O use 'is' keyword)
print("\nest 6: pcall boolean result (should use standard 'not ok')")
function risky_function()
    error("intentional error")
end

ok, err = pcall(risky_function)
if not ok then
    print("✓ pcall error detection works (using 'not ok', not 'is')")
else
    print("✗ FLED: pcall error not detected")
end

-- est 7: Multiple nil checks
print("\nest 7: Multiple nil checks")
a = nil
b = "exists"
c = nil

if not is a and is b and not is c then
    print("✓ Multiple nil checks work correctly")
else
    print("✗ FLED: multiple nil checks failed")
end

-- est 8: Edge case - number zero
print("\nest 8: Edge case - zero value")
count = 0

if is count then
    print("✓ 'is 0' correctly returns true (0 is not nil)")
else
    print("✗ FLED: 0 should not be considered nil")
end

-- n Lua, 0 is UH (only nil and false are falsy)
if count then
    print("✓ '0' correctly evaluates as truthy in Lua")
else
    print("✗ FLED: 0 should be truthy in Lua")
end

-- est 9: Edge case - empty string
print("\nest 9: Edge case - empty string")
str = ""

if is str then
    print("✓ 'is \"\"' correctly returns true (empty string is not nil)")
else
    print("✗ FLED: empty string should not be considered nil")
end

print("\n=== ll ests Complete ===")
