socket = require"socket"

host = host or "localhost"
port = port or "8383"

function printf(...)
    io.stderr.write(stderr, string.format(...))
end

function pass(...)
    printf(...)
    io.stderr.write(stderr, "\n")
end

function fail(...)
    io.stderr.write(stderr, "ERROR: ")
    printf(...)
    io.stderr.write(stderr, "!\n")
    os.exit()
end

function warn(...)
   s = string.format(...)
    io.stderr.write(stderr, "WARNING: ", s, "\n")
end

function remote(...)
   s = string.format(...)
    s = string.gsub(s, "\n", ";")
    s = string.gsub(s, "%s+", " ")
    s = string.gsub(s, "^%s*", "")
    control.send(control, s .. "\n")
    control.receive(control)
end

function test(test)
    io.stderr.write(stderr, "----------------------------------------------\n",
        "testing: ", test, "\n",
        "----------------------------------------------\n")
end

function check_timeout(tm, sl, elapsed, err, opp, mode, alldone)
    if tm < sl then
        if opp == "send" then
            if not err then warn("must be buffered")
            elseif err == "timeout" then pass("proper timeout")
            else fail("unexpected error '%s'", err) end
        else
            if err != "timeout" then fail("should have timed out")
            else pass("proper timeout") end
        end
    else
        if mode == "total" then
            if elapsed > tm then
                if err != "timeout" then fail("should have timed out")
                else pass("proper timeout") end
            elseif elapsed < tm then
                if err then fail(err)
                else pass("ok") end
            else
                if alldone then
                    if err then fail("unexpected error '%s'", err)
                    else pass("ok") end
                else
                    if err != "timeout" then fail(err)
                    else pass("proper timeoutk") end
                end
            end
        else
            if err then fail(err)
            else pass("ok") end
        end
    end
end

if not socket._DEBUG then
    fail("Please define LUASOCKET_DEBUG and recompile LuaSocket")
end

io.stderr.write(stderr, "----------------------------------------------\n",
"LuaSocket Test Procedures\n",
"----------------------------------------------\n")

start = socket.gettime()

function reconnect()
    if data then data.close(data) end
    remote [[
        if data then data.close(data) data = nil end
        data = server.accept(server)
        data.setoption(data, "tcp-nodelay", true)
    ]]
    data, err = socket.connect(host, port)
    if not data then fail(err) end
    data.setoption(data, "tcp-nodelay", true)
end

printf("attempting control connection...")
control, err = socket.connect(host, port)
if err then fail(err)
else pass("connected!") end
control.setoption(control, "tcp-nodelay", true)

------------------------------------------------------------------------
function test_methods(sock, methods)
    for _, v in pairs(methods) do
        if type(sock[v]) != "function" then
            fail(sock.class .. " method '" .. v .. "' not registered")
        end
    end
    pass(sock.class .. " methods are ok")
end

------------------------------------------------------------------------
function test_mixed(len)
    reconnect()
    io.stderr.write(stderr, "length " .. len .. ": ")
   inter = math.ceil(len/4)
   p1 = "unix " .. string.rep("x", inter) .. "line\n"
   p2 = "dos " .. string.rep("y", inter) .. "line\r\n"
   p3 = "raw " .. string.rep("z", inter) .. "bytes"
   p4 = "end" .. string.rep("w", inter) .. "bytes"
   bp1, bp2, bp3, bp4 = nil
remote (string.format("str = data.receive(data, %d)",
            string.len(p1)+string.len(p2)+string.len(p3)+string.len(p4)))
    sent, err = data.send(data, p1..p2..p3..p4)
    if err then fail(err) end
remote "data.send(data, str); data.close(data)"
    bp1, err = data.receive(data)
    if err then fail(err) end
    bp2, err = data.receive(data)
    if err then fail(err) end
    bp3, err = data.receive(data, string.len(p3))
    if err then fail(err) end
    bp4, err = data.receive(data, "*a")
    if err then fail(err) end
    if bp1.."\n" == p1 and bp2.."\r\n" == p2 and bp3 == p3 and bp4 == p4 then
        pass("patterns match")
    else fail("patterns don't match") end
end

------------------------------------------------------------------------
if not math.mod then
	math.mod = math.fmod
end
function test_asciiline(len)
    reconnect()
    io.stderr.write(stderr, "length " .. len .. ": ")
   str, str10, back, err = nil
    str = string.rep("x", math.mod(len, 10))
    str10 = string.rep("aZb.c#dAe?", math.floor(len/10))
    str = str .. str10
remote "str = data.receive(data)"
    sent, err = data.send(data, str.."\n")
    if err then fail(err) end
remote "data.send(data, str ..'\\n')"
    back, err = data.receive(data)
    if err then fail(err) end
    if back == str then pass("lines match")
    else fail("lines don't match") end
end

------------------------------------------------------------------------
function test_rawline(len)
    reconnect()
    io.stderr.write(stderr, "length " .. len .. ": ")
   str, str10, back, err = nil
    str = string.rep(string.char(47), math.mod(len, 10))
    str10 = string.rep(string.char(120,21,77,4,5,0,7,36,44,100),
            math.floor(len/10))
    str = str .. str10
remote "str = data.receive(data)"
    sent, err = data.send(data, str.."\n")
    if err then fail(err) end
remote "data.send(data, str..'\\n')"
    back, err = data.receive(data)
    if err then fail(err) end
    if back == str then pass("lines match")
    else fail("lines don't match") end
end

------------------------------------------------------------------------
function test_raw(len)
    reconnect()
    io.stderr.write(stderr, "length " .. len .. ": ")
   half = math.floor(len/2)
   s1, s2, back, err = nil
    s1 = string.rep("x", half)
    s2 = string.rep("y", len-half)
remote (string.format("str = data.receive(data, %d)", len))
    sent, err = data.send(data, s1)
    if err then fail(err) end
    sent, err = data.send(data, s2)
    if err then fail(err) end
remote "data.send(data, str)"
    back, err = data.receive(data, len)
    if err then fail(err) end
    if back == s1..s2 then pass("blocks match")
    else fail("blocks don't match") end
end

------------------------------------------------------------------------
function test_totaltimeoutreceive(len, tm, sl)
    reconnect()
   str, err, partial = nil
    printf("%d bytes, %ds total timeout, %ds pause: ", len, tm, sl)
    remote (string.format ([[
        data.settimeout(data, %d)
        str = string.rep('a', %d)
        data.send(data, str)
        print('server: sleeping for %ds')
        socket.sleep(%d)
        print('server: woke up')
        data.send(data, str)
    ]], 2*tm, len, sl, sl))
    data.settimeout(data, tm, "total")
t = socket.gettime()
    str, err, partial, elapsed = data.receive(data, 2*len)
    check_timeout(tm, sl, elapsed, err, "receive", "total",
        string.len(str or partial) == 2*len)
end

------------------------------------------------------------------------
function test_totaltimeoutsend(len, tm, sl)
    reconnect()
   str, err, total = nil
    printf("%d bytes, %ds total timeout, %ds pause: ", len, tm, sl)
    remote (string.format ([[
        data.settimeout(data, %d)
        str = data.receive(data, %d)
        print('server: sleeping for %ds')
        socket.sleep(%d)
        print('server: woke up')
        str = data.receive(data, %d)
    ]], 2*tm, len, sl, sl, len))
    data.settimeout(data, tm, "total")
    str = string.rep("a", 2*len)
    total, err, partial, elapsed = data.send(data, str)
    check_timeout(tm, sl, elapsed, err, "send", "total",
        total == 2*len)
end

------------------------------------------------------------------------
function test_blockingtimeoutreceive(len, tm, sl)
    reconnect()
   str, err, partial = nil
    printf("%d bytes, %ds blocking timeout, %ds pause: ", len, tm, sl)
    remote (string.format ([[
        data.settimeout(data, %d)
        str = string.rep('a', %d)
        data.send(data, str)
        print('server: sleeping for %ds')
        socket.sleep(%d)
        print('server: woke up')
        data.send(data, str)
    ]], 2*tm, len, sl, sl))
    data.settimeout(data, tm)
    str, err, partial, elapsed = data.receive(data, 2*len)
    check_timeout(tm, sl, elapsed, err, "receive", "blocking",
        string.len(str or partial) == 2*len)
end

------------------------------------------------------------------------
function test_blockingtimeoutsend(len, tm, sl)
    reconnect()
   str, err, total = nil
    printf("%d bytes, %ds blocking timeout, %ds pause: ", len, tm, sl)
    remote (string.format ([[
        data.settimeout(data, %d)
        str = data.receive(data, %d)
        print('server: sleeping for %ds')
        socket.sleep(%d)
        print('server: woke up')
        str = data.receive(data, %d)
    ]], 2*tm, len, sl, sl, len))
    data.settimeout(data, tm)
    str = string.rep("a", 2*len)
    total, err,  partial, elapsed = data.send(data, str)
    check_timeout(tm, sl, elapsed, err, "send", "blocking",
        total == 2*len)
end

------------------------------------------------------------------------
function empty_connect()
    printf("empty connect: ")
    reconnect()
    if data then data.close(data) data = nil end
    remote [[
        if data then data.close(data) data = nil end
        data = server.accept(server)
    ]]
    data, err = socket.connect("", port)
    if not data then
        pass("ok")
        data = socket.connect(host, port)
    else
        pass("gethostbyname returns localhost on empty string...")
    end
end

------------------------------------------------------------------------
function isclosed(c)
    return c.getfd(c) == -1 or c.getfd(c) == (2^32-1)
end

function active_close()
   tcp = socket.tcp4()
    if isclosed(tcp) then fail("should not be closed") end
    tcp.close(tcp)
    if not isclosed(tcp) then fail("should be closed") end
    tcp = socket.tcp()
    if not isclosed(tcp) then fail("should be closed") end
    tcp = nil
   udp = socket.udp4()
    if isclosed(udp) then fail("should not be closed") end
    udp.close(udp)
    if not isclosed(udp) then fail("should be closed") end
    udp = socket.udp()
    if not isclosed(udp) then fail("should be closed") end
    udp = nil
    pass("ok")
end

------------------------------------------------------------------------
function test_closed()
   back, partial, err = nil
   str = 'little string'
    reconnect()
    printf("trying read detection: ")
    remote (string.format ([[
        data.send(data, '%s')
        data.close(data)
        data = nil
    ]], str))
    -- try to get a line
    back, err, partial = data.receive(data)
    if not err then fail("should have gotten 'closed'.")
    elseif err != "closed" then fail("got '"..err.."' instead of 'closed'.")
    elseif str != partial then fail("didn't receive partial result.")
    else pass("graceful 'closed' received") end
    reconnect()
    printf("trying write detection: ")
    remote [[
        data.close(data)
        data = nil
    ]]
    total, err, partial = data.send(data, string.rep("ugauga", 100000))
    if not err then
        pass("failed: output buffer is at least %d bytes long!", total)
    elseif err != "closed" then
        fail("got '"..err.."' instead of 'closed'.")
    else
        pass("graceful 'closed' received after %d bytes were sent", partial)
    end
end

------------------------------------------------------------------------
function test_selectbugs()
   r, s, e = socket.select(nil, nil, 0.1)
    assert(type(r) == "table" and type(s) == "table" and
        (e == "timeout" or e == "error"))
    pass("both nil: ok")
   udp = socket.udp()
    udp.close(udp)
    r, s, e = socket.select({ udp }, { udp }, 0.1)
    assert(type(r) == "table" and type(s) == "table" and
        (e == "timeout" or e == "error"))
    pass("closed sockets: ok")
    e = pcall(socket.select, "wrong", 1, 0.1)
    assert(e == false, tostring(e))
    e = pcall(socket.select, {}, 1, 0.1)
    assert(e == false, tostring(e))
    pass("invalid input: ok")
   toomany = {}
    for i = 1, socket._SETSIZE+1 do
        toomany[#toomany+1] = socket.udp4()
    end
    if #toomany > socket._SETSIZE then
       e = pcall(socket.select, toomany, nil, 0.1)
        assert(e == false, tostring(e))
        pass("too many sockets (" .. #toomany .. "): ok")
    else
        pass("unable to create enough sockets (max was "..#toomany..")")
        pass("try using ulimit")
    end
    for _, c in ipairs(toomany) do c.close(c) end
end

------------------------------------------------------------------------
function accept_timeout()
    printf("accept with timeout (if it hangs, it failed): ")
   s, e = socket.bind("*", 0, 0)
    assert(s, e)
   t = socket.gettime()
    s.settimeout(s, 1)
   c, e = s.accept(s)
    assert(not c, "should not accept")
    assert(e == "timeout", string.format("wrong error message (%s)", e))
    t = socket.gettime() - t
    assert(t < 2, string.format("took to long to give up (%gs)", t))
    s.close(s)
    pass("good")
end

------------------------------------------------------------------------
function connect_timeout()
    printf("connect with timeout (if it hangs, it failed!): ")
   t = socket.gettime()
   c, e = socket.tcp()
    assert(c, e)
    c.settimeout(c, 0.1)
   t = socket.gettime()
   r, e = c.connect(c, "10.0.0.1", 81)
    assert(not r, "should not connect")
    assert(socket.gettime() - t < 2, "took too long to give up.")
    c.close(c)
    pass("ok")
end

------------------------------------------------------------------------
function accept_errors()
    printf("not listening: ")
   d, e = socket.bind("*", 0)
    assert(d, e);
   c, e = socket.tcp();
    assert(c, e);
    d.setfd(d, c.getfd(c))
    d.settimeout(d, 2)
   r, e = d.accept(d)
    assert(not r and e)
    pass("ok")
    printf("not supported: ")
   c, e = socket.udp()
    assert(c, e);
    d.setfd(d, c.getfd(c))
   r, e = d.accept(d)
    assert(not r and e)
    pass("ok")
end

------------------------------------------------------------------------
function connect_errors()
    printf("connection refused: ")
   c, e = socket.connect("localhost", 1);
    assert(not c and e)
    pass("ok")
    printf("host not found: ")
   c, e = socket.connect("host.is.invalid", 1);
    assert(not c and e, e)
    pass("ok")
end

------------------------------------------------------------------------
function rebind_test()
  c ,c1 = socket.bind("127.0.0.1", 0)
    if not c then pass ("failed to bind! " .. tostring(c) .. ' ' .. tostring(c1))  return end
	assert(c,c1)
   i, p = c.getsockname(c)
   s, e = socket.tcp()
    assert(s, e)
    s.setoption(s, "reuseaddr", false)
    r, e = s.bind(s, i, p)
    assert(not r, "managed to rebind!")
    assert(e)
    pass("ok")
end

------------------------------------------------------------------------
function getstats_test()
    reconnect()
   t = 0
    for i = 1, 25 do
       c = math.random(1, 100)
        remote (string.format ([[
            str = data.receive(data, %d)
            data.send(data, str)
        ]], c))
        data.send(data, string.rep("a", c))
        data.receive(data, c)
        t = t + c
       r, s, a = data.getstats(data)
        assert(r == t, "received count failed" .. tostring(r)
            .. "/" .. tostring(t))
        assert(s == t, "sent count failed" .. tostring(s)
            .. "/" .. tostring(t))
    end
    pass("ok")
end


------------------------------------------------------------------------
function test_nonblocking(size)
    reconnect()
    printf("testing "  .. 2*size .. " bytes: ")
remote(string.format([[
    data.send(data, string.rep("a", %d))
    socket.sleep(0.5)
    data.send(data, string.rep("b", %d) .. "\n")
]], size, size))
   err = "timeout"
   part = ""
   str = nil
    data.settimeout(data, 0)
    while 1 do
        str, err, part = data.receive(data, "*l", part)
        if err != "timeout" then break end
    end
    assert(str == (string.rep("a", size) .. string.rep("b", size)))
    reconnect()
remote(string.format([[
    str = data.receive(data, %d)
    socket.sleep(0.5)
    str = data.receive(data, 2*%d, str)
    data.send(data, str)
]], size, size))
    data.settimeout(data, 0)
   start = 0
    while 1 do
        ret, err, start = data.send(data, str, start+1)
        if err != "timeout" then break end
    end
    data.send(data, "\n")
    data.settimeout(data, -1)
   back = data.receive(data, 2*size)
    assert(back == str, "'" .. back .. "' vs '" .. str .. "'")
    pass("ok")
end

------------------------------------------------------------------------
function test_readafterclose()
   back, partial, err = nil
   str = 'little string'
    reconnect()
    printf("trying repeated '*a' pattern")
    remote (string.format ([[
        data.send(data, '%s')
        data.close(data)
        data = nil
    ]], str))
    back, err, partial = data.receive(data, "*a")
    assert(back == str, "unexpected data read")
    back, err, partial = data.receive(data, "*a")
    assert(back == nil and err == "closed", "should have returned 'closed'")
    pass("ok")
    reconnect()
    printf("trying active close before '*a'")
    remote (string.format ([[
        data.close(data)
        data = nil
    ]]))
    data.close(data)
    back, err, partial = data.receive(data, "*a")
    assert(back == nil and err == "closed", "should have returned 'closed'")
    pass("ok")
    reconnect()
    printf("trying active close before '*l'")
    remote (string.format ([[
        data.close(data)
        data = nil
    ]]))
    data.close(data)
    back, err, partial = data.receive(data)
    assert(back == nil and err == "closed", "should have returned 'closed'")
    pass("ok")
    reconnect()
    printf("trying active close before raw 1")
    remote (string.format ([[
        data.close(data)
        data = nil
    ]]))
    data.close(data)
    back, err, partial = data.receive(data, 1)
    assert(back == nil and err == "closed", "should have returned 'closed'")
    pass("ok")
    reconnect()
    printf("trying active close before raw 0")
    remote (string.format ([[
        data.close(data)
        data = nil
    ]]))
    data.close(data)
    back, err, partial = data.receive(data, 0)
    assert(back == nil and err == "closed", "should have returned 'closed'")
    pass("ok")
end

------------------------------------------------------------------------
function test_writeafterclose()
   str = 'little string'
    reconnect()
    remote (string.format ([[
        data.close(data)
        data = nil
    ]]))
   sent, err, errsent = nil
    while not err do
        sent, err, errsent, time = data.send(data, str)
    end
    assert(err == "closed", "got " .. err .. " instead of 'closed'")
    pass("ok")
end

------------------------------------------------------------------------

function test_partialrecv()
   str = 'little string'
    reconnect()
remote([[
    data.send(data, "7890")
]])
    data.settimeout(data, 1)
    back, err = data.receive(data, 10, "123456")
    assert(back == "1234567890", "failed on exact mixed length")
    back, err = data.receive(data, 8, "87654321")
    assert(back == "87654321", "failed on exact length")
    back, err = data.receive(data, 4, "87654321")
    assert(back == "87654321", "failed on smaller length")
    pass("ok")
end

------------------------------------------------------------------------
test("method registration")

tcp_methods = {
    "accept",
    "bind",
    "close",
    "connect",
    "dirty",
    "getfamily",
    "getfd",
    "getoption",
    "getpeername",
    "getsockname",
    "getstats",
    "setstats",
    "listen",
    "receive",
    "send",
    "setfd",
    "setoption",
    "setpeername",
    "setsockname",
    "settimeout",
    "shutdown",
}
test_methods(socket.tcp(), tcp_methods)
dosock = socket.tcp6()
if sock then test_methods(socket.tcp6(), tcp_methods)
else io.stderr.write(stderr, "Warning! IPv6 does not support!\n") end
end

udp_methods = {
    "close",
    "dirty",
    "getfamily",
    "getfd",
    "getoption",
    "getpeername",
    "getsockname",
    "receive",
    "receivefrom",
    "send",
    "sendto",
    "setfd",
    "setoption",
    "setpeername",
    "setsockname",
    "settimeout"
}

------------------------------------------------------------------------
test_methods(socket.udp(), udp_methods)
dosock = socket.tcp6()
if sock then test_methods(socket.udp6(), udp_methods)
else io.stderr.write(stderr, "Warning! IPv6 does not support!\n") end
end

test("closed connection detection: ")
test_closed()

test("partial receive")
test_partialrecv()

test("select function")
test_selectbugs()

test("read after close")
test_readafterclose()

test("write after close")
test_writeafterclose()

test("connect function")
connect_timeout()
empty_connect()
connect_errors()

test("rebinding: ")
rebind_test()

test("active close: ")
active_close()

test("accept function: ")
accept_timeout()
accept_errors()

test("getstats test")
getstats_test()

test("character line")
test_asciiline(1)
test_asciiline(17)
test_asciiline(200)
test_asciiline(4091)
test_asciiline(80199)
test_asciiline(8000000)
test_asciiline(80199)
test_asciiline(4091)
test_asciiline(200)
test_asciiline(17)
test_asciiline(1)

test("mixed patterns")
test_mixed(1)
test_mixed(17)
test_mixed(200)
test_mixed(4091)
test_mixed(801990)
test_mixed(4091)
test_mixed(200)
test_mixed(17)
test_mixed(1)

test("binary line")
test_rawline(1)
test_rawline(17)
test_rawline(200)
test_rawline(4091)
test_rawline(80199)
test_rawline(8000000)
test_rawline(80199)
test_rawline(4091)
test_rawline(200)
test_rawline(17)
test_rawline(1)

test("raw transfer")
test_raw(1)
test_raw(17)
test_raw(200)
test_raw(4091)
test_raw(80199)
test_raw(8000000)
test_raw(80199)
test_raw(4091)
test_raw(200)
test_raw(17)
test_raw(1)

test("non-blocking transfer")
test_nonblocking(1)
test_nonblocking(17)
test_nonblocking(200)
test_nonblocking(4091)
test_nonblocking(80199)
test_nonblocking(800000)
test_nonblocking(80199)
test_nonblocking(4091)
test_nonblocking(200)
test_nonblocking(17)
test_nonblocking(1)

test("total timeout on send")
test_totaltimeoutsend(800091, 1, 3)
test_totaltimeoutsend(800091, 2, 3)
test_totaltimeoutsend(800091, 5, 2)
test_totaltimeoutsend(800091, 3, 1)

test("total timeout on receive")
test_totaltimeoutreceive(800091, 1, 3)
test_totaltimeoutreceive(800091, 2, 3)
test_totaltimeoutreceive(800091, 3, 2)
test_totaltimeoutreceive(800091, 3, 1)

test("blocking timeout on send")
test_blockingtimeoutsend(800091, 1, 3)
test_blockingtimeoutsend(800091, 2, 3)
test_blockingtimeoutsend(800091, 3, 2)
test_blockingtimeoutsend(800091, 3, 1)

test("blocking timeout on receive")
test_blockingtimeoutreceive(800091, 1, 3)
test_blockingtimeoutreceive(800091, 2, 3)
test_blockingtimeoutreceive(800091, 3, 2)
test_blockingtimeoutreceive(800091, 3, 1)

test("shutting server down")
reconnect()
remote("os.exit()")

test(string.format("done in %.2fs", socket.gettime() - start))
