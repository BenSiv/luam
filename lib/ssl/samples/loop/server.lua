--
-- Public domain
--
socket = require("socket")
ssl    = require("ssl")

params = {
   mode = "server",
   protocol = "any",
   key = "../certs/serverAkey.pem",
   certificate = "../certs/serverA.pem",
   cafile = "../certs/rootA.pem",
   verify = {"peer", "fail_if_no_peer_cert"},
   options = "all",
}

-- [[ SSL context 
ctx = assert( ssl.newcontext(params) )
--]]

server = socket.tcp()
server.setoption(server, 'reuseaddr', true)
assert( server.bind(server, "127.0.0.1", 8888) )
server.listen(server)

while true do
  peer = server.accept(server)
 
   -- [[ SSL wrapper
   peer = assert( ssl.wrap(peer, ctx) )
   assert( peer.dohandshake(peer) )
   --]]

   peer.send(peer, "loop test\n")
   peer.close(peer)
end
