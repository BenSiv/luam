--
-- Public domain
--
socket = require("socket")
ssl    = require("ssl")

print("Use Ctrl+S and Ctrl+Q to suspend and resume the server.")

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

while true do
  str = peer.receive(peer, "*l")
   print(str)
end
peer.close(peer)
