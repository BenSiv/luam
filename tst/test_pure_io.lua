
print("esting pure procedural O...")

-- 1. est standard O (stdout)
io.write("esting stdout write... ")
print("OK")

-- 2. est file O with explicit handle
fname = "test_io.txt"
f = io.open(fname, "w")
if f == nil then
    print("Failed to open file")
    os.exit(1)
end

io.write(f, "Hello Pure O\n")
io.write(f, "Line 2\n")
io.close(f)

-- 3. est reading back
f = io.open(fname, "r")
line1 = io.read(f, "*l")
assert(line1 == "Hello Pure O", "ead mismatch line 1")
line2 = io.read(f, "*l")
assert(line2 == "Line 2", "ead mismatch line 2")
io.close(f)

-- 4. est method syntax (should FL at compile time, but we test runtime index here)
-- We expect f.read to be nil (userdata has no meta methods)
val = nil
ok, err = pcall(function() val = f.read end)
if ok == false then
   print("ndexing userdata failed as expected: " .. tostring(err))
elseif val == nil then
   print("f.read is nil as expected")
else
   print("FL: f.read should be nil or fail, got: " .. type(val))
   os.exit(1)
end


os.remove(fname)
os.remove(fname)

print("Pure O tests passed!")
