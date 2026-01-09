--
-- Public domain
--
socket = require("socket")
ssl    = require("ssl")

params = {
   mode = "client",
   protocol = "tlsv1",
   key = "../../certs/clientBkey.pem",
   certificate = "../../certs/clientB.pem",
   cafile = "../../certs/rootB.pem",
   verify = "none",
   options = "all",
}

peer = socket.tcp()
peer.connect(peer, "127.0.0.1", 8888)

-- [[ SSL wrapper
peer = assert( ssl.wrap(peer, params) )
assert(peer.dohandshake(peer))
--]]

err, msg = peer.getpeerverification(peer)
print(err, msg)

print(peer.receive(peer, "*l"))
peer.close(peer)
