-- 
-- Test the conn.want(conn) function.
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
socket.sleep(2) -- force the timeout in the client dohandshake()
assert( peer.dohandshake(peer) )
--]]

for i = 1, 10 do
  v = tostring(i)
   io.write(v)
   io.flush()
   peer.send(peer, v)
   socket.sleep(1) -- force the timeout in the client receive()
end
io.write("\n")
peer.send(peer, "\n")
peer.close(peer)
