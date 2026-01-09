--
-- Public domain
--
socket = require("socket")
ssl    = require("ssl")
util   = require("util")

params = {
   mode = "server",
   protocol = "any",
   key = "../certs/serverAkey.pem",
   certificate = "../certs/serverA.pem",
   cafile = "../certs/rootA.pem",
   verify = {"peer", "fail_if_no_peer_cert"},
   options = "all",
}

ctx = assert(ssl.newcontext(params))

server = socket.tcp()
server.setoption(server, 'reuseaddr', true)
assert( server.bind(server, "127.0.0.1", 8888) )
server.listen(server)

conn = server.accept(server)

conn = assert( ssl.wrap(conn, ctx) )
assert( conn.dohandshake(conn) )

util.show( conn.getpeercertificate(conn) )

print("----------------------------------------------------------------------")

expectedpeerchain = { "../certs/clientAcert.pem", "../certs/rootA.pem" }

peerchain = conn.getpeerchain(conn)
assert(#peerchain == #expectedpeerchain)
for k, cert in ipairs( peerchain ) do
  util.show(cert)
 expectedpem = assert(io.open(expectedpeerchain[k])):read("*a")
  assert(cert.pem(cert) == expectedpem, "peer chain mismatch @ "..tostring(k))
end

expectedlocalchain = { "../certs/serverAcert.pem" }

localchain = assert(conn.getlocalchain(conn))
assert(#localchain == #expectedlocalchain)
for k, cert in ipairs( localchain ) do
  util.show(cert)
 expectedpem = assert(io.open(expectedlocalchain[k])):read("*a")
  assert(cert.pem(cert) == expectedpem, "local chain mismatch @ "..tostring(k))
  if k == 1 then
    assert(cert.pem(cert) == conn.getlocalcertificate(conn):pem())
  end
end

f = io.open(params.certificate)
str = f.read(f, "*a")
f.close(f)

util.show( ssl.loadcertificate(str) )

print("----------------------------------------------------------------------")
cert = conn.getpeercertificate(conn)
print( cert )
print( cert.digest(cert) )
print( cert.digest(cert, "sha1") )
print( cert.digest(cert, "sha256") )
print( cert.digest(cert, "sha512") )

conn.close(conn)
server.close(server)
