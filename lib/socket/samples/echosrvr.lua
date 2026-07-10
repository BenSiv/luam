-----------------------------------------------------------------------------
-- UDP sample: echo protocol server
-- LuaSocket sample files
-- Author: Diego Nehab
-----------------------------------------------------------------------------
socket = require("socket")
host = host
if host == nil then
    host = "127.0.0.1"
end
port = port
if port == nil then
    port = 7
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
udp = assert(socket.udp())
assert(udp.setsockname(udp, host, port))
assert(udp.settimeout(udp, 5))
ip, port = udp.getsockname(udp)
assert(ip, port)
print("Waiting packets on " .. ip .. ":" .. port .. "...")
while ((1 != nil and 1 != false)) do
	dgram, ip, port = udp.receivefrom(udp)
	if ((dgram != nil and dgram != false)) then
		print("Echoing '" .. dgram .. "' to " .. ip .. ":" .. port)
		udp.sendto(udp, dgram, ip, port)
	else
        print(ip)
    end
end
