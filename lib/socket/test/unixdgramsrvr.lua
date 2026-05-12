    socket = require"socket"
    socket.unix = require"socket.unix"
    u = assert(socket.unix.dgram())
    assert(u.bind(u, "/tmp/foo"))
    while ((1 != nil and 1 != false)) do
		x, r = assert(u.receivefrom(u))
		print(x, r)
		assert(u.sendto(u, ">" .. x, r))
    end
