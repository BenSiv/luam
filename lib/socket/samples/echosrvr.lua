-----------------------------------------------------------------------------
-- UDP sample: echo protocol server
-- LuaSocket sample files
-- Author: Diego Nehab
-----------------------------------------------------------------------------
socket = require("socket")
host = host or "127.0.0.1"
port = port or 7
if arg then
    host = arg[1] or host
    port = arg[2] or port
end
print("Binding to host '" ..host.. "' and port " ..port.. "...")
udp = assert(socket.udp())
assert(udp.setsockname(udp, host, port))
assert(udp.settimeout(udp, 5))
ip, port = udp.getsockname(udp)
assert(ip, port)
print("Waiting packets on " .. ip .. ":" .. port .. "...")
while 1 do
	dgram, ip, port = udp.receivefrom(udp)
	if dgram then
		print("Echoing '" .. dgram .. "' to " .. ip .. ":" .. port)
		udp.sendto(udp, dgram, ip, port)
	else
        print(ip)
    end
end
