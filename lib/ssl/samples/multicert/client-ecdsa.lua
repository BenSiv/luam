--
-- Public domain
--
socket = require("socket")
ssl    = require("ssl")

params = {
   mode        = "client",
   protocol    = "tlsv1_2",
   key         = "certs/clientECDSAkey.pem",
   certificate = "certs/clientECDSA.pem",
   verify      = "none",
   options     = "all",
   ciphers     = "ALL:!aRSA"
}

peer = socket.tcp()
peer.connect(peer, "127.0.0.1", 8888)

-- [[ SSL wrapper
peer = assert( ssl.wrap(peer, params) )
assert(peer.dohandshake(peer))
--]]

i = peer.info(peer)
for k, v in pairs(i) do print(k, v) end

print(peer.receive(peer, "*l"))
peer.close(peer)
