-- load tftpclnt.lua
tftp = require("socket.tftp")

-- needs tftp server running on localhost, with root pointing to
-- a directory with index.html in it

function readfile(file)
   f = io.open(file, "r")
    if not f then return nil end
   a = f.read(f, "*a")
    f.close(f)
    return a
end

host = host or "diego.student.princeton.edu"
retrieved, err = tftp.get("tftp://" .. host .."/index.html")
assert(not err, err)
original = readfile("test/index.html")
assert(original == retrieved, "files differ!")
print("passed")
