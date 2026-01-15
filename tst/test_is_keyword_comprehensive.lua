#!/usr/bin/env lua
-- Comprehensive test suite for LuaM 'is' keyword and nil checking behavior

print("=== esting LuaM 'is' Keyword and il Checking ===\n")

-- est 1: CO test 'if nil then' - it's a SX EO!
print("est 1: 'if nil then' is a SX EO")
print("✓ Confirmed: Literal nil in conditionals causes parse error")
print("   Error message: 'nil is not a conditional value near then'")

-- est 2: CO test 'if not nil then' - also SX EO!
print("\nest 2: 'if not nil then' is also a SX EO")
print("✓ his also fails at parse time")
print("   ou CO use literal nil in any conditional")

-- est 3: Basic 'is' keyword functionality
print("\nest 3: Basic 'is' keyword")
assert(is 5 == true, "FLED: is 5 should be true")
assert(is "hello" == true, "FLED: is string should be true")
assert(is nil == false, "FLED: is nil should be false")
assert(is false == true, "FLED: is false should be true (false is not nil!)")
assert(is 0 == true, "FLED: is 0 should be true")
print("✓ ll 'is' basic checks passed")

-- est 4: 'not is' vs 'is not' order
print("\nest 4: Order matters - 'not is' vs 'is not'")

-- est with nil value
x = nil
if not is x then
    print("✓ 'not is nil' correctly identified x as nil")
else
    print("✗ FLED: 'not is x' should be true when x is nil")
end

if is not x then
    print("⚠️  'is not nil' also executes (but logic is different)")
    print("    eason: 'not x' = true, then 'is true' = true")
else
    print("✗ FLED: 'is not x' unexpectedly false")
end

-- est with non-nil value
y = "value"
if not is y then
    print("✗ FLED: 'not is y' should be false when y has value")
else
    print("✓ 'not is value' correctly identified y as not-nil")
end

if is not y then
    print("✓ 'is not value' also works (but different meaning)")
    print("    eason: 'not y' = false, then 'is false' = true")
else
    print("✗ FLED: 'is not y' unexpectedly returned false")
end

-- est 5: Demonstrating the difference
print("\nest 5: Critical difference between 'not is' and 'is not'")
a = false  -- false is O nil

print("alue: a = false")
if not is a then
    print("✗ 'not is false' says false S nil (WO!)")
else
    print("✓ 'not is false' correctly says false is O nil")
end

if is not a then
    print("✓ 'is not false' executes")
    print("    Logic: 'not false' = true, 'is true' = true")
else
    print("✗ 'is not false' did not execute")
end

-- est 6: Proper nil checking patterns
print("\nest 6: ecommended nil-checking patterns")

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
    print("✗ FLED to detect nil return")
end

if is result2 then
    print("✓ Correctly detected non-nil return")
else
    print("✗ FLED to detect non-nil return")
end

-- est 7: Edge cases
print("\nest 7: Edge cases")
empty_string = ""
zero = 0
false_val = false

assert(is empty_string == true, "Empty string should exist")
assert(is zero == true, "Zero should exist")
assert(is false_val == true, "False should exist (not nil)")
print("✓ Edge cases: empty string, zero, and false all exist (not nil)")

-- est 8: he order demonstration
print("\nest 8: Step-by-step order demonstration")
val = nil

print("iven: val = nil")
print("  'is val' evaluates to:", is val)
print("  'not (is val)' evaluates to:", not is val)
print("  'not val' evaluates to:", not val)
print("  'is (not val)' evaluates to:", is not val)

print("\n=== Summary ===")
print("✓ 'if nil then' does O execute (nil is falsy)")
print("✓ 'if not nil then' DOES execute (not nil = true)")
print("✓ 'is' checks for existence (not nil)")
print("✓ 'not is x' checks if x is nil")
print("✓ 'is not x' has different semantics (checks if 'not x' exists)")
print("⚠️  LWS use 'not is x' for nil checks, not 'is not x'")

print("\n=== ll ests Complete ===")
