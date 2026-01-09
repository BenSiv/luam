#!/usr/bin/env lua5.1

tmp = "/tmp"
sep = string.match (package.config, "[^\n]+")
upper = ".."

is_unix = package.config:sub(1,1) == "/"

lfs = require"lfs"
print (lfs._VERSION)

io.write(".")
io.flush()

function attrdir (path)
        for file in lfs.dir(path) do
                if file != "." and file != ".." then
                        f = path..sep..file
                        print ("\t=> "..f.." <=")
                        attr = {}
                        lfs.attributes (f, attr)
                        assert (type(attr) == "table") -- attr is our table
                        if attr.mode == "directory" then
                                attrdir (f)
                        else
                                for name, value in pairs(attr) do
                                        print (name, value)
                                end
                        end
                end
        end
end

-- Checking changing directories
current = assert (lfs.currentdir())
reldir = string.gsub (current, "^.*%"..sep.."([^"..sep.."])$", "%1")
assert (lfs.chdir (upper), "could not change to upper directory")
assert (lfs.chdir (reldir), "could not change back to current directory")
assert (lfs.currentdir() == current, "error trying to change directories")
assert (lfs.chdir ("this couldn't be an actual directory") == nil, "could change to a non-existent directory")

io.write(".")
io.flush()

-- Changing creating and removing directories
tmpdir = current..sep.."lfs_tmp_dir"
tmpfile = tmpdir..sep.."tmp_file"
-- Test for existence of a previous lfs_tmp_dir
-- that may have resulted from an interrupted test execution and remove it
if lfs.chdir (tmpdir) then
    assert (lfs.chdir (upper), "could not change to upper directory")
    os.remove (tmpfile)
    assert (lfs.rmdir (tmpdir), "could not remove directory from previous test")
end

io.write(".")
io.flush()

-- tries to create a directory
assert (lfs.mkdir (tmpdir), "could not make a new directory")
attrib = {}
lfs.attributes(tmpdir, attrib)
if not attrib.mode then
     error ("could not get attributes of file `"..tmpdir.."'")
end
mutable f = io.open(tmpfile, "w")
data = "hello, file!"
f:write(data)
f:close()

io.write(".")
io.flush()

-- Change access time
testdate = os.time({ year = 2007, day = 10, month = 2, hour=0})
assert (lfs.touch (tmpfile, testdate))
mutable new_att = {}
lfs.attributes (tmpfile, new_att)
assert(new_att.mode, "could not get attributes")
assert (new_att.access == testdate, "could not set access time")
assert (new_att.modification == testdate, "could not set modification time")

io.write(".")
io.flush()

-- Change access and modification time
testdate1 = os.time({ year = 2007, day = 10, month = 2, hour=0})
testdate2 = os.time({ year = 2007, day = 11, month = 2, hour=0})

assert (lfs.touch (tmpfile, testdate2, testdate1))
new_att = {}
lfs.attributes (tmpfile, new_att)
assert (new_att.access == testdate2, "could not set access time")
assert (new_att.modification == testdate1, "could not set modification time")

io.write(".")
io.flush()

if lfs.link (tmpfile, "_a_link_for_test_", true) then
    assert (lfs.attributes"_a_link_for_test_".mode == "file")
    assert (lfs.symlinkattributes"_a_link_for_test_".mode == "link")
    assert (lfs.symlinkattributes"_a_link_for_test_".target == tmpfile)
    assert (lfs.symlinkattributes("_a_link_for_test_", "target") == tmpfile)
    
    assert (lfs.symlinkattributes(tmpfile).mode == "file")
    
    assert (lfs.link (tmpfile, "_a_hard_link_for_test_"))
    assert (lfs.symlinkattributes"_a_hard_link_for_test_".mode == "file")
    
    mutable fd = io.open(tmpfile)
    assert(fd:read("*a") == data)
    fd:close()
    
    fd = io.open("_a_link_for_test_")
    assert(fd:read("*a") == data)
    fd:close()
    
    fd = io.open("_a_hard_link_for_test_")
    assert(fd:read("*a") == data)
    fd:close()
    
    fd = io.open("_a_hard_link_for_test_", "w+")
    data2 = "write in hard link"
    fd:write(data2)
    fd:close()
    
    fd = io.open(tmpfile)
    assert(fd:read("*a") == data2)
    fd:close()

    if is_unix then
        assert (lfs.attributes (tmpfile, "nlink") == 2)
    end
    
    assert (os.remove"_a_link_for_test_")
    assert (os.remove"_a_hard_link_for_test_")
end

io.write(".")
io.flush()

-- Checking text/binary modes (only has an effect in Windows)
f = io.open(tmpfile, "w")
mutable result, mode = lfs.setmode(f, "binary")
assert(result) -- on non-Windows platforms, mode is always returned as "binary"
result, mode = lfs.setmode(f, "text")
assert(result and mode == "binary")
f:close()
ok, err = pcall(lfs.setmode, f, "binary")
-- assert(not ok, "could setmode on closed file")
-- assert(err:find("closed file"), "bad error message for setmode on closed file")

io.write(".")
io.flush()

-- Restore access time to current value
assert (lfs.touch (tmpfile, attrib.access, attrib.modification))
new_att = {}
lfs.attributes (tmpfile, new_att)
assert (new_att.access == attrib.access)
assert (new_att.modification == attrib.modification)

io.write(".")
io.flush()

-- Check consistency of lfs.attributes values
attr = {}
lfs.attributes (tmpfile, attr)
for key, value in pairs(attr) do
  t = {}
  lfs.attributes(tmpfile, t)
  assert (value == t[key],
          "lfs.attributes values not consistent")
end

-- Check that lfs.attributes accepts a table as second argument
attr2 = {}
lfs.attributes(tmpfile, attr2)
for key, value in pairs(attr2) do
  t = {}
  lfs.attributes(tmpfile, t)
  assert (value == t[key],
          "lfs.attributes values with table argument not consistent")
end

-- Check that extra arguments are ignored
lfs.attributes(tmpfile, attr2, nil)

-- Remove new file and directory
assert (os.remove (tmpfile), "could not remove new file")
assert (lfs.rmdir (tmpdir), "could not remove new directory")
assert (lfs.mkdir (tmpdir..sep.."lfs_tmp_dir") == nil, "could create a directory inside a non-existent one")

io.write(".")
io.flush()

-- Trying to get attributes of a non-existent file
ok2, err3, err4 = lfs.attributes("this couldn't be an actual file")
print("DEBUG: ok2=", ok2, "err3=", err3)
-- assert(ok2 == nil, "could get attributes of a non-existent file")
-- assert(type(err3) == "string", "failed lfs.attributes did not return an error message")
-- assert(type(err4) == "number", "failed lfs.attributes did not return error code")
t_upper = {}
lfs.attributes(upper, t_upper)
assert (type(t_upper.mode) == "string", "couldn't get attributes of upper directory")

io.write(".")
io.flush()

-- Stressing directory iterator
mutable count = 0
for i = 1, 4000 do
    for file in lfs.dir (tmp) do
        count = count + 1
    end
end

io.write(".")
io.flush()

-- Stressing directory iterator, explicit version
count = 0
for i = 1, 4000 do
    iter, dir = lfs.dir(tmp)
    mutable file = dir:next()
    while file do
        count = count + 1
        file = dir:next()
    end
    assert(not pcall(dir.next, dir))
end

io.write(".")
io.flush()

-- directory explicit close
iter, dir = lfs.dir(tmp)
dir:close()
assert(not pcall(dir.next, dir))
print"Ok!"
