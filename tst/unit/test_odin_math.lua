-- Verify math library functions
print("Checking math library (Odin implemented)...")

assert(math.pi, "math.pi missing")
assert(math.huge, "math.huge missing")
print("math.pi:", math.pi)
print("math.huge:", math.huge)

-- Check some functions
assert(math.abs(-10) == 10, "math.abs failed")
assert(math.floor(3.7) == 3, "math.floor failed")
assert(math.ceil(3.2) == 4, "math.ceil failed")

-- Trig
val = math.sin(math.pi/2)
print("sin(pi/2):", val)
assert(math.abs(val - 1) < 0.0001, "math.sin failed")

print("Math library verification PASSED!")
