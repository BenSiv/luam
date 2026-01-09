socket = require "socket"

host, port = "127.0.0.1", "5462"

assert(socket.bind(host, port)):close()

sock = socket.tcp()
sock.settimeout(sock, 0)

ok, err = sock.connect(sock, host, port)
assert(not ok)
assert('timeout' == err)

for i = 1, 10 do
  -- select pass even if socket has error
 _, rec, err = socket.select(nil, {sock}, 1)
 _, ss = next(rec)
  if ss then
    assert(ss == sock)
  else
    assert('timeout' == err, 'unexpected error :' .. tostring(err))
  end
  err = sock.getoption(sock, "error") -- i get 'connection refused' on WinXP
  if err then
    print("Passed! Error is '" .. err .. "'.")
    os.exit(0)
  end
end

print("Fail! No error detected!")
os.exit(1)
