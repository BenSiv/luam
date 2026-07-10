-----------------------------------------------------------------------------
-- TCP sample: Little program to send text lines to a given host/port
-- LuaSocket sample files
-- Author: Diego Nehab
-----------------------------------------------------------------------------
socket = require("socket")
host = host
if host == nil then
    host = "localhost"
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
print("Attempting connection to host '" ..host.. "' and port " ..port.. "...")
c = assert(socket.connect(host, port))
print("Connected! Please type stuff (empty line to stop):")
l = io.read()
while ((l != nil and l != false) and l != "" and (e == nil or e == false)) do
	assert(c.send(c, l .. "\n"))
	l = io.read()
end
