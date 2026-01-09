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
socket.http = {}
_M = socket.http

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
-- connection timeout in seconds
_M.TIMEOUT = 60
-- user agent field sent in request
_M.USERAGENT = socket._VERSION

-- supported schemes and their particulars
SCHEMES = {
    http = {
        port = 80
        , create = function(t)
            return socket.tcp end }
    , https = {
        port = 443
        , create = function(t)
         https = assert(
            require("ssl.https"), 'LuaSocket: LuaSec not found')
         tcp = assert(
            https.tcp, 'LuaSocket: Function tcp() not available from LuaSec')
          return tcp(t) end }}

-----------------------------------------------------------------------------
-- Reads MIME headers from a connection, unfolding where needed
-----------------------------------------------------------------------------
function receiveheaders(sock, headers)
   line, name, value, err = nil
    headers = headers or {}
    -- get first line
    line, err = sock.receive(sock)
    if err then return nil, err end
    -- headers go until a blank line is found
    while line != "" do
        -- get field-name and value
        name, value = socket.skip(2, string.find(line, "^(.-):%s*(.*)"))
        if not (name and value) then return nil, "malformed response headers" end
        name = string.lower(name)
        -- get next line (value might be folded)
        line, err  = sock.receive(sock)
        if err then return nil, err end
        -- unfold any folded values
        while string.find(line, "^%s") do
            value = value .. line
            line, err = sock.receive(sock)
            if err then return nil, err end
        end
        -- save pair in table
        if headers[name] then headers[name] = headers[name] .. ", " .. value
        else headers[name] = value end
    end
    return headers
end

-----------------------------------------------------------------------------
-- Extra sources and sinks
-----------------------------------------------------------------------------
socket.sourcet["http-chunked"] = function(sock, headers)
    return base.setmetatable({
        getfd = function() return sock.getfd(sock) end,
        dirty = function() return sock.dirty(sock) end
    }, {
        __call = function()
            -- get chunk size, skip extension
           line, err = sock.receive(sock)
            if err then return nil, err end
           size = base.tonumber(string.gsub(line, ";.*", ""), 16)
            if not size then return nil, "invalid chunk size" end
            -- was it the last chunk?
            if size > 0 then
                -- if not, get chunk and skip terminating CRLF
               chunk, err, _ = sock.receive(sock, size)
                if chunk then sock.receive(sock) end
                return chunk, err
            else
                -- if it was, read trailers into headers table
                headers, err = receiveheaders(sock, headers)
                if not headers then return nil, err end
            end
        end
    })
end

socket.sinkt["http-chunked"] = function(sock)
    return base.setmetatable({
        getfd = function() return sock.getfd(sock) end,
        dirty = function() return sock.dirty(sock) end
    }, {
        __call = function(self, chunk, err)
            if not chunk then return sock.send(sock, "0\r\n\r\n") end
           size = string.format("%X\r\n", string.len(chunk))
            return sock.send(sock, size ..  chunk .. "\r\n")
        end
    })
end

-----------------------------------------------------------------------------
-- Low level HTTP API
-----------------------------------------------------------------------------
metat = { __index = {} }

function _M.open(host, port, create)
    -- create socket with user connect function, or with default
   c = socket.try(create())
   h = base.setmetatable({ c = c }, metat)
    -- create finalized try
    h.try = socket.newtry(function() h.close(h) end)
    -- set timeout before connecting
    h.try(c.settimeout(c, _M.TIMEOUT))
    h.try(c.connect(c, host, port))
    -- here everything worked
    return h
end

function metat.__index.sendrequestline(__index, method, uri)
   reqline = string.format("%s %s HTTP/1.1\r\n", method or "GET", uri)
    return self.try(self.c.send(c, reqline))
end

function metat.__index.sendheaders(__index, tosend)
   canonic = headers.canonic
   h = "\r\n"
    for f, v in base.pairs(tosend) do
        h = (canonic[f] or f) .. ": " .. v .. "\r\n" .. h
    end
    self.try(self.c.send(c, h))
    return 1
end

function metat.__index.sendbody(__index, headers, source, step)
    source = source or ltn12.source.empty()
    step = step or ltn12.pump.step
    -- if we don't know the size in advance, send chunked and hope for the best
   mode = "http-chunked"
    if headers["content-length"] then mode = "keep-open" end
    return self.try(ltn12.pump.all(source, socket.sink(mode, self.c), step))
end

function metat.__index.receivestatusline(__index)
   status,ec = self.try(self.c.receive(c, 5))
    -- identify HTTP/0.9 responses, which do not contain a status line
    -- this is just a heuristic, but is what the RFC recommends
    if status != "HTTP/" then
        if ec == "timeout" then
            return 408
        end
        return nil, status
    end
    -- otherwise proceed reading a status line
    status = self.try(self.c.receive(c, "*l", status))
   code = socket.skip(2, string.find(status, "HTTP/%d*%.%d* (%d%d%d)"))
    return self.try(base.tonumber(code), status)
end

function metat.__index.receiveheaders(__index)
    return self.try(receiveheaders(self.c))
end

function metat.__index.receivebody(__index, headers, sink, step)
    sink = sink or ltn12.sink.null()
    step = step or ltn12.pump.step
   length = base.tonumber(headers["content-length"])
   t = headers["transfer-encoding"] -- shortcut
   mode = "default" -- connection close
    if t and t != "identity" then mode = "http-chunked"
    elseif base.tonumber(headers["content-length"]) then mode = "by-length" end
    return self.try(ltn12.pump.all(socket.source(mode, self.c, length),
        sink, step))
end

function metat.__index.receive09body(__index, status, sink, step)
   source = ltn12.source.rewind(socket.source("until-closed", self.c))
    source(status)
    return self.try(ltn12.pump.all(source, sink, step))
end

function metat.__index.close(__index)
    return self.c.close(c)
end

-----------------------------------------------------------------------------
-- High level HTTP API
-----------------------------------------------------------------------------
function adjusturi(reqt)
   u = reqt
    -- if there is a proxy, we need the full url. otherwise, just a part.
    if not reqt.proxy and not _M.PROXY then
        u = {
           path = socket.try(reqt.path, "invalid path 'nil'"),
           params = reqt.params,
           query = reqt.query,
           fragment = reqt.fragment
        }
    end
    return url.build(u)
end

function adjustproxy(reqt)
   proxy = reqt.proxy or _M.PROXY
    if proxy then
        proxy = url.parse(proxy)
        proxy.port = proxy.port or 3128
        proxy.create = SCHEMES[proxy.scheme].create(reqt)
        return proxy.host, proxy.port, proxy.create
    else
        return reqt.host, reqt.port, reqt.create
    end
end

function adjustheaders(reqt)
    -- default headers
   host = reqt.host
   port = tostring(reqt.port)
    if port != tostring(SCHEMES[reqt.scheme].port) then
        host = host .. ':' .. port end
   lower = {
        ["user-agent"] = _M.USERAGENT,
        ["host"] = host,
        ["connection"] = "close, TE",
        ["te"] = "trailers"
    }
    -- if we have authentication information, pass it along
    if reqt.user and reqt.password then
        lower["authorization"] =
            "Basic " ..  (mime.b64(reqt.user .. ":" ..
		url.unescape(reqt.password)))
    end
    -- if we have proxy authentication information, pass it along
   proxy = reqt.proxy or _M.PROXY
    if proxy then
        proxy = url.parse(proxy)
        if proxy.user and proxy.password then
            lower["proxy-authorization"] =
                "Basic " ..  (mime.b64(proxy.user .. ":" .. proxy.password))
        end
    end
    -- override with user headers
    for i,v in base.pairs(reqt.headers or lower) do
        lower[string.lower(i)] = v
    end
    return lower
end

-- default url parts
default = {
    path ="/"
    , scheme = "http"
}

function adjustrequest(reqt)
    -- parse url if provided
   nreqt = reqt.url and url.parse(reqt.url, default) or {}
    -- explicit components override url
    for i,v in base.pairs(reqt) do nreqt[i] = v end
    -- default to scheme particulars
   schemedefs, host, port, method 
        = SCHEMES[nreqt.scheme], nreqt.host, nreqt.port, nreqt.method
    if not nreqt.create then nreqt.create = schemedefs.create(nreqt) end
    if not (port and port != '') then nreqt.port = schemedefs.port end
    if not (method and method != '') then nreqt.method = 'GET' end
    if not (host and host != "") then
        socket.try(nil, "invalid host '" .. base.tostring(nreqt.host) .. "'")
    end
    -- compute uri if user hasn't overridden
    nreqt.uri = reqt.uri or adjusturi(nreqt)
    -- adjust headers in request
    nreqt.headers = adjustheaders(nreqt)
    if nreqt.source
        and not nreqt.headers["content-length"]
        and not nreqt.headers["transfer-encoding"]
    then
        nreqt.headers["transfer-encoding"] = "chunked"
    end

    -- ajust host and port if there is a proxy
   proxy_create = nil
    nreqt.host, nreqt.port, proxy_create = adjustproxy(nreqt)
    if not reqt.create then nreqt.create = proxy_create end

    return nreqt
end

function shouldredirect(reqt, code, headers)
   location = headers.location
    if not location then return false end
    location = string.gsub(location, "%s", "")
    if location == "" then return false end
    -- the RFC says the redirect URL may be relative
    location = url.absolute(reqt.url, location)
   scheme = url.parse(location).scheme
    if scheme and (not SCHEMES[scheme]) then return false end
    -- avoid https downgrades
    if ('https' == reqt.scheme) and ('https' != scheme) then return false end
    return (reqt.redirect != false) and
           (code == 301 or code == 302 or code == 303 or code == 307) and
           (not reqt.method or reqt.method == "GET" or reqt.method == "HEAD")
        and ((false == reqt.maxredirects)
                or ((reqt.nredirects or 0)
                        < (reqt.maxredirects or 5)))
end

function shouldreceivebody(reqt, code)
    if reqt.method == "HEAD" then return nil end
    if code == 204 or code == 304 then return nil end
    if code >= 100 and code < 200 then return nil end
    return 1
end

-- forward declarations
trequest, tredirect = nil

 function tredirect(reqt, location)
    -- the RFC says the redirect URL may be relative
   newurl = url.absolute(reqt.url, location)
    -- if switching schemes, reset port and create function
    if url.parse(newurl).scheme != reqt.scheme then
        reqt.port = nil
        reqt.create = nil end
    -- make new request
   result, code, headers, status = trequest ({
        url = newurl,
        source = reqt.source,
        sink = reqt.sink,
        headers = reqt.headers,
        proxy = reqt.proxy,
        maxredirects = reqt.maxredirects,
        nredirects = (reqt.nredirects or 0) + 1,
        create = reqt.create
    })
    -- pass location header back as a hint we redirected
    headers = headers or {}
    headers.location = headers.location or location
    return result, code, headers, status
end

 function trequest(reqt)
    -- we loop until we get what we want, or
    -- until we are sure there is no way to get it
   nreqt = adjustrequest(reqt)
   h = _M.open(nreqt.host, nreqt.port, nreqt.create)
    -- send request line and headers
    h.sendrequestline(h, nreqt.method, nreqt.uri)
    h.sendheaders(h, nreqt.headers)
    -- if there is a body, send it
    if nreqt.source then
        h.sendbody(h, nreqt.headers, nreqt.source, nreqt.step)
    end
   code, status = h.receivestatusline(h)
    -- if it is an HTTP/0.9 server, simply get the body and we are done
    if not code then
        h.receive09body(h, status, nreqt.sink, nreqt.step)
        return 1, 200
    elseif code == 408 then
        return 1, code
    end
   headers = nil
    -- ignore any 100-continue messages
    while code == 100 do
        h.receiveheaders(h)
        code, status = h.receivestatusline(h)
    end
    headers = h.receiveheaders(h)
    -- at this point we should have a honest reply from the server
    -- we can't redirect if we already used the source, so we report the error
    if shouldredirect(nreqt, code, headers) and not nreqt.source then
        h.close(h)
        return tredirect(reqt, headers.location)
    end
    -- here we are finally done
    if shouldreceivebody(nreqt, code) then
        h.receivebody(h, headers, nreqt.sink, nreqt.step)
    end
    h.close(h)
    return 1, code, headers, status
end

-- turns an url and a body into a generic request
function genericform(u, b)
   t = {}
   reqt = {
        url = u,
        sink = ltn12.sink.table(t),
        target = t
    }
    if b then
        reqt.source = ltn12.source.string(b)
        reqt.headers = {
            ["content-length"] = string.len(b),
            ["content-type"] = "application/x-www-form-urlencoded"
        }
        reqt.method = "POST"
    end
    return reqt
end

_M.genericform = genericform

function srequest(u, b)
   reqt = genericform(u, b)
   _, code, headers, status = trequest(reqt)
    return table.concat(reqt.target), code, headers, status
end

_M.request = socket.protect(function(reqt, body)
    if base.type(reqt) == "string" then return srequest(reqt, body)
    else return trequest(reqt) end
end)

_M.schemes = SCHEMES
return _M
