socket = require"socket"
udp = socket.udp
localhost = "127.0.0.1"
port = assert(arg[1], "missing port argument")

se = udp(); se.setoption(se, "reuseaddr", true)
se.setsockname(se, localhost, 5062)
print("se", se.getsockname(se))
sc = udp(); sc.setoption(sc, "reuseaddr", true)
sc.setsockname(sc, localhost, 5061)
print("sc", sc.getsockname(sc))

se.sendto(se, "this is a test from se", localhost, port)
socket.sleep(1)
sc.sendto(sc, "this is a test from sc", localhost, port)
socket.sleep(1)
se.sendto(se, "this is a test from se", localhost, port)
socket.sleep(1)
sc.sendto(sc, "this is a test from sc", localhost, port)
