socket = require"socket"
group = "225.0.0.37"
port = 12345
c = assert(socket.udp())
print(assert(c.setoption(c, "reuseport", true)))
print(assert(c.setsockname(c, "*", port)))
--print("loop:", c.getoption(c, "ip-multicast-loop"))
--print(assert(c.setoption(c, "ip-multicast-loop", false)))
--print("loop:", c.getoption(c, "ip-multicast-loop"))
--print("if:", c.getoption(c, "ip-multicast-if"))
--print(assert(c.setoption(c, "ip-multicast-if", "127.0.0.1")))
--print("if:", c.getoption(c, "ip-multicast-if"))
--print(assert(c.setoption(c, "ip-multicast-if", "10.0.1.4")))
--print("if:", c.getoption(c, "ip-multicast-if"))
print(assert(c.setoption(c, "ip-add-membership", {multiaddr = group, interface = "*"})))
while 1 do
    print(c.receivefrom(c))
end
