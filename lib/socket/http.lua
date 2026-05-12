-----------------------------------------------------------------------------
-- HTTP/1.1 client support for the Lua language.
-- LuaSocket toolkit.
-- Author: Diego Nehab
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Declare module and import dependencies
-------------------------------------------------------------------------------
socket = require("socket")
url = require("socket.url")
ltn12 = require("ltn12")
mime = require("mime")
string = require("string")
headers = require("socket.headers")
base = _G
table = require("table")

_M = ({})

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
_M.PORT = 80
_M.PROXY = nil
_M.TIMEOUT = 60
_M.USERAGENT = socket._VERSION

-----------------------------------------------------------------------------
-- Userful alternative to socket.try
-----------------------------------------------------------------------------
function _M.newtry(c_try)
    return function(res_try, err_try)
        if (res_try == nil or res_try == false) then
            if (c_try != nil and c_try != false) then c_try.close(c_try) end
            base.error(err_try, 0)
        end
        return res_try
    end
end

-----------------------------------------------------------------------------
-- Helper functions
-----------------------------------------------------------------------------
function adjusturi(parsed_uri)
   path_uri = (parsed_uri.path != nil and parsed_uri.path != false and parsed_uri.path) or "/"
    if (parsed_uri.query != nil and parsed_uri.query != false) then path_uri = path_uri .. "?" .. parsed_uri.query end
    return path_uri
end

function adjustproxy(p_proxy)
   encode_proxy = function(s_proxy) return mime.b64(s_proxy) end
    if (base.type(p_proxy) == "string") then
       proxy_res = url.parse(p_proxy)
       auth_res = (proxy_res.user and proxy_res.password) and "Basic " .. encode_proxy(proxy_res.user .. ":" .. proxy_res.password)
        return proxy_res.host, proxy_res.port or 3128, auth_res
    end
    return p_proxy.host, p_proxy.port or 3128, p_proxy.auth
end

function adjustheaders(host_h, port_h, method_h, uri_h, tosend_h)
   lower_h = function(s_h) return string.lower(s_h) end
   res_h = ({
        ["host"] = host_h .. (((port_h != nil and port_h != false) and port_h != 80) and ":" .. base.tostring(port_h) or ""),
        ["user-agent"] = _M.USERAGENT,
        ["connection"] = "close" -- we don't support keep-alive yet
    })
    if method_h == "POST" then
        res_h["content-type"] = "application/x-www-form-urlencoded"
        res_h["content-length"] = "0"
    end
    for i_h, v_h in base.pairs(tosend_h or ({})) do
        res_h[lower_h(i_h)] = v_h
    end
    return res_h
end

function default_create()
   f_create = socket.tcp
    return f_create()
end

-----------------------------------------------------------------------------
-- Connection metatable
-----------------------------------------------------------------------------
metat = ({ __index = ({}) })

function metat.__index.connect(self, host, port)
    self.try(getmetatable(self.c).__index.settimeout(self.c, self.timeout))
    return self.try(getmetatable(self.c).__index.connect(self.c, host, port))
end

function metat.__index.sendrequestline(self, method, uri)
   reqline = string.format("%s %s HTTP/1.1\r\n", (((method != nil and method != false) and method) or "GET"), uri)
    return self.try(getmetatable(self.c).__index.send(self.c, reqline))
end

function metat.__index.sendheaders(self, tosend)
   canonic_h = headers.canonic
   h_str = ""
    for f_h, v_h in base.pairs(tosend) do
        h_str = h_str .. ((((canonic_h != nil and canonic_h != false) and (canonic_h[f_h] != nil and canonic_h[f_h] != false) and canonic_h[f_h])) or f_h) .. ": " .. v_h .. "\r\n"
    end
    self.try(getmetatable(self.c).__index.send(self.c, h_str .. "\r\n"))
    return 1
end

function metat.__index.sendbody(self, headers_body, source_body, step_body)
    source_body = (((source_body != nil and source_body != false) and source_body) or ltn12.source.empty())
    step_body = (((step_body != nil and step_body != false) and step_body) or ltn12.pump.step)
   mode_body = "http-chunked"
    if (headers_body["content-length"] != nil and headers_body["content-length"] != false) then mode_body = "keep-open" end
    return self.try(ltn12.pump.all(source_body, socket.sink(mode_body, self.c), step_body))
end

function metat.__index.receivestatusline(self)
   status_line, ec_line = self.try(getmetatable(self.c).__index.receive(self.c, 5))
    if status_line != "HTTP/" then self.try(nil, "invalid status line") end
   status_line, ec_line = self.try(getmetatable(self.c).__index.receive(self.c, "*l"))
    if (ec_line != nil and ec_line != false) then self.try(nil, ec_line) end
    return base.tonumber(string.sub(status_line, 5, 7)), status_line
end

function metat.__index.receiveheaders(self)
   h_res = ({})
    while true do
       line_h, err_h = self.try(getmetatable(self.c).__index.receive(self.c, "*l"))
        if line_h == "" then break end
       name_h, value_h = socket.skip(2, string.find(line_h, "^(.-):%s*(.*)"))
        if (name_h == nil or name_h == false) then self.try(nil, "malformed reponse headers") end
        name_h = string.lower(name_h)
        if (h_res[name_h] != nil and h_res[name_h] != false) then h_res[name_h] = h_res[name_h] .. ", " .. value_h
        else h_res[name_h] = value_h end
    end
    return h_res
end

function metat.__index.receivebody(self, headers_body, sink_body, step_body)
    sink_body = (((sink_body != nil and sink_body != false) and sink_body) or ltn12.sink.null())
    step_body = (((step_body != nil and step_body != false) and step_body) or ltn12.pump.step)
   length_body = base.tonumber(headers_body["content-length"])
   t_body = headers_body["transfer-encoding"]
   mode_body = "until-closed"
    if (t_body != nil and t_body != false) and t_body != "identity" then mode_body = "http-chunked"
    elseif (length_body != nil and length_body != false) then mode_body = "by-length" end
    return self.try(ltn12.pump.all(socket.source(mode_body, self.c, length_body), sink_body, step_body))
end

function metat.__index.receive09body(self, status_body, sink_body, step_body)
   source_body = ltn12.source.rewind(socket.source("until-closed", self.c))
    source_body(status_body)
    return self.try(ltn12.pump.all(source_body, sink_body, step_body))
end

function metat.__index.close(self)
    return getmetatable(self.c).__index.close(self.c)
end

-----------------------------------------------------------------------------
-- High level HTTP client functions
-----------------------------------------------------------------------------
function _M.open(host_open, port_open, create_open)
   f_open = (((create_open != nil and create_open != false) and create_open) or default_create)
   c_open = f_open()
   h_open = base.setmetatable(({ c = c_open, try = _M.newtry(c_open) }), metat)
    return h_open
end

function _M.request(url_http, body_http)
   parsed_http = ({})
    if (base.type(url_http) == "string") then
        parsed_http = url.parse(url_http)
    else
        parsed_http = url_http
    end
    if (parsed_http.scheme != "http" and parsed_http.scheme != "https") then 
        base.error("invalid scheme '" .. (parsed_http.scheme or "nil") .. "'", 2)
    end
   host_http = parsed_http.host
   port_http = parsed_http.port or ((parsed_http.scheme == "https") and 443 or 80)
   uri_http = adjusturi(parsed_http)
   tosend_http = adjustheaders(host_http, port_http, parsed_http.method, uri_http, parsed_http.headers)
   h_http = _M.open(host_http, port_http, parsed_http.create)
    h_http.timeout = _M.TIMEOUT
    h_http.connect(h_http, host_http, port_http)
    h_http.sendrequestline(h_http, parsed_http.method, uri_http)
    h_http.sendheaders(h_http, tosend_http)
    if (body_http != nil and body_http != false) then
       source_http = ltn12.source.string(body_http)
        h_http.sendbody(h_http, tosend_http, source_http)
    elseif (parsed_http.source != nil and parsed_http.source != false) then
        h_http.sendbody(h_http, tosend_http, parsed_http.source, parsed_http.step)
    end
   code_http, status_http = h_http.receivestatusline(h_http)
    while code_http == 100 do
        h_http.receiveheaders(h_http)
        code_http, status_http = h_http.receivestatusline(h_http)
    end
   headers_http = h_http.receiveheaders(h_http)
    h_http.receivebody(h_http, headers_http, parsed_http.sink, parsed_http.step)
    h_http.close(h_http)
    return 1, code_http, headers_http, status_http
end

return _M
