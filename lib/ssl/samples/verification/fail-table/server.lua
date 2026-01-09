--
-- Public domain
--
socket = require("socket")
ssl    = require("ssl")

params = {
   mode = "server",
   protocol = "tlsv1",
   key = "../../certs/serverAkey.pem",
   certificate = "../../certs/serverA.pem",
   cafile = "../../certs/rootA.pem",
   verify = {"peer", "fail_if_no_peer_cert"},
   options = "all",
   verifyext = {"lsec_continue", "crl_check", "crl_check_chain"},
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

succ, errs = peer.getpeerverification(peer)
print(succ, errs)
for i, err in pairs(errs) do
  for j, msg in ipairs(err) do
    print("depth = " .. i, "error = " .. msg)
  end
end

peer.send(peer, "oneshot test\n")
peer.close(peer)
