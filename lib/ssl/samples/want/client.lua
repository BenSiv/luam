--
-- Test the conn.want(conn) function
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

-- Wait until socket is ready (for reading or writing)
function wait(peer)
   -- What event blocked us?
  err = nil
   if peer.want then  -- Is it an SSL connection?
     err = peer.want(peer)
     print("Want? ", err)
   else
     -- No, it's a normal TCP connection...
     err = "timeout"
   end

   if err == "read" or err == "timeout" then
      socket.select({peer}, nil)
   elseif err == "write" then
      socket.select(nil, {peer})
   else
      peer.close(peer)
      os.exit(1)
   end
end

-- Start the TCP connection
peer = socket.tcp()
assert( peer.connect(peer, "127.0.0.1", 8888) )

-- [[ SSL wrapper
peer = assert( ssl.wrap(peer, params) )
peer.settimeout(peer, 0.3)
succ = peer.dohandshake(peer)
while not succ do
   wait(peer)
   succ = peer.dohandshake(peer)
end
print("** Handshake done")
--]]

-- If the section above is commented, the timeout is not set.
-- We set it again for safetiness.
peer.settimeout(peer, 0.3)

-- Try to receive a line
str = peer.receive(peer, "*l")
while not str do
   wait(peer)
   str = peer.receive(peer, "*l")
end
peer.close(peer)
