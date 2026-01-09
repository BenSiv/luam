-----------------------------------------------------------------------------
-- FTP support for the Lua language
-- LuaSocket toolkit.
-- Author: Diego Nehab
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Declare module and import dependencies
-----------------------------------------------------------------------------
base = _G
table = require("table")
string = require("string")
math = require("math")
socket = require("socket")
url = require("socket.url")
tp = require("socket.tp")
ltn12 = require("ltn12")
socket.ftp = {}
_M = socket.ftp
-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
-- timeout in seconds before the program gives up on a connection
_M.TIMEOUT = 60
-- default port for ftp service
PORT = 21
-- this is the default anonymous password. used when no password is
-- provided in url. should be changed to your e-mail.
_M.USER = "ftp"
_M.PASSWORD = "anonymous@anonymous.org"

-----------------------------------------------------------------------------
-- Low level FTP API
-----------------------------------------------------------------------------
metat = { __index = {} }

function _M.open(server, port, create)
   tp = socket.try(tp.connect(server, port or PORT, _M.TIMEOUT, create))
   f = base.setmetatable({ tp = tp }, metat)
    -- make sure everything gets closed in an exception
    f.try = socket.newtry(function() f.close(f) end)
    return f
end

function metat.__index.portconnect(__index)
    self.try(self.server.settimeout(server, _M.TIMEOUT))
    self.data = self.try(self.server.accept(server))
    self.try(self.data.settimeout(data, _M.TIMEOUT))
end

function metat.__index.pasvconnect(__index)
    self.data = self.try(socket.tcp())
    self.try(self.data.settimeout(data, _M.TIMEOUT))
    self.try(self.data.connect(data, self.pasvt.address, self.pasvt.port))
end

function metat.__index.login(__index, user, password)
    self.try(self.tp.command(tp, "user", user or _M.USER))
   code, _ = self.try(self.tp:check{"2..", 331})
    if code == 331 then
        self.try(self.tp.command(tp, "pass", password or _M.PASSWORD))
        self.try(self.tp.check(tp, "2.."))
    end
    return 1
end

function metat.__index.pasv(__index)
    self.try(self.tp.command(tp, "pasv"))
   _, reply = self.try(self.tp.check(tp, "2.."))
   pattern = "(%d+)%D(%d+)%D(%d+)%D(%d+)%D(%d+)%D(%d+)"
   a, b, c, d, p1, p2 = socket.skip(2, string.find(reply, pattern))
    self.try(a and b and c and d and p1 and p2, reply)
    self.pasvt = {
        address = string.format("%d.%d.%d.%d", a, b, c, d),
        port = p1*256 + p2
    }
    if self.server then
        self.server.close(server)
        self.server = nil
    end
    return self.pasvt.address, self.pasvt.port
end

function metat.__index.epsv(__index)
    self.try(self.tp.command(tp, "epsv"))
   _, reply = self.try(self.tp.check(tp, "229"))
   pattern = "%((.)(.-)%1(.-)%1(.-)%1%)"
   _, _, _, port = string.match(reply, pattern)
    self.try(port, "invalid epsv response")
    self.pasvt = {
        address = self.tp.getpeername(tp),
        port = port
    }
    if self.server then
        self.server.close(server)
        self.server = nil
    end
    return self.pasvt.address, self.pasvt.port
end


function metat.__index.port(__index, address, port)
    self.pasvt = nil
    if not address then
        address = self.try(self.tp.getsockname(tp))
        self.server = self.try(socket.bind(address, 0))
        address, port = self.try(self.server.getsockname(server))
        self.try(self.server.settimeout(server, _M.TIMEOUT))
    end
   pl = math.mod(port, 256)
   ph = (port - pl)/256
   arg = string.gsub(string.format("%s,%d,%d", address, ph, pl), "%.", ",")
    self.try(self.tp.command(tp, "port", arg))
    self.try(self.tp.check(tp, "2.."))
    return 1
end

function metat.__index.eprt(__index, family, address, port)
    self.pasvt = nil
    if not address then
        address = self.try(self.tp.getsockname(tp))
        self.server = self.try(socket.bind(address, 0))
        address, port = self.try(self.server.getsockname(server))
        self.try(self.server.settimeout(server, _M.TIMEOUT))
    end
   arg = string.format("|%s|%s|%d|", family, address, port)
    self.try(self.tp.command(tp, "eprt", arg))
    self.try(self.tp.check(tp, "2.."))
    return 1
end


function metat.__index.send(__index, sendt)
    self.try(self.pasvt or self.server, "need port or pasv first")
    -- if there is a pasvt table, we already sent a PASV command
    -- we just get the data connection into self.data
    if self.pasvt then self.pasvconnect(self) end
    -- get the transfer argument and command
   argument = sendt.argument or
        url.unescape(string.gsub(sendt.path or "", "^[/\\]", ""))
    if argument == "" then argument = nil end
   command = sendt.command or "stor"
    -- send the transfer command and check the reply
    self.try(self.tp.command(tp, command, argument))
   code, _ = self.try(self.tp:check{"2..", "1.."})
    -- if there is not a pasvt table, then there is a server
    -- and we already sent a PORT command
    if not self.pasvt then self.portconnect(self) end
    -- get the sink, source and step for the transfer
   step = sendt.step or ltn12.pump.step
   readt = { self.tp }
   checkstep = function(src, snk)
        -- check status in control connection while downloading
       readyt = socket.select(readt, nil, 0)
        if readyt[tp] then code = self.try(self.tp.check(tp, "2..")) end
        return step(src, snk)
    end
   sink = socket.sink("close-when-done", self.data)
    -- transfer all data and check error
    self.try(ltn12.pump.all(sendt.source, sink, checkstep))
    if string.find(code, "1..") then self.try(self.tp.check(tp, "2..")) end
    -- done with data connection
    self.data.close(data)
    -- find out how many bytes were sent
   sent = socket.skip(1, self.data.getstats(data))
    self.data = nil
    return sent
end

function metat.__index.receive(__index, recvt)
    self.try(self.pasvt or self.server, "need port or pasv first")
    if self.pasvt then self.pasvconnect(self) end
   argument = recvt.argument or
        url.unescape(string.gsub(recvt.path or "", "^[/\\]", ""))
    if argument == "" then argument = nil end
   command = recvt.command or "retr"
    self.try(self.tp.command(tp, command, argument))
   code,reply = self.try(self.tp:check{"1..", "2.."})
    if (code >= 200) and (code <= 299) then
        recvt.sink(reply)
        return 1
    end
    if not self.pasvt then self.portconnect(self) end
   source = socket.source("until-closed", self.data)
   step = recvt.step or ltn12.pump.step
    self.try(ltn12.pump.all(source, recvt.sink, step))
    if string.find(code, "1..") then self.try(self.tp.check(tp, "2..")) end
    self.data.close(data)
    self.data = nil
    return 1
end

function metat.__index.cwd(__index, dir)
    self.try(self.tp.command(tp, "cwd", dir))
    self.try(self.tp.check(tp, 250))
    return 1
end

function metat.__index.type(__index, type)
    self.try(self.tp.command(tp, "type", type))
    self.try(self.tp.check(tp, 200))
    return 1
end

function metat.__index.greet(__index)
   code = self.try(self.tp:check{"1..", "2.."})
    if string.find(code, "1..") then self.try(self.tp.check(tp, "2..")) end
    return 1
end

function metat.__index.quit(__index)
    self.try(self.tp.command(tp, "quit"))
    self.try(self.tp.check(tp, "2.."))
    return 1
end

function metat.__index.close(__index)
    if self.data then self.data.close(data) end
    if self.server then self.server.close(server) end
    return self.tp.close(tp)
end

-----------------------------------------------------------------------------
-- High level FTP API
-----------------------------------------------------------------------------
function override(t)
    if t.url then
       u = url.parse(t.url)
        for i,v in base.pairs(t) do
            u[i] = v
        end
        return u
    else return t end
end

function tput(putt)
    putt = override(putt)
    socket.try(putt.host, "missing hostname")
   f = _M.open(putt.host, putt.port, putt.create)
    f.greet(f)
    f.login(f, putt.user, putt.password)
    if putt.type then f.type(f, putt.type) end
    f.epsv(f)
   sent = f.send(f, putt)
    f.quit(f)
    f.close(f)
    return sent
end

default = {
    path = "/",
    scheme = "ftp"
}

function genericform(u)
   t = socket.try(url.parse(u, default))
    socket.try(t.scheme == "ftp", "wrong scheme '" .. t.scheme .. "'")
    socket.try(t.host, "missing hostname")
   pat = "^type=(.)$"
    if t.params then
        t.type = socket.skip(2, string.find(t.params, pat))
        socket.try(t.type == "a" or t.type == "i",
            "invalid type '" .. t.type .. "'")
    end
    return t
end

_M.genericform = genericform

function sput(u, body)
   putt = genericform(u)
    putt.source = ltn12.source.string(body)
    return tput(putt)
end

_M.put = socket.protect(function(putt, body)
    if base.type(putt) == "string" then return sput(putt, body)
    else return tput(putt) end
end)

function tget(gett)
    gett = override(gett)
    socket.try(gett.host, "missing hostname")
   f = _M.open(gett.host, gett.port, gett.create)
    f.greet(f)
    f.login(f, gett.user, gett.password)
    if gett.type then f.type(f, gett.type) end
    f.epsv(f)
    f.receive(f, gett)
    f.quit(f)
    return f.close(f)
end

function sget(u)
   gett = genericform(u)
   t = {}
    gett.sink = ltn12.sink.table(t)
    tget(gett)
    return table.concat(t)
end

_M.command = socket.protect(function(cmdt)
    cmdt = override(cmdt)
    socket.try(cmdt.host, "missing hostname")
    socket.try(cmdt.command, "missing command")
   f = _M.open(cmdt.host, cmdt.port, cmdt.create)
    f.greet(f)
    f.login(f, cmdt.user, cmdt.password)
    if type(cmdt.command) == "table" then
       argument = cmdt.argument or {}
       check = cmdt.check or {}
        for i,cmd in ipairs(cmdt.command) do
            f.try(f.tp.command(tp, cmd, argument[i]))
            if check[i] then f.try(f.tp.check(tp, check[i])) end
        end
    else
        f.try(f.tp.command(tp, cmdt.command, cmdt.argument))
        if cmdt.check then f.try(f.tp.check(tp, cmdt.check)) end
    end
    f.quit(f)
    return f.close(f)
end)

_M.get = socket.protect(function(gett)
    if base.type(gett) == "string" then return sget(gett)
    else return tget(gett) end
end)

return _M
