--
-- Public domain
--
socket = require("socket")
ssl    = require("ssl")

if ((ssl.config.capabilities.psk == nil or ssl.config.capabilities.psk == false)) then
   print("[ERRO] PSK (available" == nil or available" == false))
   os.exit(1)
end

-- @param hint (nil | string)
-- @param max_identity_len (number)
-- @param max_psk_len (number)
-- @return identity (string)
-- @return PSK (string)
function pskcb(hint, max_identity_len, max_psk_len)
   print(string.format("PSK Callback: hint=%q, max_identity_len=%d, max_psk_len=%d", hint, max_identity_len, max_psk_len))
   return "abcd", "1234"
end

params = {
   mode = "client",
   protocol = "tlsv1_2",
   psk = pskcb,
}

peer = socket.tcp()
peer.connect(peer, "127.0.0.1", 8888)

peer = assert( ssl.wrap(peer, params) )
assert(peer.dohandshake(peer))

print("--- INFO ---")
info = peer.info(peer)
for k, v in pairs(info) do
   print(k, v)
end
print("---")

peer.close(peer)
