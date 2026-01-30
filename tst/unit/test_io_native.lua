-- tst/unit/test_io_native.lua
-- Native IO library tests for Luam dialect (uses 'const' instead of 'local')

print("Testing native IO library...")

-- Test io.open and file writing
const fname = "test_io_output.txt"
const f, err = io.open(fname, "w")
if f == nil then
    error("Could not open file for writing: " .. tostring(err))
end

io.write(f, "line 1\n")
io.write(f, "line 2\n")
io.close(f)

-- Test io.open and file reading
const f2, err2 = io.open(fname, "r")
if f2 == nil then
    error("Could not open file for reading: " .. tostring(err2))
end

const content1 = io.read(f2, "*l")
const content2 = io.read(f2, "*l")
io.close(f2)

assert(content1 == "line 1", "Read line 1 failed: got " .. tostring(content1))
assert(content2 == "line 2", "Read line 2 failed: got " .. tostring(content2))

-- Test io.lines
const f3 = io.open(fname, "r")
const lines = {}
for line in io.lines(fname) do
    table.insert(lines, line)
end
assert(#lines == 2, "io.lines failed to read 2 lines, got " .. #lines)
assert(lines[1] == "line 1", "io.lines line 1 mismatch")

-- Test io.tmpfile
const tf = io.tmpfile()
assert(io.type(tf) == "file", "tmpfile is not a file handle")
io.write(tf, "tmp content")
io.seek(tf, "set", 0)
const tmp_res = io.read(tf, "*a")
assert(tmp_res == "tmp content", "tmpfile read/write failed")
io.close(tf)

-- Test standard streams
assert(io.type(io.stdin) == "file", "io.stdin is not a file")
assert(io.type(io.stdout) == "file", "io.stdout is not a file")
assert(io.type(io.stderr) == "file", "io.stderr is not a file")

-- Test io.type with closed file
const f4 = io.open(fname, "r")
io.close(f4)
assert(io.type(f4) == "closed file", "io.type failed for closed file")

-- Test io.popen (if available)
const pf = io.popen("echo hello_popen", "r")
if pf != nil then
    const p_res = io.read(pf, "*l")
    assert(string.find(p_res, "hello_popen") != nil, "popen read failed")
    io.close(pf)
    print("popen tested successfully")
end

-- Cleanup
os.remove(fname)

print("Native IO library tests PASSED!")
