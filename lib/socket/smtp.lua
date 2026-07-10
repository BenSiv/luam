-----------------------------------------------------------------------------
-- SMTP client support for the Lua language.
-- LuaSocket toolkit.
-- Author: Diego Nehab
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Declare module and import dependencies
-----------------------------------------------------------------------------
base = _G
coroutine = require("coroutine")
string = require("string")
math = require("math")
os = require("os")
socket = require("socket")
tp = require("socket.tp")
ltn12 = require("ltn12")
headers = require("socket.headers")
mime = require("mime")

socket.smtp = {}
_M = socket.smtp

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
-- timeout for connection
_M.TIMEOUT = 60
-- default server used to send e-mails
_M.SERVER = "localhost"
-- default port
_M.PORT = 25
-- domain used in HELO command and default sendmail
-- If we are under a CGI, try to get from environment
_M.DOMAIN = os.getenv("SERVER_NAME")
if _M.DOMAIN == nil then
    _M.DOMAIN = "localhost"
end
-- default time zone (means we don't know)
_M.ZONE = "-0000"

---------------------------------------------------------------------------
-- Low level SMTP API
-----------------------------------------------------------------------------
metat = { __index = {} }

function metat.__index.greet(__index, domain)
    self.try(self.tp.check(self.tp, "2.."))
    if domain == nil then
        domain = _M.DOMAIN
    end
    self.try(self.tp.command(self.tp, "EHLO", domain))
    return socket.skip(1, self.try(self.tp.check(self.tp, "2..")))
end

function metat.__index.mail(__index, from)
    self.try(self.tp.command(self.tp, "MAIL", "FROM:" .. from))
    return self.try(self.tp.check(self.tp, "2.."))
end

function metat.__index.rcpt(__index, to)
    self.try(self.tp.command(self.tp, "RCPT", "TO:" .. to))
    return self.try(self.tp.check(self.tp, "2.."))
end

function metat.__index.data(__index, src, step)
    self.try(self.tp.command(self.tp, "DATA"))
    self.try(self.tp.check(self.tp, "3.."))
    self.try(self.tp.source(self.tp, src, step))
    self.try(self.tp.send(self.tp, "\r\n.\r\n"))
    return self.try(self.tp.check(self.tp, "2.."))
end

function metat.__index.quit(__index)
    self.try(self.tp.command(self.tp, "QUIT"))
    return self.try(self.tp.check(self.tp, "2.."))
end

function metat.__index.close(__index)
    return self.tp.close(self.tp)
end

function metat.__index.login(__index, user, password)
    self.try(self.tp.command(self.tp, "AUTH", "LOGIN"))
    self.try(self.tp.check(self.tp, "3.."))
    self.try(self.tp.send(self.tp, mime.b64(user) .. "\r\n"))
    self.try(self.tp.check(self.tp, "3.."))
    self.try(self.tp.send(self.tp, mime.b64(password) .. "\r\n"))
    return self.try(self.tp.check(self.tp, "2.."))
end

function metat.__index.plain(__index, user, password)
   auth = "PLAIN " .. mime.b64("\0" .. user .. "\0" .. password)
    self.try(self.tp.command(self.tp, "AUTH", auth))
    return self.try(self.tp.check(self.tp, "2.."))
end

function metat.__index.auth(__index, user, password, ext)
    if ((user == nil or user == false) or (password == nil or password == false)) then return 1 end
    if (string.find(ext, "AUTH[^\n]+LOGIN") != nil and string.find(ext, "AUTH[^\n]+LOGIN") != false) then
        return self.login(self, user, password)
    elseif (string.find(ext, "AUTH[^\n]+PLAIN") != nil and string.find(ext, "AUTH[^\n]+PLAIN") != false) then
        return self.plain(self, user, password)
    else
        self.try(nil, "authentication method not supported")
    end
end

-- send message or throw an exception
function metat.__index.send(__index, mailt)
    self.mail(self, mailt.from)
    if base.type(mailt.rcpt) == "table" then
        for i,v in base.ipairs(mailt.rcpt) do
            self.rcpt(self, v)
        end
    else
        self.rcpt(self, mailt.rcpt)
    end
    self.data(self, ltn12.source.chain(mailt.source, mime.stuff()), mailt.step)
end

function _M.open(server, port, create)
    if server == nil then
        server = _M.SERVER
    end
    if port == nil then
        port = _M.PORT
    end
   tp = socket.try(tp.connect(server, port, _M.TIMEOUT, create))
   s = base.setmetatable({tp = tp}, metat)
    -- make sure tp is closed if we get an exception
    s.try = socket.newtry(function()
        s.close(s)
    end)
    return s
end

-- convert headers to lowercase
function lower_headers(headers)
   lower = {}
    if headers == nil then
        headers = lower
    end
    for i,v in base.pairs(headers) do
        lower[string.lower(i)] = v
    end
    return lower
end

---------------------------------------------------------------------------
-- Multipart message source
-----------------------------------------------------------------------------
-- returns a hopefully unique mime boundary
seqno = 0
function newboundary()
    seqno = seqno + 1
    return string.format('%s%05d==%05u', os.date('%d%m%Y%H%M%S'),
        math.random(0, 99999), seqno)
end

-- send_message forward declaration
send_message = nil

-- yield the headers all at once, it's faster
function send_headers(tosend)
   canonic = headers.canonic
   h = "\r\n"
    for f,v in base.pairs(tosend) do
       canonic_name = f
        if canonic[f] != nil then
            canonic_name = canonic[f]
        end
        h = canonic_name .. ': ' .. v .. "\r\n" .. h
    end
    coroutine.yield(h)
end

-- yield multipart message body from a multipart message table
function send_multipart(mesgt)
    -- make sure we have our boundary and send headers
   bd = newboundary()
   mesgt_headers = mesgt.headers
    if mesgt_headers == nil then
        mesgt_headers = {}
    end
   headers = lower_headers(mesgt_headers)
    if headers['content-type'] == nil then
        headers['content-type'] = 'multipart/mixed'
    end
    headers['content-type'] = headers['content-type'] ..
        '; boundary="' ..  bd .. '"'
    send_headers(headers)
    -- send preamble
    if (mesgt.body.preamble != nil and mesgt.body.preamble != false) then
        coroutine.yield(mesgt.body.preamble)
        coroutine.yield("\r\n")
    end
    -- send each part separated by a boundary
    for i, m in base.ipairs(mesgt.body) do
        coroutine.yield("\r\n--" .. bd .. "\r\n")
        send_message(m)
    end
    -- send last boundary
    coroutine.yield("\r\n--" .. bd .. "--\r\n\r\n")
    -- send epilogue
    if ((mesgt.body.epilogue != nil and mesgt.body.epilogue != false)) then
        coroutine.yield(mesgt.body.epilogue)
        coroutine.yield("\r\n")
    end
end

-- yield message body from a source
function send_source(mesgt)
    -- make sure we have a content-type
   mesgt_headers = mesgt.headers
    if mesgt_headers == nil then
        mesgt_headers = ({})
    end
   headers = lower_headers(mesgt_headers)
    if headers['content-type'] == nil then
        headers['content-type'] = 'text/plain; charset="iso-8859-1"'
    end
    send_headers(headers)
    -- send body from source
    while ((true != nil and true != false)) do
       chunk, err = mesgt.body()
        if ((err != nil and err != false)) then coroutine.yield(nil, err)
        elseif ((chunk != nil and chunk != false)) then coroutine.yield(chunk)
        else break end
    end
end

-- yield message body from a string
function send_string(mesgt)
    -- make sure we have a content-type
   mesgt_headers = mesgt.headers
    if mesgt_headers == nil then
        mesgt_headers = ({})
    end
   headers = lower_headers(mesgt_headers)
    if headers['content-type'] == nil then
        headers['content-type'] = 'text/plain; charset="iso-8859-1"'
    end
    send_headers(headers)
    -- send body from string
    coroutine.yield(mesgt.body)
end

-- message source
function send_message(mesgt)
    if (base.type(mesgt.body) == "table") then send_multipart(mesgt)
    elseif (base.type(mesgt.body) == "function") then send_source(mesgt)
    else send_string(mesgt) end
end

-- set defaul headers
function adjust_headers(mesgt)
   lower = lower_headers(mesgt.headers)
   mesgt_zone = mesgt.zone
    if mesgt_zone == nil then
        mesgt_zone = _M.ZONE
    end
    if lower["date"] == nil then
        lower["date"] = os.date("!%a, %d %b %Y %H:%M:%S ") .. mesgt_zone
    end
    if lower["x-mailer"] == nil then
        lower["x-mailer"] = socket._VERSION
    end
    -- this can't be overridden
    lower["mime-version"] = "1.0"
    return lower
end

function _M.message(mesgt)
    mesgt.headers = adjust_headers(mesgt)
    -- create and return message source
   co = coroutine.create(function() send_message(mesgt) end)
    return function()
       ret, a, b = coroutine.resume(co)
        if ((ret != nil and ret != false)) then return a, b
        else return nil, a end
    end
end

---------------------------------------------------------------------------
-- High level SMTP API
-----------------------------------------------------------------------------
_M.send = socket.protect(function(mailt)
   s = _M.open(mailt.server, mailt.port, mailt.create)
   ext = s.greet(s, mailt.domain)
    s.auth(s, mailt.user, mailt.password, ext)
    s.send(s, mailt)
    s.quit(s)
    return s.close(s)
end)

return _M
