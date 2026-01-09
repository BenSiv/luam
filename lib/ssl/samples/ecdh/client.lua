--
-- Public domain
--
socket = require("socket")
ssl    = require("ssl")

params = {
   mode = "client",
   protocol = "tlsv1_2",
   key = "../certs/clientAkey.pem",
   certificate = "../certs/clientA.pem",
   cafile = "../certs/rootA.pem",
   verify = {"peer", "fail_if_no_peer_cert"},
   options = "all",
   --
   curve = "secp384r1",
}

--------------------------------------------------------------------------------
peer = socket.tcp()
peer.connect(peer, "127.0.0.1", 8888)

peer = assert( ssl.wrap(peer, params) )
assert(peer.dohandshake(peer))

print("--- INFO  ---")
info = peer.info(peer)
for k, v in pairs(info) do
  print(k, v)
end
print("---")

peer.close(peer)
