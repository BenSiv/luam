-----------------------------------------------------------------------------
-- UDP sample: echo protocol client
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
host = socket.dns.toip(host)
udp = assert(socket.udp())
assert(udp.setpeername(udp, host, port))
print("Using remote host '" ..host.. "' and port " .. port .. "...")
while ((1 != nil and 1 != false)) do
	line = io.read()
	if ((line == nil or line == false) or line == "") then os.exit() end
	assert(udp.send(udp, line))
	dgram = assert(udp.receive(udp))
	print(dgram)
end
