---------------------------------------------------------------------------
-- LuaSec 0.6
-- Copyright (C) 2009-2016 Bruno Silvestre
--
-- https.lua - HTTPS (built on top of LuaSocket http.lua)
---------------------------------------------------------------------------

socket = require("socket")
ssl    = require("ssl")
http   = require("socket.http")
url    = require("socket.url")
ltn12  = require("ltn12")
base   = _G

_M = ({})

-- For procedural calls
metat = ({ __index = ({}) })

function tcp()
   params_tcp = ({})
   conn_tcp = socket.tcp()
    return base.setmetatable(({
      c = conn_tcp,
      s = nil,
      p = params_tcp,
      try = socket.newtry(conn_tcp)
    }), metat)
end

function metat.__index.connect(self, host, port)
    return getmetatable(self.c).__index.connect(self.c, host, port)
end

function metat.__index.send(self, data, i, j)
    if (self.s != nil and self.s != false) then
        return getmetatable(self.s).__index.send(self.s, data, i, j)
    end
    return getmetatable(self.c).__index.send(self.c, data, i, j)
end

function metat.__index.receive(self, pattern, prefix)
    if (self.s != nil and self.s != false) then
        return getmetatable(self.s).__index.receive(self.s, pattern, prefix)
    end
    return getmetatable(self.c).__index.receive(self.c, pattern, prefix)
end

function metat.__index.close(self)
    if (self.s != nil and self.s != false) then
        getmetatable(self.s).__index.close(self.s)
    end
    return getmetatable(self.c).__index.close(self.c)
end

function metat.__index.settimeout(self, value, mode)
    return getmetatable(self.c).__index.settimeout(self.c, value, mode)
end

function metat.__index.setoption(self, option, value)
    return getmetatable(self.c).__index.setoption(self.c, option, value)
end

function metat.__index.setparams(self, params)
    self.p = params
end

function metat.__index.dohandshake(self)
   s_wrap, err_wrap = ssl.wrap(self.c, self.p)
    if (s_wrap == nil or s_wrap == false) then return nil, err_wrap end
    self.s = s_wrap
    return getmetatable(self.s).__index.dohandshake(self.s)
end

function metat.__index.getpeercertificate(self)
    if (self.s != nil and self.s != false) then
        return getmetatable(self.s).__index.getpeercertificate(self.s)
    end
    return nil
end

function metat.__index.getpeerverification(self)
    if (self.s != nil and self.s != false) then
        return getmetatable(self.s).__index.getpeerverification(self.s)
    end
    return nil
end

-- Default configuration for LuaSec
_M.PORT = 443

function _M.request(url_val, body_val)
    parsed_https = ({})
    if (base.type(url_val) == "string") then
        parsed_https = url.parse(url_val)
    else
        parsed_https = url_val
        if (parsed_https.url != nil and parsed_https.url != false) then
            parsed_from_url = url.parse(parsed_https.url)
            for i_upd, v_upd in base.pairs(parsed_from_url) do
                if (parsed_https[i_upd] == nil or parsed_https[i_upd] == false) then
                    parsed_https[i_upd] = v_upd
                end
            end
        end
    end
    
    if (parsed_https.scheme != "https") then
        return nil, "invalid protocol"
    end
    
   host_https = parsed_https.host
   port_https = parsed_https.port or _M.PORT
   
   create_https = function()
       c_https = tcp()
       
       -- DEFAULT SSL PARAMS
       sslparams_https = parsed_https.sslparams or ({})
       if (sslparams_https.protocol == nil or sslparams_https.protocol == false) then
           sslparams_https.protocol = "any"
       end
       if (sslparams_https.mode == nil or sslparams_https.mode == false) then
           sslparams_https.mode = "client"
       end
       if (sslparams_https.verify == nil or sslparams_https.verify == false) then
           sslparams_https.verify = "none"
       end
       if (sslparams_https.options == nil or sslparams_https.options == false) then
           sslparams_https.options = "all"
       end
       
       getmetatable(c_https).__index.setparams(c_https, sslparams_https)
       
       -- Wrapped create function for http.lua
       obj_https = ({
           c = c_https,
           connect = function(self_c, h, p)
               res_conn, err_conn = getmetatable(self_c.c).__index.connect(self_c.c, h, p)
               if (res_conn == nil or res_conn == false) then return nil, err_conn end
               return getmetatable(self_c.c).__index.dohandshake(self_c.c)
           end,
           send = function(self_c, data, i, j)
               return getmetatable(self_c.c).__index.send(self_c.c, data, i, j)
           end,
           receive = function(self_c, pattern, prefix)
               return getmetatable(self_c.c).__index.receive(self_c.c, pattern, prefix)
           end,
           close = function(self_c)
               return getmetatable(self_c.c).__index.close(self_c.c)
           end,
           settimeout = function(self_c, value, mode)
               return getmetatable(self_c.c).__index.settimeout(self_c.c, value, mode)
           end
       })
       mt_https = ({ __index = obj_https })
       return base.setmetatable(obj_https, mt_https)
   end
   
   parsed_https.create = create_https
   return http.request(parsed_https, body_val)
end

return _M
