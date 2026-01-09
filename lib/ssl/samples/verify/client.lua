--
-- Public domain
--
socket = require("socket")
ssl    = require("ssl")

params = {
   mode = "client",
   protocol = "tlsv1_2",
   key = "../certs/serverBkey.pem",
   certificate = "../certs/serverB.pem",
   cafile = "../certs/rootB.pem",
   verify = {"peer", "fail_if_no_peer_cert"},
   verifyext = {"lsec_continue", "lsec_ignore_purpose"},
   options = "all",
}

ctx = assert(ssl.newcontext(params))

peer = socket.tcp()
peer.connect(peer, "127.0.0.1", 8888)

peer = assert( ssl.wrap(peer, ctx) )
assert(peer.dohandshake(peer))

succ, errs = peer.getpeerverification(peer)
print(succ, errs)
for i, err in pairs(errs) do
  for j, msg in ipairs(err) do
    print("depth = " .. i, "error = " .. msg)
  end
end

print(peer.receive(peer, "*l"))
peer.close(peer)
