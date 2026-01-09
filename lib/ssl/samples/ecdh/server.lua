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
   --
   curve = "secp384r1",
}

------------------------------------------------------------------------------
ctx = assert(ssl.newcontext(params))

server = socket.tcp()
server.setoption(server, 'reuseaddr', true)
assert( server.bind(server, "127.0.0.1", 8888) )
server.listen(server)

peer = server.accept(server)

peer = assert( ssl.wrap(peer, ctx) )
assert( peer.dohandshake(peer) )

print("--- INFO ---")
info = peer.info(peer)
for k, v in pairs(info) do
  print(k, v)
end
print("---")

peer.close(peer)
server.close(server)
