socket = require"socket"
socket.unix = require"socket.unix"
c = assert(socket.unix.stream())
assert(c.connect(c, "/tmp/foo"))
while 1 do
   l = io.read()
    assert(c.send(c, l .. "\n"))
end
