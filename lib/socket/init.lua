-----------------------------------------------------------------------------
-- LuaSocket helper module
-- Author: Diego Nehab
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Declare module and import dependencies
-----------------------------------------------------------------------------
base = _G
string = require("string")
math = require("math")
socket = require("socket.core")

_M = socket

-----------------------------------------------------------------------------
-- Exported auxiliar functions
-----------------------------------------------------------------------------
function _M.connect4(address, port, laddress, lport)
    return socket.connect(address, port, laddress, lport, "inet")
end

function _M.connect6(address, port, laddress, lport)
    return socket.connect(address, port, laddress, lport, "inet6")
end

function _M.bind(host, port, backlog)
    if host == "*" then host = "0.0.0.0" end
   addrinfo, err = socket.dns.getaddrinfo(host);
    if not addrinfo then return nil, err end
   sock, res = nil, nil
    err = "no info on address"
    for i, alt in base.ipairs(addrinfo) do
        if alt.family == "inet" then
            sock, err = socket.tcp4()
        else
            sock, err = socket.tcp6()
        end
        if not sock then return nil, err end
        sock.setoption(sock, "reuseaddr", true)
        res, err = sock.bind(sock, alt.addr, port)
        if not res then
            sock.close(sock)
        else
            res, err = sock.listen(sock, backlog)
            if not res then
                sock.close(sock)
            else
                return sock
            end
        end
    end
    return nil, err
end

_M.try = _M.newtry()

function _M.choose(table)
    return function(name, opt1, opt2)
        if base.type(name) != "string" then
            name, opt1, opt2 = "default", name, opt1
        end
       f = table[name or "nil"]
        if not f then base.error("unknown key (".. base.tostring(name) ..")", 3)
        else return f(opt1, opt2) end
    end
end

-----------------------------------------------------------------------------
-- Socket sources and sinks, conforming to LTN12
-----------------------------------------------------------------------------
-- create namespaces inside LuaSocket namespace
sourcet, sinkt = {}, {}
_M.sourcet = sourcet
_M.sinkt = sinkt

_M.BLOCKSIZE = 2048

sinkt["close-when-done"] = function(sock)
    return base.setmetatable({
        getfd = function() return sock.getfd(sock) end,
        dirty = function() return sock.dirty(sock) end
    }, {
        __call = function(self, chunk, err)
            if not chunk then
                sock.close(sock)
                return 1
            else return sock.send(sock, chunk) end
        end
    })
end

sinkt["keep-open"] = function(sock)
    return base.setmetatable({
        getfd = function() return sock.getfd(sock) end,
        dirty = function() return sock.dirty(sock) end
    }, {
        __call = function(self, chunk, err)
            if chunk then return sock.send(sock, chunk)
            else return 1 end
        end
    })
end

sinkt["default"] = sinkt["keep-open"]

_M.sink = _M.choose(sinkt)

sourcet["by-length"] = function(sock, length)
    return base.setmetatable({
        getfd = function() return sock.getfd(sock) end,
        dirty = function() return sock.dirty(sock) end
    }, {
        __call = function()
            if length <= 0 then return nil end
           size = math.min(socket.BLOCKSIZE, length)
           chunk, err = sock.receive(sock, size)
            if err then return nil, err end
            length = length - string.len(chunk)
            return chunk
        end
    })
end

sourcet["until-closed"] = function(sock)
   done = nil
    return base.setmetatable({
        getfd = function() return sock.getfd(sock) end,
        dirty = function() return sock.dirty(sock) end
    }, {
        __call = function()
            if done then return nil end
           chunk, err, partial = sock.receive(sock, socket.BLOCKSIZE)
            if not err then return chunk
            elseif err == "closed" then
                sock.close(sock)
                done = 1
                return partial
            else return nil, err end
        end
    })
end


sourcet["default"] = sourcet["until-closed"]

_M.source = _M.choose(sourcet)

return _M
