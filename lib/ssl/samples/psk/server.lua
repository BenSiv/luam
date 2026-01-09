--
-- Public domain
--
socket = require("socket")
ssl    = require("ssl")

if not ssl.config.capabilities.psk then
   print("[ERRO] PSK not available")
   os.exit(1)
end

-- @param identity (string)
-- @param max_psk_len (number)
-- @return psk (string)
function pskcb(identity, max_psk_len)
   print(string.format("PSK Callback: identity=%q, max_psk_len=%d", identity, max_psk_len))
   if identity == "abcd" then
     return "1234"
  end
  return nil
end

params = {
   mode = "server",
   protocol = "any",
   options = "all",

-- PSK with just a callback
   psk = pskcb,

-- PSK with identity hint
--   psk = {
--      hint = "hintpsksample",
--      callback = pskcb,
--   },
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

print("--- INFO ---")
info = peer.info(peer)
for k, v in pairs(info) do
   print(k, v)
end
print("---")

peer.close(peer)
server.close(server)
