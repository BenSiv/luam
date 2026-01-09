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

cert = peer.getpeercertificate(peer)
sha1   = cert.digest(cert, "sha1")
sha256 = cert.digest(cert, "sha256")
sha512 = cert.digest(cert, "sha512")

print("SHA1",   sha1)
print("SHA256", sha256)
print("SHA512", sha512)

peer.send(peer, "oneshot test\n")
peer.close(peer)
