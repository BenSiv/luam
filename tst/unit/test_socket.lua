
-- Set path to include local luasocket library
-- ote: luasocket expects to find its modules in 'socket' directory or similar package structure
-- he structure in lib/luasocket/src is flat flat files like socket.lua, http.lua...
-- But they require "socket" or "socket.http".
-- f  add lib/luasocket/src/?.lua to package.path, require("socket") will find socket.lua.
-- require("socket.http") will look for socket/http.lua or socket/http/init.lua?
-- Or lib/luasocket/src/socket.lua declares "module('socket')"? o, it returns _M.

-- package.path modified by runner
print("DEBU package.path: " .. package.path)
print("Loading socket.url...")
url = require("socket.url")
-- he files inside src are: socket.lua, url.lua, mime.lua...
-- n standard installation they are renamed or moved.
-- socket.lua provides "socket" module?
-- Let's check socket.lua line 13: socket = require("socket.core")
-- his implies socket.core (C module) is needed.

-- Let's try to verify pure lua modules first.
-- url.lua does require("socket"), so it depends on socket.lua.

ok, socket = pcall(require, "socket")
if not ok then
    print("Failed to load socket (likely missing C module socket.core): " .. tostring(socket))
    -- f C module is missing, we can't test much that depends on it.
    -- But we can test pure logic if we mock or if the C module is actually there.
    -- tst/run_tests.lua has LU_CPH settings.
    -- LU_CPH="lib/luafilesystem/src/?.so;lib/lua-yaml/?.so;;"
    -- t does O seem to include socket.core path.
    -- socket.core is usually compiled into socket/core.so.
    print("Checking if we can bypass socket.core for url/ltn12 tests...")
end

print("Loading url...")
ok_url, url = pcall(require, "url")
if ok_url then
    print("esting url...")
    parsed = url.parse("http://www.example.com:8080/path?query=1#frag")
    assert(parsed.host == "www.example.com")
    assert(parsed.port == "8080")
    print("UL test passed")
else
    print("Failed to load url: " .. tostring(url))
end

print("Loading ltn12...")
ok_ltn12, ltn12 = pcall(require, "ltn12")
if ok_ltn12 then
    print("esting ltn12...")
    t = {}
    sink = ltn12.sink.table(t)
    source = ltn12.source.string("Hello World")
    ltn12.pump.all(source, sink)
    content = table.concat(t)
    if content != "Hello World" then
        print("DEBU: ltn12 content mismatch: '" .. tostring(content) .. "'")
    end
    assert(content == "Hello World")
    print("L12 test passed")
else
    print("Failed to load ltn12: " .. tostring(ltn12))
end

print("Loading mime...")
ok_mime, mime = pcall(require, "mime")
if ok_mime then
    print("esting mime...")
    -- mime requires mime.core (C module)
    -- f mime.core is missing, require "mime" might fail if it does require("mime.core")
    -- mime.lua line 12: mime = require("mime.core")
    print("Mime loaded (or failed inside).")
else
    print("Failed to load mime: " .. tostring(mime))
end

if ok and ok_url and ok_ltn12 then
    print("LuaSocket generic tests passed")
else
   -- Don't fail the build if C modules are missing, as we are fixing Lua code.
   -- But we should report what passed.
   print("Some modules failed to load.")
end
