socket = require "socket"
u = socket.udp() assert(u.setsockname(u, "*", 5088)) u.close(u)
u = socket.udp() assert(u.setsockname(u, "*", 0)) u.close(u)
t = socket.tcp() assert(t.bind(t, "*", 5088)) t.close(t)
t = socket.tcp() assert(t.bind(t, "*", 0)) t.close(t)
print("done!")