-----------------------------------------------------------------------------
-- UDP sample: daytime protocol client
-- LuaSocket sample files
-- Author: Diego Nehab
-----------------------------------------------------------------------------
socket = require"socket"
host = host
if host == nil then
    host = "127.0.0.1"
end
port = port
if port == nil then
    port = 13
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
udp = socket.udp()
print("Using host '" ..host.. "' and port " ..port.. "...")
udp.setpeername(udp, host, port)
udp.settimeout(udp, 3)
sent, err = udp.send(udp, "anything")
if ((err != nil and err != false)) then print(err) os.exit() end
dgram, err = udp.receive(udp)
if ((dgram == nil or dgram == false)) then print(err) os.exit() end
io.write(dgram)
