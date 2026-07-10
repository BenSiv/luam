socket = require("socket")
ftp = require("socket.ftp")
url = require("socket.url")
ltn12 = require("ltn12")

-- use dscl to create user "luasocket" with password "password"
-- with home in /Users/diego/luasocket/test/ftp
-- with group com.apple.access_ftp
-- with shell set to /sbin/nologin
-- set /etc/ftpchroot to chroot luasocket
-- must set group com.apple.access_ftp on user _ftp (for anonymous access)
-- copy index.html to /var/empty/pub (home of user ftp)
-- start ftp server with
-- sudo -s launchctl load -w /System/Library/LaunchDaemons/ftp.plist
-- copy index.html to /Users/diego/luasocket/test/ftp
-- stop with
-- sudo -s launchctl unload -w /System/Library/LaunchDaemons/ftp.plist

-- override protection to make sure we see all errors
--socket.protect = function(s) return s end

dofile("testsupport.lua")

host = host
if host == nil then
    host = "localhost"
end
port, index_file, index, back, err, ret = nil

t = socket.gettime()

index_file = "index.html"

-- a function that returns a directory listing
function nlst(u)
   t = {}
   p = url.parse(u)
    p.command = "nlst"
    p.sink = ltn12.sink.table(t)
   r, e = ftp.get(p)
    result = nil
    if r != nil and r != false then
        result = table.concat(t)
    end
    return result, e
end

-- function that removes a remote file
function dele(u)
   p = url.parse(u)
    p.command = "dele"
    p.argument = string.gsub(p.path, "^/", "")
    if (p.argumet == "") then p.argument = nil end
    p.check = 250
    return ftp.command(p)
end

-- read index with CRLF convention
index = readfile(index_file)

io.write("testing wrong scheme: ")
back, err = ftp.get("wrong://banana.com/lixo")
assert((back == nil or back == false) and err == "wrong scheme 'wrong'", err)
print("ok")

io.write("testing invalid url: ")
back, err = ftp.get("localhost/dir1/index.html;type=i")
assert((back == nil or back == false) and err != nil and err != false)
print("ok")

io.write("testing anonymous file download: ")
back, err = socket.ftp.get("ftp://" .. host .. "/pub/index.html;type=i")
assert((err == nil or err == false) and back == index, err)
print("ok")

io.write("erasing before upload: ")
ret, err = dele("ftp://luasocket:password@" .. host .. "/index.up.html")
if ((ret == nil or ret == false)) then print(err)
else print("ok") end

io.write("testing upload: ")
ret, err = ftp.put("ftp://luasocket:password@" .. host .. "/index.up.html;type=i", index)
assert(ret != nil and ret != false and (err == nil or err == false), err)
print("ok")

io.write("downloading uploaded file: ")
back, err = ftp.get("ftp://luasocket:password@" .. host .. "/index.up.html;type=i")
assert(ret != nil and ret != false and (err == nil or err == false) and index == back, err)
print("ok")

io.write("erasing after upload/download: ")
ret, err = dele("ftp://luasocket:password@" .. host .. "/index.up.html")
assert(ret != nil and ret != false and (err == nil or err == false), err)
print("ok")

io.write("testing weird-character translation: ")
back, err = ftp.get("ftp://luasocket:password@" .. host .. "/%23%3f;type=i")
assert((err == nil or err == false) and back == index, err)
print("ok")

io.write("testing parameter overriding: ")
back = {}
ret, err = ftp.get({
    url = "//stupid:mistake@" .. host .. "/index.html",
    user = "luasocket",
    password = "password",
    type = "i",
    sink = ltn12.sink.table(back)
})
assert(ret != nil and ret != false and (err == nil or err == false) and table.concat(back) == index, err)
print("ok")

io.write("testing upload denial: ")
ret, err = ftp.put("ftp://" .. host .. "/index.up.html;type=a", index)
assert((ret == nil or ret == false) and err != nil and err != false, "should have failed")
print(err)

io.write("testing authentication failure: ")
ret, err = ftp.get("ftp://luasocket:wrong@".. host .. "/index.html;type=a")
assert((ret == nil or ret == false) and err != nil and err != false, "should have failed")
print(err)

io.write("testing wrong file: ")
back, err = ftp.get("ftp://".. host .. "/index.wrong.html;type=a")
assert((back == nil or back == false) and err != nil and err != false, "should have failed")
print(err)

print("passed all tests")
print(string.format("done in %.2fs", socket.gettime() - t))
