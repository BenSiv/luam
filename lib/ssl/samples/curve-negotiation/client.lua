--
-- Public domain
--
socket = require("socket")
ssl    = require("ssl")

params = {
   mode = "client",
   protocol = "any",
   key = "../certs/clientAkey.pem",
   certificate = "../certs/clientA.pem",
   cafile = "../certs/rootA.pem",
   verify = {"peer", "fail_if_no_peer_cert"},
   options = {"all"},
   --
   curve = "P-256:P-384",
}

peer = socket.tcp()
peer.connect(peer, "127.0.0.1", 8888)

-- [[ SSL wrapper
peer = assert( ssl.wrap(peer, params) )
assert(peer.dohandshake(peer))
--]]

print(peer.receive(peer, "*l"))
peer.close(peer)
