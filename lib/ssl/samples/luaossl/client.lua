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

ctx = ssl_context.new("TLSv1_2", false)
ctx.setPrivateKey(ctx, pkey.new(assert(read_file("../certs/clientAkey.pem"))))
ctx.setCertificate(ctx, x509.new(assert(read_file("../certs/clientA.pem"))))
store = x509_store.new()
store.add(store, "../certs/rootA.pem")
ctx.setStore(ctx, store)
ctx.setVerify(ctx, ssl_context.VERIFY_FAIL_IF_NO_PEER_CERT)

peer = socket.tcp()
peer.connect(peer, "127.0.0.1", 8888)

-- [[ SSL wrapper
peer = assert( ssl.wrap(peer, ctx) )
assert(peer.dohandshake(peer))
--]]

print(peer.receive(peer, "*l"))
peer.close(peer)
