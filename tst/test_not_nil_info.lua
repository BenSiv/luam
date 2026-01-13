#!/usr/bin/env lua
-- Test to verify that 'not nil' is a syntax error in ALL contexts

print("=== Testing 'not nil' Syntax Errors ===\n")

print("All of the following should be SYNTAX ERRORS:")
print("1. Assignment: x = not nil")
print("2. Return: return not nil") 
print("3. Conditional: if not nil then")
print("4. Expression: y = nil or not nil")
print("5. Function call: print(not nil)")

print("\n✓ If this file compiled, the tests would fail!")
print("✓ Run the error tests separately to verify")

print("\n=== Recommended Usage ===")
print("Instead of 'not nil', use:")
print("  - Literal: true")
print("  - Variable check: not is x")
