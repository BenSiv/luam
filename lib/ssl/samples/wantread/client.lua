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
   if err == "timeout" or err == "wantread" then
      socket.select({peer}, nil)
   elseif err == "wantwrite" then
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
peer.settimeout(peer, 0.3)
succ, err = peer.dohandshake(peer)
while not succ do
   print("handshake", err)
   wait(peer, err)
   succ, err = peer.dohandshake(peer)
end
print("** Handshake done")
--]]

-- If the section above is commented, the timeout is not set.
-- We set it again for safetiness.
peer.settimeout(peer, 0.3)  

str, err, part = peer.receive(peer, "*l")
while not str do
   print(part, err)
   wait(peer, err)
   str, err, part = peer.receive(peer, "*l")
end
peer.close(peer)
