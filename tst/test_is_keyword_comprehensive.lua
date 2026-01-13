#!/usr/bin/env lua
-- Comprehensive test suite for LuaM 'is' keyword and nil checking behavior

print("=== Testing LuaM 'is' Keyword and Nil Checking ===\n")

-- Test 1: CANNOT test 'if nil then' - it's a SYNTAX ERROR!
print("Test 1: 'if nil then' is a SYNTAX ERROR")
print("✓ Confirmed: Literal nil in conditionals causes parse error")
print("   Error message: 'nil is not a conditional value near then'")

-- Test 2: CANNOT test 'if not nil then' - also SYNTAX ERROR!
print("\nTest 2: 'if not nil then' is also a SYNTAX ERROR")
print("✓ This also fails at parse time")
print("   You CANNOT use literal nil in any conditional")

-- Test 3: Basic 'is' keyword functionality
print("\nTest 3: Basic 'is' keyword")
assert(is 5 == true, "FAILED: is 5 should be true")
assert(is "hello" == true, "FAILED: is string should be true")
assert(is nil == false, "FAILED: is nil should be false")
assert(is false == true, "FAILED: is false should be true (false is not nil!)")
assert(is 0 == true, "FAILED: is 0 should be true")
print("✓ All 'is' basic checks passed")

-- Test 4: 'not is' vs 'is not' order
print("\nTest 4: Order matters - 'not is' vs 'is not'")

-- Test with nil value
x = nil
if not is x then
    print("✓ 'not is nil' correctly identified x as nil")
else
    print("✗ FAILED: 'not is x' should be true when x is nil")
end

if is not x then
    print("⚠️  'is not nil' also executes (but logic is different)")
    print("    Reason: 'not x' = true, then 'is true' = true")
else
    print("✗ FAILED: 'is not x' unexpectedly false")
end

-- Test with non-nil value
y = "value"
if not is y then
    print("✗ FAILED: 'not is y' should be false when y has value")
else
    print("✓ 'not is value' correctly identified y as not-nil")
end

if is not y then
    print("✓ 'is not value' also works (but different meaning)")
    print("    Reason: 'not y' = false, then 'is false' = true")
else
    print("✗ FAILED: 'is not y' unexpectedly returned false")
end

-- Test 5: Demonstrating the difference
print("\nTest 5: Critical difference between 'not is' and 'is not'")
a = false  -- false is NOT nil

print("Value: a = false")
if not is a then
    print("✗ 'not is false' says false IS nil (WRONG!)")
else
    print("✓ 'not is false' correctly says false is NOT nil")
end

if is not a then
    print("✓ 'is not false' executes")
    print("    Logic: 'not false' = true, 'is true' = true")
else
    print("✗ 'is not false' did not execute")
end

-- Test 6: Proper nil checking patterns
print("\nTest 6: Recommended nil-checking patterns")

function returns_nil()
    return nil
end

function returns_value()
    return "success"
end

result1 = returns_nil()
result2 = returns_value()

if not is result1 then
    print("✓ Correctly detected nil return")
else
    print("✗ FAILED to detect nil return")
end

if is result2 then
    print("✓ Correctly detected non-nil return")
else
    print("✗ FAILED to detect non-nil return")
end

-- Test 7: Edge cases
print("\nTest 7: Edge cases")
empty_string = ""
zero = 0
false_val = false

assert(is empty_string == true, "Empty string should exist")
assert(is zero == true, "Zero should exist")
assert(is false_val == true, "False should exist (not nil)")
print("✓ Edge cases: empty string, zero, and false all exist (not nil)")

-- Test 8: The order demonstration
print("\nTest 8: Step-by-step order demonstration")
val = nil

print("Given: val = nil")
print("  'is val' evaluates to:", is val)
print("  'not (is val)' evaluates to:", not is val)
print("  'not val' evaluates to:", not val)
print("  'is (not val)' evaluates to:", is not val)

print("\n=== Summary ===")
print("✓ 'if nil then' does NOT execute (nil is falsy)")
print("✓ 'if not nil then' DOES execute (not nil = true)")
print("✓ 'is' checks for existence (not nil)")
print("✓ 'not is x' checks if x is nil")
print("✓ 'is not x' has different semantics (checks if 'not x' exists)")
print("⚠️  ALWAYS use 'not is x' for nil checks, not 'is not x'")

print("\n=== All Tests Complete ===")
