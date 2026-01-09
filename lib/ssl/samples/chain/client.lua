--
-- Public domain
--
socket = require("socket")
ssl    = require("ssl")
util   = require("util") 

params = {
   mode = "client",
   protocol = "tlsv1_2",
   key = "../certs/clientAkey.pem",
   certificate = "../certs/clientA.pem",
   cafile = "../certs/rootA.pem",
   verify = {"peer", "fail_if_no_peer_cert"},
   options = "all",
}

conn = socket.tcp()
conn.connect(conn, "127.0.0.1", 8888)

conn = assert( ssl.wrap(conn, params) )
assert(conn.dohandshake(conn))

util.show( conn.getpeercertificate(conn) )

print("----------------------------------------------------------------------")

for k, cert in ipairs( conn.getpeerchain(conn) ) do
  util.show(cert)
end

cert = conn.getpeercertificate(conn)
print( cert )
print( cert.pem(cert) )

conn.close(conn)
