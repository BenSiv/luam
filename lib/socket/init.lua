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
    if (addrinfo == nil or addrinfo == false) then return nil, err end
   sock, res = nil, nil
    err = "no info on address"
    for i, alt in base.ipairs(addrinfo) do
        if alt.family == "inet" then
            sock, err = socket.tcp4()
        else
            sock, err = socket.tcp6()
        end
        if (sock == nil or sock == false) then return nil, err end
        getmetatable(sock).__index.setoption(sock, "reuseaddr", true)
        res, err = getmetatable(sock).__index.bind(sock, alt.addr, port)
        if (res == nil or res == false) then
            getmetatable(sock).__index.close(sock)
        else
            res, err = getmetatable(sock).__index.listen(sock, backlog)
            if (res == nil or res == false) then
                getmetatable(sock).__index.close(sock)
            else
                return sock
            end
        end
    end
    return nil, err
end

_M.try = _M.newtry()

function _M.choose(tbl)
    return function(name, opt1, opt2)
        if base.type(name) != "string" then
            name, opt1, opt2 = "default", name, opt1
        end
       f = tbl[(((name != nil and name != false) and name) or "nil")]
        if (f == nil or f == false) then base.error("unknown key (".. base.tostring(name) ..")", 3)
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
    return base.setmetatable(({
        getfd = function() return getmetatable(sock).__index.getfd(sock) end,
        dirty = function() return getmetatable(sock).__index.dirty(sock) end
    }), ({
        __call = function(self, chunk, err)
            if (chunk == nil or chunk == false) then
                getmetatable(sock).__index.close(sock)
                return 1
            else return getmetatable(sock).__index.send(sock, chunk) end
        end
    }))
end

sinkt["keep-open"] = function(sock)
    return base.setmetatable(({
        getfd = function() return getmetatable(sock).__index.getfd(sock) end,
        dirty = function() return getmetatable(sock).__index.dirty(sock) end
    }), ({
        __call = function(self, chunk, err)
            if (chunk != nil and chunk != false) then return getmetatable(sock).__index.send(sock, chunk)
            else return 1 end
        end
    }))
end

sinkt["default"] = sinkt["keep-open"]

_M.sink = _M.choose(sinkt)

sourcet["by-length"] = function(sock, length)
    return base.setmetatable(({
        getfd = function() return getmetatable(sock).__index.getfd(sock) end,
        dirty = function() return getmetatable(sock).__index.dirty(sock) end
    }), ({
        __call = function()
            if length <= 0 then return nil end
           size = math.min(socket.BLOCKSIZE, length)
           chunk, err = getmetatable(sock).__index.receive(sock, size)
            if (err != nil and err != false) then return nil, err end
            length = length - string.len(chunk)
            return chunk
        end
    }))
end

sourcet["until-closed"] = function(sock)
   done = nil
    return base.setmetatable(({
        getfd = function() return getmetatable(sock).__index.getfd(sock) end,
        dirty = function() return getmetatable(sock).__index.dirty(sock) end
    }), ({
        __call = function()
            if (done != nil and done != false) then return nil end
           chunk, err, partial = getmetatable(sock).__index.receive(sock, socket.BLOCKSIZE)
            if (err == nil or err == false) then return chunk
            elseif err == "closed" then
                getmetatable(sock).__index.close(sock)
                done = 1
                return partial
            else return nil, err end
        end
    }))
end

-- HTTP chunked
sourcet["http-chunked"] = function(sock)
   done = nil
    return base.setmetatable(({
        getfd = function() return getmetatable(sock).__index.getfd(sock) end,
        dirty = function() return getmetatable(sock).__index.dirty(sock) end
    }), ({
        __call = function()
            if (done != nil and done != false) then return nil end
           line, err = getmetatable(sock).__index.receive(sock, "*l")
            if (err != nil and err != false) then return nil, err end
           size = base.tonumber(string.gsub(line, ";.*", ""), 16)
            if (size == nil or size == false) then return nil, "invalid chunk size" end
            if size > 0 then
               chunk, err = getmetatable(sock).__index.receive(sock, size)
                if (err != nil and err != false) then return nil, err end
                getmetatable(sock).__index.receive(sock, 2) -- skip \r\n
                return chunk
            else
                getmetatable(sock).__index.receive(sock, 2) -- skip \r\n
                done = 1
                return nil
            end
        end
    }))
end

sinkt["http-chunked"] = function(sock)
    return base.setmetatable(({
        getfd = function() return getmetatable(sock).__index.getfd(sock) end,
        dirty = function() return getmetatable(sock).__index.dirty(sock) end
    }), ({
        __call = function(self, chunk, err)
            if (chunk == nil or chunk == false) then
                return getmetatable(sock).__index.send(sock, "0\r\n\r\n")
            end
           size = string.format("%x\r\n", string.len(chunk))
            return getmetatable(sock).__index.send(sock, size .. chunk .. "\r\n")
        end
    }))
end

sourcet["default"] = sourcet["until-closed"]

_M.source = _M.choose(sourcet)

return _M
