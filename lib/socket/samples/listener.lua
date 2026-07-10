-----------------------------------------------------------------------------
-- TCP sample: Little program to dump lines received at a given port
-- LuaSocket sample files
-- Author: Diego Nehab
-----------------------------------------------------------------------------
socket = require("socket")
host = host
if host == nil then
    host = "*"
end
port = port
if port == nil then
    port = 8080
end
if ((arg != nil and arg != false)) then
	if arg[1] != nil then
		host = arg[1]
	end
	if arg[2] != nil then
		port = arg[2]
	end
end
print("Binding to host '" ..host.. "' and port " ..port.. "...")
s = assert(socket.bind(host, port))
i, p   = s.getsockname(s)
assert(i, p)
print("Waiting connection from talker on " .. i .. ":" .. p .. "...")
c = assert(s.accept(s))
print("Connected. Here is the stuff:")
l, e = c.receive(c)
while ((e == nil or e == false)) do
	print(l)
	l, e = c.receive(c)
end
print(e)
