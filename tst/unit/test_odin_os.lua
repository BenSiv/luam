-- Verify OS library functions
print("Checking OS library (Odin implemented)...")

-- Check os.clock (should be a number >= 0)
t = os.clock()
print("os.clock():", t)
assert(type(t) == "number", "os.clock did not return a number")
assert(t >= 0, "os.clock returned negative value")

-- Check os.getenv
home = os.getenv("HOME")
print("HOME env var:", home)
assert(type(home) == "string", "os.getenv(HOME) did not return a string")
assert(#home > 0, "os.getenv(HOME) returned empty string")

-- Check os.execute (echo should work)
status = os.execute("echo 'os.execute working'")
print("os.execute status:", status)
assert(status == 0, "os.execute returned non-zero status")

print("OS library verification PASSED!")
