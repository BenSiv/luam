print("Testing strict nil conditionals...")

-- Test 1: if false should work
if false then
    print("ERROR: if false entered block")
    os.exit(1)
end
print("PASS: if false works correctly")

-- Test 2: nil or default should work  
x = nil or "default"
assert(x == "default", "Test 2 FAILED")
print("PASS: nil or default works")

-- Test 3: undefined global or default should work
result = undefined_global or 42
assert(result == 42, "Test 3 FAILED")
print("PASS: undefined or default works")

-- Test 4: and with nil  
z = nil and "value"
assert(z == nil, "Test 4 FAILED")
print("PASS: nil and value works")

-- Test 5: is operator for existence check
assert(is 5 == true, "Test 5a FAILED")
assert(is false == true, "Test 5b FAILED")  
assert(is nil == false, "Test 5c FAILED")
assert(is 0 == true, "Test 5d FAILED")
print("PASS: is operator works")

-- Test 6: type renaming
assert(type("hello") == "text", "Test 6a FAILED")
assert(type(true) == "flag", "Test 6b FAILED")
print("PASS: type renaming works")

print("\n✅ All tests passed!")
print("\nNote: Strict nil checks tested manually:")
print("  - 'if nil' errors at parse time")
print("  - 'if nil_variable' errors at runtime")
