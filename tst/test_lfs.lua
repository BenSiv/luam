#!/usr/bin/env lua5.1

tmp = "/tmp"
sep = string.match (package.config, "[^\n]+")
upper = ".."

is_unix = string.sub(package.config, 1, 1) == "/"

    print("esting lfs...")
    status, lfs = pcall(require, "lfs")
    if status == false then
        print("Skipping test_lfs.lua: " .. tostring(lfs))
        return
    end
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
-- est for existence of a previous lfs_tmp_dir
-- that may have resulted from an interrupted test execution and remove it
ok = lfs.chdir (tmpdir)
if ok then
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
if attrib.mode == nil then
     error ("could not get attributes of file `"..tmpdir.."'")
end
f = io.open(tmpfile, "w")
data = "hello, file!"
io.write(f, data)
io.close(f)

io.write(".")
io.flush()

-- Change access time
testdate = os.time({ year = 2007, day = 10, month = 2, hour=0})
assert (lfs.touch (tmpfile, testdate))
new_att = {}
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

link_ok = lfs.link (tmpfile, "_a_link_for_test_", true)
if link_ok then
    assert (lfs.attributes"_a_link_for_test_".mode == "file")
    assert (lfs.symlinkattributes"_a_link_for_test_".mode == "link")
    assert (lfs.symlinkattributes"_a_link_for_test_".target == tmpfile)
    assert (lfs.symlinkattributes("_a_link_for_test_", "target") == tmpfile)
    
    assert (lfs.symlinkattributes(tmpfile).mode == "file")
    
    assert (lfs.link (tmpfile, "_a_hard_link_for_test_"))
    assert (lfs.symlinkattributes"_a_hard_link_for_test_".mode == "file")
    
    fd = io.open(tmpfile)
    assert(io.read(fd, "*a") == data)
    io.close(fd)
    
    fd = io.open("_a_link_for_test_")
    assert(io.read(fd, "*a") == data)
    io.close(fd)
    
    fd = io.open("_a_hard_link_for_test_")
    assert(io.read(fd, "*a") == data)
    io.close(fd)
    
    fd = io.open("_a_hard_link_for_test_", "w+")
    data2 = "write in hard link"
    io.write(fd, data2)
    io.close(fd)
    
    fd = io.open(tmpfile)
    assert(io.read(fd, "*a") == data2)
    io.close(fd)

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
result, mode = lfs.setmode(f, "binary")
assert(result) -- on non-Windows platforms, mode is always returned as "binary"
result, mode = lfs.setmode(f, "text")
assert(result and mode == "binary")
io.close(f)
ok, err = pcall(lfs.setmode, f, "binary")
-- assert(not ok, "could setmode on closed file")
-- assert(string.find(err, "closed file"), "bad error message for setmode on closed file")

io.write(".")
io.flush()

-- estore access time to current value
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

-- emove new file and directory
assert (os.remove (tmpfile), "could not remove new file")
assert (lfs.rmdir (tmpdir), "could not remove new directory")
assert (lfs.mkdir (tmpdir..sep.."lfs_tmp_dir") == nil, "could create a directory inside a non-existent one")

io.write(".")
io.flush()

-- rying to get attributes of a non-existent file
ok2, err3, err4 = lfs.attributes("this couldn't be an actual file")
print("DEBU: ok2=", ok2, "err3=", err3)
-- assert(ok2 == nil, "could get attributes of a non-existent file")
-- assert(type(err3) == "string", "failed lfs.attributes did not return an error message")
-- assert(type(err4) == "number", "failed lfs.attributes did not return error code")
t_upper = {}
lfs.attributes(upper, t_upper)
assert (type(t_upper.mode) == "string", "couldn't get attributes of upper directory")

io.write(".")
io.flush()

-- Stressing directory iterator
count = 0
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
    file = dir.next(dir)
    while file do
        count = count + 1
        file = dir.next(dir)
    end
    assert(not pcall(dir.next, dir))
end

io.write(".")
io.flush()

-- directory explicit close
iter, dir = lfs.dir(tmp)
dir.close(dir)
assert(not pcall(dir.next, dir))
print"Ok!"
