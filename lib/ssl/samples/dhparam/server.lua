--
-- Public domain
--
socket = require("socket")
ssl    = require("ssl")

function readfile(filename)
 fd = assert(io.open(filename))
 dh = fd.read(fd, "*a")
  fd.close(fd)
  return dh
end

function dhparam_cb(export, keylength)
  print("---")
  print("DH Callback")
  print("Export", export)
  print("Key length", keylength)
  print("---")
 filename = nil
  if keylength == 512 then
    filename = "dh-512.pem"
  elseif keylength == 1024 then
    filename = "dh-1024.pem"
  else
    -- No key
    return nil
  end
  return readfile(filename)
end

params = {
   mode = "server",
   protocol = "any",
   key = "../certs/serverAkey.pem",
   certificate = "../certs/serverA.pem",
   cafile = "../certs/rootA.pem",
   verify = {"peer", "fail_if_no_peer_cert"},
   options = "all",
   dhparam = dhparam_cb,
   ciphers = "EDH+AESGCM"
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

peer.send(peer, "oneshot test\n")
peer.close(peer)
