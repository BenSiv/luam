socket = require"socket"
group = "225.0.0.37"
port = 12345
c = assert(socket.udp())
--print(assert(c.setoption(c, "reuseport", true)))
--print(assert(c.setsockname(c, "*", port)))
--print(assert(c.setoption(c, "ip-multicast-loop", false)))
--print(assert(c.setoption(c, "ip-multicast-ttl", 4)))
--print(assert(c.setoption(c, "ip-multicast-if", "10.0.1.3")))
--print(assert(c.setoption(c, "ip-add-membership", {multiaddr = group, interface = "*"})))
i = 0
while 1 do
   message = string.format("hello all %d!", i)
    assert(c.sendto(c, message, group, port))
    print("sent " .. message)
    socket.sleep(1)
    c.settimeout(c, 0.5)
    print(c.receivefrom(c))
    i = i + 1
end
