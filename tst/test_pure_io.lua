
print("Testing pure procedural IO...")

-- 1. Test standard IO (stdout)
io.write("Testing stdout write... ")
print("OK")

-- 2. Test file IO with explicit handle
fname = "test_io.txt"
f = io.open(fname, "w")
if not f then
    print("Failed to open file")
    os.exit(1)
end

io.write(f, "Hello Pure IO\n")
io.write(f, "Line 2\n")
io.close(f)

-- 3. Test reading back
f = io.open(fname, "r")
line1 = io.read(f, "*l")
assert(line1 == "Hello Pure IO", "Read mismatch line 1")
line2 = io.read(f, "*l")
assert(line2 == "Line 2", "Read mismatch line 2")
io.close(f)

-- 4. Test method syntax (should FAIL at compile time, but we test runtime index here)
-- We expect f.read to be nil (userdata has no meta methods)
val = nil
ok, err = pcall(function() val = f.read end)
if not ok then
   print("Indexing userdata failed as expected: " .. tostring(err))
elseif val == nil then
   print("f.read is nil as expected")
else
   print("FAIL: f.read should be nil or fail, got: " .. type(val))
   os.exit(1)
end


os.remove(fname)
os.remove(fname)

print("Pure IO tests passed!")
