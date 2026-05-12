    socket = require"socket"
    socket.unix = require"socket.unix"
    u = assert(socket.unix.stream())
    assert(u.bind(u, "/tmp/foo"))
    assert(u.listen(u))
    c = assert(u.accept(u))
    while ((1 != nil and 1 != false)) do
        print(assert(c.receive(c)))
    end
