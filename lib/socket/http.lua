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
SCHEMES = ({
    http = ({
        port = 80
        , create = function(t)
            return socket.tcp() end })
    , https = ({
        port = 443
        , create = function(t)
         https = assert(
            require("ssl.https"), 'LuaSocket: LuaSec not found')
         tcp = assert(
            https.tcp, 'LuaSocket: Function tcp() not available from LuaSec')
          return tcp(t) end })})

-----------------------------------------------------------------------------
-- Reads MIME headers from a connection, unfolding where needed
-----------------------------------------------------------------------------
function receiveheaders(sock, headers)
   line, name, value, err = nil
    if headers == nil or headers == false then
        headers = {}
    end
    -- get first line
    line, err = sock.receive(sock)
    if (err != nil and err != false) then return nil, err end
    -- headers go until a blank line is found
    while line != "" do
        -- get field-name and value
        name, value = socket.skip(2, string.find(line, "^(.-):%s*(.*)"))
        if (name == nil or name == false) or (value == nil or value == false) then return nil, "malformed response headers" end
        name = string.lower(name)
        -- get next line (value might be folded)
        line, err  = sock.receive(sock)
        if (err != nil and err != false) then return nil, err end
        -- unfold any folded values
        while (string.find(line, "^%s") != nil and string.find(line, "^%s") != false) do
            value = value .. line
            line, err = sock.receive(sock)
            if (err != nil and err != false) then return nil, err end
        end
        -- save pair in table
        if (headers[name] != nil and headers[name] != false) then headers[name] = headers[name] .. ", " .. value
        else headers[name] = value end
    end
    return headers
end

-----------------------------------------------------------------------------
-- Extra sources and sinks
-----------------------------------------------------------------------------
socket.sourcet["http-chunked"] = function(sock, headers)
    return base.setmetatable(({
        getfd = function() return sock.getfd(sock) end,
        dirty = function() return sock.dirty(sock) end
    }), ({
        __call = function()
            -- get chunk size, skip extension
           line, err = sock.receive(sock)
            if (err != nil and err != false) then return nil, err end
           size = base.tonumber(string.gsub(line, ";.*", ""), 16)
            if (size == nil or size == false) then return nil, "invalid chunk size" end
            -- was it the last chunk?
            if size > 0 then
                -- if not, get chunk and skip terminating CRLF
               chunk, err, _ = sock.receive(sock, size)
                if (chunk != nil and chunk != false) then sock.receive(sock) end
                return chunk, err
            else
                -- if it was, read trailers into headers table
                headers, err = receiveheaders(sock, headers)
                if (headers == nil or headers == false) then return nil, err end
            end
        end
    }))
end

socket.sinkt["http-chunked"] = function(sock)
    return base.setmetatable(({
        getfd = function() return sock.getfd(sock) end,
        dirty = function() return sock.dirty(sock) end
    }), ({
        __call = function(self, chunk, err)
            if (chunk == nil or chunk == false) then return sock.send(sock, "0\r\n\r\n") end
           size = string.format("%X\r\n", string.len(chunk))
            return sock.send(sock, size ..  chunk .. "\r\n")
        end
    }))
end

-----------------------------------------------------------------------------
-- Low level HTTP API
-----------------------------------------------------------------------------
metat = ({ __index = ({}) })

function _M.open(host, port, create)
    -- create socket with user connect function, or with default
   c = socket.try(create())
   h = base.setmetatable(({ c = c }), metat)
    -- create finalized try
    h.try = socket.newtry(function() h.close(h) end)
    -- set timeout before connecting
    h.try(c.settimeout(c, _M.TIMEOUT))
    h.try(c.connect(c, host, port))
    -- here everything worked
    return h
end

function metat.__index.sendrequestline(self, method, uri)
    if method == nil or method == false then
        method = "GET"
    end
   reqline = string.format("%s %s HTTP/1.1\r\n", method, uri)
    return self.try(self.c.send(self.c, reqline))
end

function metat.__index.sendheaders(self, tosend)
   canonic = headers.canonic
   h = "\r\n"
    for f, v in base.pairs(tosend) do
        canon = f
        if canonic[f] != nil and canonic[f] != false then
            canon = canonic[f]
        end
        h = canon .. ": " .. v .. "\r\n" .. h
    end
    self.try(self.c.send(self.c, h))
    return 1
end

function metat.__index.sendbody(self, headers, source, step)
    if source == nil or source == false then
        source = ltn12.source.empty()
    end
    if step == nil or step == false then
        step = ltn12.pump.step
    end
    -- if we don't know the size in advance, send chunked and hope for the best
   mode = "http-chunked"
    if (headers["content-length"] != nil and headers["content-length"] != false) then mode = "keep-open" end
    return self.try(ltn12.pump.all(source, socket.sink(mode, self.c), step))
end

function metat.__index.receivestatusline(self)
   status,ec = self.try(self.c.receive(self.c, 5))
    -- identify HTTP/0.9 responses, which do not contain a status line
    -- this is just a heuristic, but is what the RFC recommends
    if status != "HTTP/" then
        if ec == "timeout" then
            return 408
        end
        return nil, status
    end
    -- otherwise proceed reading a status line
    status = self.try(self.c.receive(self.c, "*l", status))
   code = socket.skip(2, string.find(status, "HTTP/%d*%.%d* (%d%d%d)"))
    return self.try(base.tonumber(code), status)
end

function metat.__index.receiveheaders(self)
    return self.try(receiveheaders(self.c))
end

function metat.__index.receivebody(self, headers, sink, step)
    if sink == nil or sink == false then
        sink = ltn12.sink.null()
    end
    if step == nil or step == false then
        step = ltn12.pump.step
    end
   length = base.tonumber(headers["content-length"])
   t = headers["transfer-encoding"] -- shortcut
   mode = "default" -- connection close
    if (t != nil and t != false) and t != "identity" then mode = "http-chunked"
    elseif (base.tonumber(headers["content-length"]) != nil and base.tonumber(headers["content-length"]) != false) then mode = "by-length" end
    return self.try(ltn12.pump.all(socket.source(mode, self.c, length),
        sink, step))
end

function metat.__index.receive09body(self, status, sink, step)
   source = ltn12.source.rewind(socket.source("until-closed", self.c))
    source(status)
    return self.try(ltn12.pump.all(source, sink, step))
end

function metat.__index.close(self)
    return self.c.close(self.c)
end

-----------------------------------------------------------------------------
-- High level HTTP API
-----------------------------------------------------------------------------
function adjusturi(reqt)
   u = reqt
    -- if there is a proxy, we need the full url. otherwise, just a part.
    if (reqt.proxy == nil or reqt.proxy == false) and (_M.PROXY == nil or _M.PROXY == false) then
        u = ({
           path = socket.try(reqt.path, "invalid path 'nil'"),
           params = reqt.params,
           query = reqt.query,
           fragment = reqt.fragment
        })
    end
    return url.build(u)
end

function adjustproxy(reqt)
   proxy = reqt.proxy
    if proxy == nil or proxy == false then
        proxy = _M.PROXY
    end
    if (proxy != nil and proxy != false) then
        proxy = url.parse(proxy)
        if proxy.port == nil or proxy.port == false then
            proxy.port = 3128
        end
        proxy.create = SCHEMES[proxy.scheme].create(reqt)
        return proxy.host, proxy.port, proxy.create
    else
        return reqt.host, reqt.port, reqt.create
    end
end

function adjustheaders(reqt)
    -- default headers
   host = reqt.host
   port = base.tostring(reqt.port)
    if port != base.tostring(SCHEMES[reqt.scheme].port) then
        host = host .. ':' .. port end
   lower = ({
        ["user-agent"] = _M.USERAGENT,
        ["host"] = host,
        ["connection"] = "close, TE",
        ["te"] = "trailers"
    })
    -- if we have authentication information, pass it along
    if (reqt.user != nil and reqt.user != false) and (reqt.password != nil and reqt.password != false) then
        lower["authorization"] =
            "Basic " ..  (mime.b64(reqt.user .. ":" ..
		url.unescape(reqt.password)))
    end
    -- if we have proxy authentication information, pass it along
   proxy = reqt.proxy
    if proxy == nil or proxy == false then
        proxy = _M.PROXY
    end
    if (proxy != nil and proxy != false) then
        proxy = url.parse(proxy)
        if (proxy.user != nil and proxy.user != false) and (proxy.password != nil and proxy.password != false) then
            lower["proxy-authorization"] =
                "Basic " ..  (mime.b64(proxy.user .. ":" .. proxy.password))
        end
    end
    -- override with user headers
   useheaders = reqt.headers
    if useheaders == nil or useheaders == false then
        useheaders = lower
    end
    for i,v in base.pairs(useheaders) do
        lower[string.lower(i)] = v
    end
    return lower
end

-- default url parts
default = ({
    path ="/"
    , scheme = "http"
})

function adjustrequest(reqt)
    -- parse url if provided
   nreqt = {}
    if reqt.url != nil and reqt.url != false then
        nreqt = url.parse(reqt.url, default)
    end
    -- explicit components override url
    for i,v in base.pairs(reqt) do nreqt[i] = v end
    -- default to scheme particulars
   schemedefs, host, port, method = SCHEMES[nreqt.scheme], nreqt.host, nreqt.port, nreqt.method
    if (nreqt.create == nil or nreqt.create == false) then nreqt.create = schemedefs.create(nreqt) end
    if (port == nil or port == "" or port == false) then nreqt.port = schemedefs.port end
    if (method == nil or method == "" or method == false) then nreqt.method = 'GET' end
    if (host == nil or host == "" or host == false) then
        socket.try(nil, "invalid host '" .. base.tostring(nreqt.host) .. "'")
    end
    -- compute uri if user hasn't overridden
    nreqt.uri = reqt.uri
    if nreqt.uri == nil or nreqt.uri == false then
        nreqt.uri = adjusturi(nreqt)
    end
    -- adjust headers in request
    nreqt.headers = adjustheaders(nreqt)
    if (nreqt.source != nil and nreqt.source != false)
        and (nreqt.headers["content-length"] == nil or nreqt.headers["content-length"] == false)
        and (nreqt.headers["transfer-encoding"] == nil or nreqt.headers["transfer-encoding"] == false)
    then
        nreqt.headers["transfer-encoding"] = "chunked"
    end

    -- ajust host and port if there is a proxy
   proxy_create = nil
    nreqt.host, nreqt.port, proxy_create = adjustproxy(nreqt)
    if (reqt.create == nil or reqt.create == false) then nreqt.create = proxy_create end

    return nreqt
end

function shouldredirect(reqt, code, headers)
   location = headers.location
    if (location == nil or location == false) then return false end
    location = string.gsub(location, "%s", "")
    if location == "" then return false end
    -- the RFC says the redirect URL may be relative
    location = url.absolute(reqt.url, location)
   scheme = url.parse(location).scheme
    if (scheme != nil and scheme != false) and (SCHEMES[scheme] == nil or SCHEMES[scheme] == false) then return false end
    -- avoid https downgrades
    if ('https' == reqt.scheme) and ('https' != scheme) then return false end
   sr_nredirects = reqt.nredirects
    if sr_nredirects == nil or sr_nredirects == false then
        sr_nredirects = 0
    end
   sr_maxredirects = reqt.maxredirects
    if sr_maxredirects == nil or sr_maxredirects == false then
        sr_maxredirects = 5
    end
    return (reqt.redirect != false) and
           (code == 301 or code == 302 or code == 303 or code == 307) and
           ((reqt.method == nil or reqt.method == false) or reqt.method == "GET" or reqt.method == "HEAD")
        and ((false == reqt.maxredirects)
                or (sr_nredirects < sr_maxredirects))
end

function shouldreceivebody(reqt, code)
    if reqt.method == "HEAD" then return nil end
    if (code == 204 or code == 304) then return nil end
    if (code >= 100 and code < 200) then return nil end
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
   td_nredirects = reqt.nredirects
    if td_nredirects == nil or td_nredirects == false then
        td_nredirects = 0
    end
   result, code, headers, status = trequest(({
        url = newurl,
        source = reqt.source,
        sink = reqt.sink,
        headers = reqt.headers,
        proxy = reqt.proxy,
        maxredirects = reqt.maxredirects,
        nredirects = td_nredirects + 1,
        create = reqt.create
    }))
    -- pass location header back as a hint we redirected
    if headers == nil or headers == false then
        headers = {}
    end
    if headers.location == nil or headers.location == false then
        headers.location = location
    end
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
    if (nreqt.source != nil and nreqt.source != false) then
        h.sendbody(h, nreqt.headers, nreqt.source, nreqt.step)
    end
   code, status = h.receivestatusline(h)
    -- if it is an HTTP/0.9 server, simply get the body and we are done
    if (code == nil or code == false) then
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
    if (shouldredirect(nreqt, code, headers) != nil and shouldredirect(nreqt, code, headers) != false) and (nreqt.source == nil or nreqt.source == false) then
        h.close(h)
        return tredirect(reqt, headers.location)
    end
    -- here we are finally done
    if (shouldreceivebody(nreqt, code) != nil and shouldreceivebody(nreqt, code) != false) then
        h.receivebody(h, headers, nreqt.sink, nreqt.step)
    end
    h.close(h)
    return 1, code, headers, status
end

-- turns an url and a body into a generic request
function genericform(u, b)
   t = ({})
   reqt = ({
        url = u,
        sink = ltn12.sink.table(t),
        target = t
    })
    if (b != nil and b != false) then
        reqt.source = ltn12.source.string(b)
        reqt.headers = ({
            ["content-length"] = string.len(b),
            ["content-type"] = "application/x-www-form-urlencoded"
        })
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
