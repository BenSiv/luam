--
-- Public domain
--
socket = require("socket")
ssl    = require("ssl")

params = {
   mode = "server",
   protocol = "tlsv1",
   key = "../../certs/serverAkey.pem",
   certificate = "../../certs/serverA.pem",
   cafile = "../../certs/rootA.pem",
   verify = "none",
   options = "all",
}

-- [[ SSL context
ctx = assert(ssl.newcontext(params))
--]]

server = socket.tcp()
server.setoption(server, 'reuseaddr', true)
assert( server.bind(server, "127.0.0.1", 8888) )
server.listen(server)

peer = server.accept(server)

-- [[ SSL wrapper
peer = assert( ssl.wrap(peer, ctx) )
assert( peer.dohandshake(peer) )
--]]

err, msg = peer.getpeerverification(peer)
print(err, msg)

peer.send(peer, "oneshot test\n")
peer.close(peer)
