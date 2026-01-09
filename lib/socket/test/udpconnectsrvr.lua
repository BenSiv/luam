socket = require"socket"
udp = socket.udp
localhost = "127.0.0.1"
s = assert(udp())
assert(tostring(s):find("udp{unconnected}"))
print("setpeername", s.setpeername(s, localhost, 5061))
print("getsockname", s.getsockname(s))
assert(tostring(s):find("udp{connected}"))
print(s.receive(s))
print("setpeername", s.setpeername(s, "*"))
print("getsockname", s.getsockname(s))
s.sendto(s, "a", localhost, 12345)
print("getsockname", s.getsockname(s))
assert(tostring(s):find("udp{unconnected}"))
print(s.receivefrom(s))
s.close(s)
