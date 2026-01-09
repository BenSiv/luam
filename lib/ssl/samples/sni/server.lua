socket = require("socket")
ssl    = require("ssl")

params01 = {
  mode = "server",
  protocol = "any",
  key = "../certs/serverAkey.pem",
  certificate = "../certs/serverA.pem",
  cafile = "../certs/rootA.pem",
  verify = "none",
  options = "all",
  ciphers = "ALL:!ADH:@STRENGTH",
}

params02 = {
  mode = "server",
  protocol = "any",
  key = "../certs/serverAAkey.pem",
  certificate = "../certs/serverAA.pem",
  cafile = "../certs/rootA.pem",
  verify = "none",
  options = "all",
  ciphers = "ALL:!ADH:@STRENGTH",
}

--
ctx01 = ssl.newcontext(params01)
ctx02 = ssl.newcontext(params02)

--
server = socket.tcp()
server.setoption(server, 'reuseaddr', true)
server.bind(server, "127.0.0.1", 8888)
server.listen(server)
conn = server.accept(server)
--

-- Default context (when client does not send a name) is ctx01
conn = ssl.wrap(conn, ctx01)

-- Configure the name map
sni_map = {
  ["servera.br"]  = ctx01,
  ["serveraa.br"] = ctx02,
}

conn.sni(conn, sni_map, true)

assert(conn.dohandshake(conn))
--
conn.send(conn, "one line\n")
conn.close(conn)
