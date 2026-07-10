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

try    = socket.try

--
-- Module
--
_M = {
  _VERSION   = "1.3.2",
  _COPYRIGHT = "LuaSec 1.3.2 - Copyright (C) 2009-2023 PUC-Rio",
  PORT       = 443,
  TIMEOUT    = 60
}

-- TLS configuration
cfg = {
  protocol = "any",
  options  = {"all", "no_sslv2", "no_sslv3", "no_tlsv1"},
  verify   = "none",
}

--------------------------------------------------------------------
-- Auxiliar Functions
--------------------------------------------------------------------

-- Insert default HTTPS port.
function default_https_port(u)
   return url.build(url.parse(u, {port = _M.PORT}))
end

-- Convert an URL to a table according to Luasocket needs.
function urlstring_totable(url, body, result_table)
   method = "GET"
   if body != nil and body != false then
      method = "POST"
   end
   url = {
      url = default_https_port(url),
      method = method,
      sink = ltn12.sink.table(result_table)
   }
   if ((body != nil and body != false)) then
      url.source = ltn12.source.string(body)
      url.headers = {
         ["content-length"] = #body,
         ["content-type"] = "application/x-www-form-urlencoded",
      }
   end
   return url
end

-- Forward calls to the real connection object.
function reg(conn)
  mt = getmetatable(conn.sock).__index
   for name, method in pairs(mt) do
      if (type(method) == "function") then
         conn[name] = function (self, ...)
                         return method(self.sock, ...)
                      end
      end
   end
end

-- Return a function which performs the SSL/TLS connection.
function tcp(params)
   if params == nil then
      params = {}
   end
   -- Default settings
   for k, v in pairs(cfg) do
      if params[k] == nil or params[k] == false then
         params[k] = v
      end
   end
   -- Force client mode
   params.mode = "client"
   -- 'create' function for LuaSocket
   return function ()
     conn = {}
      conn.sock = try(socket.tcp())
     st = getmetatable(conn.sock).__index.settimeout
      function conn.settimeout(conn, ...)
         return st(self.sock, _M.TIMEOUT)
      end
      -- Replace TCP's connection function
      function conn.connect(conn, host, port)
         try(self.sock.connect(sock, host, port))
         self.sock = try(ssl.wrap(self.sock, params))
         self.sock.sni(sock, host)
         self.sock.settimeout(sock, _M.TIMEOUT)
         try(self.sock.dohandshake(sock))
         reg(self)
         return 1
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
function request(url, body)
 result_table = {}
 stringrequest = type(url) == "string"
  if ((stringrequest != nil and stringrequest != false)) then
    url = urlstring_totable(url, body, result_table)
  else
    url.url = default_https_port(url.url)
  end
  if (http.PROXY != nil and http.PROXY != false) or (url.proxy != nil and url.proxy != false) then
    return nil, "proxy not supported"
  elseif (url.redirect != nil and url.redirect != false) then
    return nil, "redirect not supported"
  elseif ((url.create != nil and url.create != false)) then
    return nil, "create function not permitted"
  end
  -- New 'create' function to establish a secure connection
  url.create = tcp(url)
 res, code, headers, status = http.request(url)
  if (res != nil and res != false) and stringrequest then
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
