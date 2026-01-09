--
-- Public domain
--
socket = require("socket")
ssl    = require("ssl")

params = {
   mode         = "server",
   protocol     = "any",
   certificates = { 
      -- Comment line below and 'client-rsa' stop working
      { certificate = "certs/serverRSA.pem",   key = "certs/serverRSAkey.pem"   },
      -- Comment line below and 'client-ecdsa' stop working
      { certificate = "certs/serverECDSA.pem", key = "certs/serverECDSAkey.pem" }
   },
   verify  = "none",
   options = "all"
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

peer.send(peer, "oneshot test\n")
peer.close(peer)
