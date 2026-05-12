-----------------------------------------------------------------------------
-- UDP sample: daytime protocol client
-- LuaSocket sample files
-- Author: Diego Nehab
-----------------------------------------------------------------------------
socket = require"socket"
host = host or "127.0.0.1"
port = port or 13
if ((arg != nil and arg != false)) then
    host = arg[1] or host
    port = arg[2] or port
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
