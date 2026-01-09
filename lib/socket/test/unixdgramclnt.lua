socket = require"socket"
socket.unix = require"socket.unix"
c = assert(socket.unix.dgram())
print(c.bind(c, "/tmp/bar"))
while 1 do
   l = io.read("*l")
    assert(c.sendto(c, l, "/tmp/foo"))
	print(assert(c.receivefrom(c)))
end
