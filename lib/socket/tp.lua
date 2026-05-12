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
   line, err = getmetatable(c).__index.receive(c)
   reply = line
    if (err != nil and err != false) then return nil, err end
    code, sep = socket.skip(2, string.find(line, "^(%d%d%d)(.?)"))
    if (code == nil or code == false) then return nil, "invalid server reply" end
    if sep == "-" then -- reply is multiline
        while true do
            line, err = getmetatable(c).__index.receive(c)
            if (err != nil and err != false) then return nil, err end
            current, sep = socket.skip(2, string.find(line, "^(%d%d%d)(.?)"))
            reply = reply .. "\n" .. line
        -- reply ends with same code
            if code == current and sep == " " then break end
        end
    end
    return code, reply
end

-- metatable for sock object
metat = ({ __index = ({}) })

function metat.__index.getpeername(self)
    return getmetatable(self.c).__index.getpeername(self.c)
end

function metat.__index.getsockname(self)
    return getmetatable(self.c).__index.getpeername(self.c)
end

function metat.__index.check(self, ok)
   code, reply = get_reply(self.c)
    if (code == nil or code == false) then return nil, reply end
    if base.type(ok) != "function" then
        if base.type(ok) == "table" then
            for i, v in base.ipairs(ok) do
                if (string.find(code, v) != nil and string.find(code, v) != false) then
                    return base.tonumber(code), reply
                end
            end
            return nil, reply
        else
            if (string.find(code, ok) != nil and string.find(code, ok) != false) then return base.tonumber(code), reply
            else return nil, reply end
        end
    else return ok(base.tonumber(code), reply) end
end

function metat.__index.command(self, cmd, arg)
    cmd = string.upper(cmd)
    if (arg != nil and arg != false) then
        return getmetatable(self.c).__index.send(self.c, cmd .. " " .. arg.. "\r\n")
    else
        return getmetatable(self.c).__index.send(self.c, cmd .. "\r\n")
    end
end

function metat.__index.sink(self, snk, pat)
   chunk, err = getmetatable(self.c).__index.receive(self.c, pat)
    return snk(chunk, err)
end

function metat.__index.send(self, data)
    return getmetatable(self.c).__index.send(self.c, data)
end

function metat.__index.receive(self, pat)
    return getmetatable(self.c).__index.receive(self.c, pat)
end

function metat.__index.getfd(self)
    return getmetatable(self.c).__index.getfd(self.c)
end

function metat.__index.dirty(self)
    return getmetatable(self.c).__index.dirty(self.c)
end

function metat.__index.getcontrol(self)
    return self.c
end

function metat.__index.source(self, source, step)
   sink = socket.sink("keep-open", self.c)
   ret, err = ltn12.pump.all(source, sink, (((step != nil and step != false) and step) or ltn12.pump.step))
    return ret, err
end

-- closes the underlying c
function metat.__index.close(self)
    getmetatable(self.c).__index.close(self.c)
    return 1
end

-- connect with server and return c object
function _M.connect(host, port, timeout, create)
   c, e = (((create != nil and create != false) and create) or socket.tcp)()
    if (c == nil or c == false) then return nil, e end
    getmetatable(c).__index.settimeout(c, (((timeout != nil and timeout != false) and timeout) or _M.TIMEOUT))
   r, e = getmetatable(c).__index.connect(c, host, port)
    if (r == nil or r == false) then
        getmetatable(c).__index.close(c)
        return nil, e
    end
    return base.setmetatable(({c = c}), metat)
end

return _M
