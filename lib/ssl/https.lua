----------------------------------------------------------------------------
-- LuaSec 1.3.2
--
-- Copyright (C) 2009-2023 PUC-Rio
--
-- Author: Pablo Musa
-- Author: Tomas Guisasola
---------------------------------------------------------------------------

socket = require("socket")
ssl    = require("ssl")
ltn12  = require("ltn12")
http   = require("socket.http")
url    = require("socket.url")

base   = _G
try    = socket.try

--
-- Module
--
_M = ({
  _VERSION   = "1.3.2",
  _COPYRIGHT = "LuaSec 1.3.2 - Copyright (C) 2009-2023 PUC-Rio",
  PORT       = 443,
  TIMEOUT    = 60
})

-- TLS configuration
cfg = ({
  protocol = "any",
  options  = ({"all", "no_sslv2", "no_sslv3", "no_tlsv1"}),
  verify   = "none",
})

--------------------------------------------------------------------
-- Auxiliar Functions
--------------------------------------------------------------------

-- Insert default HTTPS port.
function default_https_port(u)
   return url.build(url.parse(u, ({port = _M.PORT})))
end

-- Convert an URL to a table according to Luasocket needs.
function urlstring_totable(url_str, body, result_table)
   url_tbl = ({
      url = default_https_port(url_str),
      method = (((body != nil and body != false) and "POST") or "GET"),
      sink = ltn12.sink.table(result_table)
   })
   if (body != nil and body != false) then
      url_tbl.source = ltn12.source.string(body)
      url_tbl.headers = ({
         ["content-length"] = string.len(body),
         ["content-type"] = "application/x-www-form-urlencoded",
      })
   end
   return url_tbl
end

-- Forward calls to the real connection object.
function reg(conn)
  mt = getmetatable(conn.sock).__index
   for name, method in base.pairs(mt) do
      if type(method) == "function" then
         conn[name] = function (self, ...)
                          return method(self.sock, ...)
                       end
      end
   end
end

-- Return a function which performs the SSL/TLS connection.
function tcp(params)
   params = ((params != nil and params != false) and params) or ({})
   -- Default settings
   for k, v in base.pairs(cfg) do 
      params[k] = ((params[k] != nil and params[k] != false) and params[k]) or v
   end
   -- Force client mode
   params.mode = "client"
   -- 'create' function for LuaSocket
   return function ()
     conn = ({})
      conn.sock = try(socket.tcp())
     
      -- Replace TCP's connection function
      function conn.connect(self, host, port)
         -- Call connect on the underlying socket
         try(getmetatable(self.sock).__index.connect(self.sock, host, port))
         -- Wrap the socket with SSL
         self.sock = try(ssl.wrap(self.sock, params))
         -- Call SSL methods using metatable
         getmetatable(self.sock).__index.sni(self.sock, host)
         getmetatable(self.sock).__index.settimeout(self.sock, _M.TIMEOUT)
         try(getmetatable(self.sock).__index.dohandshake(self.sock))
         reg(self)
         return 1
      end
      
      function conn.settimeout(self, ...)
         return getmetatable(self.sock).__index.settimeout(self.sock, _M.TIMEOUT)
      end
      
      return conn
  end
end

--------------------------------------------------------------------
-- Main Function
--------------------------------------------------------------------

-- Make a HTTP request over secure connection.  This function receives
--  the same parameters of LuaSocket's HTTP module (except 'proxy' and
--  'redirect') plus LuaSec parameters.
--
-- @param url mandatory (string or table)
-- @param body optional (string)
-- @return (string if url == string or 1), code, headers, status
--
function request(url_val, body)
  result_table = ({})
  stringrequest = (type(url_val) == "string")
   if (stringrequest != nil and stringrequest != false) then
    url_val = urlstring_totable(url_val, body, result_table)
   else
    url_val.url = default_https_port(url_val.url)
   end
   if (http.PROXY != nil and http.PROXY != false) or (url_val.proxy != nil and url_val.proxy != false) then
    return nil, "proxy not supported"
   elseif (url_val.redirect != nil and url_val.redirect != false) then
    return nil, "redirect not supported"
   elseif (url_val.create != nil and url_val.create != false) then
    -- Special case for internal Luasocket calls
    if type(url_val.create) != "function" then
        return nil, "create function not permitted"
    end
   end
  -- New 'create' function to establish a secure connection
  url_val.create = tcp(url_val)
  res, code, headers, status = http.request(url_val)
   if (res != nil and res != false) and (stringrequest != nil and stringrequest != false) then
    return table.concat(result_table), code, headers, status
   end
  return res, code, headers, status
end

--------------------------------------------------------------------------------
-- Export module
--

_M.request = request
_M.tcp = tcp

return _M
