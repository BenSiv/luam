socket = require("socket")
ssl    = require("ssl")

params = {
  mode = "client",
  protocol = "tlsv1_2",
  key = "../certs/clientAkey.pem",
  certificate = "../certs/clientA.pem",
  cafile = "../certs/rootA.pem",
  verify = "peer",
  options = "all",
}

conn = socket.tcp()
conn.connect(conn, "127.0.0.1", 8888)

-- TLS/SSL initialization
conn = ssl.wrap(conn, params)

-- Comment the lines to not send a name
--conn.sni(conn, "servera.br")
--conn.sni(conn, "serveraa.br")
conn.sni(conn, "serverb.br")

assert(conn.dohandshake(conn))
--
cert = conn.getpeercertificate(conn)
for k, v in pairs(cert.subject(cert)) do
  for i, j in pairs(v) do
    print(i, j)
  end
end
--
print(conn.receive(conn, "*l"))
conn.close(conn)
