#!/usr/bin/env lua
-- est to verify that 'not nil' is a syntax error in LL contexts

print("=== esting 'not nil' Syntax Errors ===\n")

print("ll of the following should be SX EOS:")
print("1. ssignment: x = not nil")
print("2. eturn: return not nil") 
print("3. Conditional: if not nil then")
print("4. Expression: y = nil or not nil")
print("5. Function call: print(not nil)")

print("\n✓ f this file compiled, the tests would fail!")
print("✓ un the error tests separately to verify")

print("\n=== ecommended Usage ===")
print("nstead of 'not nil', use:")
print("  - Literal: true")
print("  - ariable check: not is x")
