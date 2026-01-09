-----------------------------------------------------------------------------
-- Unified SMTP/FTP subsystem
-- LuaSocket toolkit.
-- Author: Diego Nehab
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Declare module and import dependencies
-----------------------------------------------------------------------------
base = _G
string = require("string")
socket = require("socket")
ltn12 = require("ltn12")

socket.tp = {}
_M = socket.tp

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
_M.TIMEOUT = 60

-----------------------------------------------------------------------------
-- Implementation
-----------------------------------------------------------------------------
-- gets server reply (works for SMTP and FTP)
function get_reply(c)
   code, current, sep = nil
   line, err = c.receive(c)
   reply = line
    if err then return nil, err end
    code, sep = socket.skip(2, string.find(line, "^(%d%d%d)(.?)"))
    if not code then return nil, "invalid server reply" end
    if sep == "-" then -- reply is multiline
        repeat
            line, err = c.receive(c)
            if err then return nil, err end
            current, sep = socket.skip(2, string.find(line, "^(%d%d%d)(.?)"))
            reply = reply .. "\n" .. line
        -- reply ends with same code
        until code == current and sep == " "
    end
    return code, reply
end

-- metatable for sock object
metat = { __index = {} }

function metat.__index.getpeername(__index)
    return self.c.getpeername(c)
end

function metat.__index.getsockname(__index)
    return self.c.getpeername(c)
end

function metat.__index.check(__index, ok)
   code, reply = get_reply(self.c)
    if not code then return nil, reply end
    if base.type(ok) != "function" then
        if base.type(ok) == "table" then
            for i, v in base.ipairs(ok) do
                if string.find(code, v) then
                    return base.tonumber(code), reply
                end
            end
            return nil, reply
        else
            if string.find(code, ok) then return base.tonumber(code), reply
            else return nil, reply end
        end
    else return ok(base.tonumber(code), reply) end
end

function metat.__index.command(__index, cmd, arg)
    cmd = string.upper(cmd)
    if arg then
        return self.c.send(c, cmd .. " " .. arg.. "\r\n")
    else
        return self.c.send(c, cmd .. "\r\n")
    end
end

function metat.__index.sink(__index, snk, pat)
   chunk, err = self.c.receive(c, pat)
    return snk(chunk, err)
end

function metat.__index.send(__index, data)
    return self.c.send(c, data)
end

function metat.__index.receive(__index, pat)
    return self.c.receive(c, pat)
end

function metat.__index.getfd(__index)
    return self.c.getfd(c)
end

function metat.__index.dirty(__index)
    return self.c.dirty(c)
end

function metat.__index.getcontrol(__index)
    return self.c
end

function metat.__index.source(__index, source, step)
   sink = socket.sink("keep-open", self.c)
   ret, err = ltn12.pump.all(source, sink, step or ltn12.pump.step)
    return ret, err
end

-- closes the underlying c
function metat.__index.close(__index)
    self.c.close(c)
    return 1
end

-- connect with server and return c object
function _M.connect(host, port, timeout, create)
   c, e = (create or socket.tcp)()
    if not c then return nil, e end
    c.settimeout(c, timeout or _M.TIMEOUT)
   r, e = c.connect(c, host, port)
    if not r then
        c.close(c)
        return nil, e
    end
    return base.setmetatable({c = c}, metat)
end

return _M
