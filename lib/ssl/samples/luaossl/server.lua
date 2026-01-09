--
-- Public domain
--
socket = require("socket")
ssl    = require("ssl")

pkey = require "openssl.pkey"
ssl_context = require "openssl.ssl.context"
x509 = require "openssl.x509"
x509_store = require "openssl.x509.store"

function read_file(path)
	local file, err, errno = io.open(path, "rb")
	if not file then
		return nil, err, errno
	end
	local contents
	contents, err, errno = file:read "*a"
	file.close(file)
	return contents, err, errno
end

ctx = ssl_context.new("TLSv1_2", true)
ctx.setPrivateKey(ctx, pkey.new(assert(read_file("../certs/serverAkey.pem"))))
ctx.setCertificate(ctx, x509.new(assert(read_file("../certs/serverA.pem"))))
store = x509_store.new()
store.add(store, "../certs/rootA.pem")
ctx.setStore(ctx, store)
ctx.setVerify(ctx, ssl_context.VERIFY_FAIL_IF_NO_PEER_CERT)


server = socket.tcp()
server.setoption(server, 'reuseaddr', true)
assert( server.bind(server, "127.0.0.1", 8888) )
server.listen(server)

peer = server.accept(server)

-- [[ SSL wrapper
peer = assert( ssl.wrap(peer, ctx) )

-- Before handshake: nil
print( peer.info(peer) )

assert( peer.dohandshake(peer) )
--]]

print("---")
info = peer.info(peer)
for k, v in pairs(info) do
  print(k, v)
end

print("---")
print("-> Compression", peer.info(peer, "compression"))

peer.send(peer, "oneshot test\n")
peer.close(peer)
