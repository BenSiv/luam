--
-- Public domain
--
socket = require("socket")
ssl    = require("ssl")

--
-- Callback that selects one protocol from client's list.
--
function alpncb01(protocols)
   print("--- ALPN protocols from client")
   for k, v in ipairs(protocols) do
      print(k, v)
   end
   print("--- Selecting:", protocols[1])
   return protocols[1]
end

--
-- Callback that returns a fixed list, ignoring the client's list.
--
function alpncb02(protocols)
   print("--- ALPN protocols from client")
   for k, v in ipairs(protocols) do
      print(k, v)
   end
   print("--- Returning a fixed list") 
   return {"bar", "foo"}
end

--
-- Callback that generates a list as it whishes.
--
function alpncb03(protocols)
  resp = {}
   print("--- ALPN protocols from client")
   for k, v in ipairs(protocols) do
      print(k, v)
      if k%2 != 0 then resp[#resp+1] = v end
   end
   print("--- Returning an odd list")
   return resp
end


params = {
   mode = "server",
   protocol = "any",
   key = "../certs/serverAkey.pem",
   certificate = "../certs/serverA.pem",
   cafile = "../certs/rootA.pem",
   verify = {"peer", "fail_if_no_peer_cert"},
   options = "all",
   --alpn = alpncb01,
   --alpn = alpncb02,
   --alpn = alpncb03,
   alpn = {"bar", "baz", "foo"},
}


-- [[ SSL context
ctx = assert(ssl.newcontext(params))
--]]

server = socket.tcp()
server.setoption(server, 'reuseaddr', true)
assert( server.bind(server, "127.0.0.1", 8888) )
server.listen(server)

peer = server.accept(server)
peer = assert( ssl.wrap(peer, ctx) )
assert( peer.dohandshake(peer) )

print("ALPN", peer.getalpn(peer))

peer.close(peer)
server.close(server)
