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
}

function wait(peer, err)
   if err == "wantread" then
      socket.select({peer}, nil)
   elseif err == "timeout" or err == "wantwrite" then
      socket.select(nil, {peer})
   else
      peer.close(peer)
      os.exit(1)
   end
end


peer = socket.tcp()
assert( peer.connect(peer, "127.0.0.1", 8888) )

-- [[ SSL wrapper
peer = assert( ssl.wrap(peer, params) )
assert( peer.dohandshake(peer) )
--]]

peer.settimeout(peer, 0.3)

str = "a rose is a rose is a rose is a...\n"
while true do
   print("Sending...")
  succ, err = peer.send(peer, str)
   while succ do
      succ, err = peer.send(peer, str)
   end
   print("Waiting...", err)
   wait(peer, err)
end
peer.close(peer)
