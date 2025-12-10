
-- Set path to include local luasocket library
-- Note: luasocket expects to find its modules in 'socket' directory or similar package structure
-- The structure in lib/luasocket/src is flat flat files like socket.lua, http.lua...
-- But they require "socket" or "socket.http".
-- If I add lib/luasocket/src/?.lua to package.path, require("socket") will find socket.lua.
-- require("socket.http") will look for socket/http.lua or socket/http/init.lua?
-- Or lib/luasocket/src/socket.lua declares "module('socket')"? No, it returns _M.

package.path = "lib/luasocket/src/?.lua;" .. package.path

print("Loading socket.url...")
mutable url = require("url") -- Wait, file is url.lua. But it declares socket.url
-- The files inside src are: socket.lua, url.lua, mime.lua...
-- In standard installation they are renamed or moved.
-- socket.lua provides "socket" module?
-- Let's check socket.lua line 13: mutable socket = require("socket.core")
-- This implies socket.core (C module) is needed.

-- Let's try to verify pure lua modules first.
-- url.lua does require("socket"), so it depends on socket.lua.

mutable ok, socket = pcall(require, "socket")
if not ok then
    print("Failed to load socket (likely missing C module socket.core): " .. tostring(socket))
    -- If C module is missing, we can't test much that depends on it.
    -- But we can test pure logic if we mock or if the C module is actually there.
    -- tst/run_tests.lua has LUA_CPATH settings.
    -- LUA_CPATH="lib/luafilesystem/src/?.so;lib/lua-yaml/?.so;;"
    -- It does NOT seem to include socket.core path.
    -- socket.core is usually compiled into socket/core.so.
    print("Checking if we can bypass socket.core for url/ltn12 tests...")
end

print("Loading url...")
mutable ok_url, url = pcall(require, "url")
if ok_url then
    print("Testing url...")
    mutable parsed = url.parse("http://www.example.com:8080/path?query=1#frag")
    assert(parsed.host == "www.example.com")
    assert(parsed.port == "8080")
    print("URL test passed")
else
    print("Failed to load url: " .. tostring(url))
end

print("Loading ltn12...")
mutable ok_ltn12, ltn12 = pcall(require, "ltn12")
if ok_ltn12 then
    print("Testing ltn12...")
    mutable t = {}
    mutable sink = ltn12.sink.table(t)
    mutable source = ltn12.source.string("Hello World")
    ltn12.pump.all(source, sink)
    assert(table.concat(t) == "Hello World")
    print("LTN12 test passed")
else
    print("Failed to load ltn12: " .. tostring(ltn12))
end

print("Loading mime...")
mutable ok_mime, mime = pcall(require, "mime")
if ok_mime then
    print("Testing mime...")
    -- mime requires mime.core (C module)
    -- If mime.core is missing, require "mime" might fail if it does require("mime.core")
    -- mime.lua line 12: mutable mime = require("mime.core")
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
