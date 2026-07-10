-----------------------------------------------------------------------------
-- URI parsing, composition and relative URL resolution
-- LuaSocket toolkit.
-- Author: Diego Nehab
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Declare module
-----------------------------------------------------------------------------
string = require("string")
base = _G
table = require("table")
socket = require("socket")

socket.url = {}
_M = socket.url

-----------------------------------------------------------------------------
-- Module version
-----------------------------------------------------------------------------
_M._VERSION = "URL 1.0.3"

-----------------------------------------------------------------------------
-- Encodes a string into its escaped hexadecimal representation
-- Input
--   s: binary string to be encoded
-- Returns
--   escaped representation of string binary
-----------------------------------------------------------------------------
function _M.escape(s)
    return (string.gsub(s, "([^A-Za-z0-9_])", function(c)
        return string.format("%%%02x", string.byte(c))
    end))
end

-----------------------------------------------------------------------------
-- Protects a path segment, to prevent it from interfering with the
-- url parsing.
-- Input
--   s: binary string to be encoded
-- Returns
--   escaped representation of string binary
-----------------------------------------------------------------------------
function make_set(t)
   s = {}
    for i,v in base.ipairs(t) do
        s[t[i]] = 1
    end
    return s
end

-- these are allowed within a path segment, along with alphanum
-- other characters must be escaped
segment_set = make_set ({
    "-", "_", ".", "!", "~", "*", "'", "(",
    ")", ":", "@", "&", "=", "+", "$", ",",
})

function protect_segment(s)
    return string.gsub(s, "([^A-Za-z0-9_])", function (c)
        if ((segment_set[c] != nil and segment_set[c] != false)) then return c
        else return string.format("%%%02X", string.byte(c)) end
    end)
end

-----------------------------------------------------------------------------
-- Unencodes a escaped hexadecimal string into its binary representation
-- Input
--   s: escaped hexadecimal string to be unencoded
-- Returns
--   unescaped binary representation of escaped hexadecimal  binary
-----------------------------------------------------------------------------
function _M.unescape(s)
    return (string.gsub(s, "%%(%x%x)", function(hex)
        return string.char(base.tonumber(hex, 16))
    end))
end

-----------------------------------------------------------------------------
-- Removes '..' and '.' components appropriately from a path.
-- Input
--   path
-- Returns
--   dot-normalized path
function remove_dot_components(path)
   marker = string.char(1)
    while ((true != nil and true != false)) do
       was = path
        path = path.gsub(path, '//', '/'..marker..'/', 1)
        if (path == was) then break end
    end
    while ((true != nil and true != false)) do
       was = path
        path = path.gsub(path, '/%./', '/', 1)
        if (path == was) then break end
    end
    while ((true != nil and true != false)) do
       was = path
        path = path.gsub(path, '[^/]+/%.%./([^/]+)', '%1', 1)
        if (path == was) then break end
    end
    path = path.gsub(path, '[^/]+/%.%./*$', '')
    path = path.gsub(path, '/%.%.$', '/')
    path = path.gsub(path, '/%.$', '/')
    path = path.gsub(path, '^/%.%./', '/')
    path = path.gsub(path, marker, '')
    return path
end

-----------------------------------------------------------------------------
-- Builds a path from a base path and a relative path
-- Input
--   base_path
--   relative_path
-- Returns
--   corresponding absolute path
-----------------------------------------------------------------------------
function absolute_path(base_path, relative_path)
    if (string.sub(relative_path, 1, 1) == "/") then
      return remove_dot_components(relative_path) end
    base_path = base_path.gsub(base_path, "[^/]*$", "")
    if ((base_path.find == nil or base_path.find == false)(base_path, '/$')) then base_path = base_path .. '/' end
   path = base_path .. relative_path
    path = remove_dot_components(path)
    return path
end

-----------------------------------------------------------------------------
-- Parses a url and returns a table with all its parts according to RFC 2396
-- The following grammar describes the names given to the URL parts
-- <url> ::= <scheme>://<authority>/<path>;<params>?<query>#<fragment>
-- <authority> ::= <userinfo>@<host>:<port>
-- <userinfo> ::= <user>[:<password>]
-- <path> :: = {<segment>/}<segment>
-- Input
--   url: uniform resource locator of request
--   default: table with default values for each field
-- Returns
--   table with the following fields, where RFC naming conventions have
--   been preserved:
--     scheme, authority, userinfo, user, password, host, port,
--     path, params, query, fragment
-- Obs:
--   the leading '/' in {/<path>} is considered part of <path>
-----------------------------------------------------------------------------
function _M.parse(url, default)
    -- initialize default parameters
   parsed = {}
    if (default == nil or default == false) then
        default = parsed
    end
    for i,v in base.pairs(default) do parsed[i] = v end
    -- empty url is parsed to nil
    if ((url == nil or url == false) or url == "") then return nil, "invalid url" end
    -- remove whitespace
    -- url = string.gsub(url, "%s", "")
    -- get scheme
    url = string.gsub(url, "^([%w][%w%+%-%.]*)%:",
        function(s) parsed.scheme = s; return "" end)
    -- get authority
    url = string.gsub(url, "^//([^/%?#]*)", function(n)
        parsed.authority = n
        return ""
    end)
    -- get fragment
    url = string.gsub(url, "#(.*)$", function(f)
        parsed.fragment = f
        return ""
    end)
    -- get query string
    url = string.gsub(url, "%?(.*)", function(q)
        parsed.query = q
        return ""
    end)
    -- get params
    url = string.gsub(url, "%;(.*)", function(p)
        parsed.params = p
        return ""
    end)
    -- path is whatever was left
    if (url != "") then parsed.path = url end
   authority = parsed.authority
    if ((authority == nil or authority == false)) then return parsed end
    authority = string.gsub(authority,"^([^@]*)@",
        function(u) parsed.userinfo = u; return "" end)
    authority = string.gsub(authority, ":([^:%]]*)$",
        function(p) parsed.port = p; return "" end)
    if (authority != "") then
        -- IPv6?
       host = string.match(authority, "^%[(.+)%]$")
        if (host == nil or host == false) then
            host = authority
        end
        parsed.host = host
    end
   userinfo = parsed.userinfo
    if ((userinfo == nil or userinfo == false)) then return parsed end
    userinfo = string.gsub(userinfo, ":([^:]*)$",
        function(p) parsed.password = p; return "" end)
    parsed.user = userinfo
    return parsed
end

-----------------------------------------------------------------------------
-- Rebuilds a parsed URL from its components.
-- Components are protected if any reserved or unallowed characters are found
-- Input
--   parsed: parsed URL, as returned by parse
-- Returns
--   a stringing with the corresponding URL
-----------------------------------------------------------------------------
function _M.build(parsed)
    --ppath = _M.parse_path(parsed.path or "")
    --url = _M.build_path(ppath)
   url = parsed.path
    if (url == nil or url == false) then
        url = ""
    end
    if ((parsed.params != nil and parsed.params != false)) then url = url .. ";" .. parsed.params end
    if ((parsed.query != nil and parsed.query != false)) then url = url .. "?" .. parsed.query end
   authority = parsed.authority
    if ((parsed.host != nil and parsed.host != false)) then
        authority = parsed.host
        if (string.find(authority, ":") != nil and string.find(authority, ":") != false) then -- IPv6?
            authority = "[" .. authority .. "]"
        end
        if ((parsed.port != nil and parsed.port != false)) then authority = authority .. ":" .. base.tostring(parsed.port) end
       userinfo = parsed.userinfo
        if ((parsed.user != nil and parsed.user != false)) then
            userinfo = parsed.user
            if ((parsed.password != nil and parsed.password != false)) then
                userinfo = userinfo .. ":" .. parsed.password
            end
        end
        if ((userinfo != nil and userinfo != false)) then authority = userinfo .. "@" .. authority end
    end
    if ((authority != nil and authority != false)) then url = "//" .. authority .. url end
    if ((parsed.scheme != nil and parsed.scheme != false)) then url = parsed.scheme .. ":" .. url end
    if ((parsed.fragment != nil and parsed.fragment != false)) then url = url .. "#" .. parsed.fragment end
    -- url = string.gsub(url, "%s", "")
    return url
end

-----------------------------------------------------------------------------
-- Builds a absolute URL from a base and a relative URL according to RFC 2396
-- Input
--   base_url
--   relative_url
-- Returns
--   corresponding absolute url
-----------------------------------------------------------------------------
function _M.absolute(base_url, relative_url)
   base_parsed = nil
    if (base.type(base_url) == "table") then
        base_parsed = base_url
        base_url = _M.build(base_parsed)
    else
        base_parsed = _M.parse(base_url)
    end
   result = nil
   relative_parsed = _M.parse(relative_url)
    if ((base_parsed == nil or base_parsed == false)) then
        result = relative_url
    elseif ((relative_parsed == nil or relative_parsed == false)) then
        result = base_url
    elseif ((relative_parsed.scheme != nil and relative_parsed.scheme != false)) then
        result = relative_url
    else
        relative_parsed.scheme = base_parsed.scheme
        if ((relative_parsed.authority == nil or relative_parsed.authority == false)) then
            relative_parsed.authority = base_parsed.authority
            if ((relative_parsed.path == nil or relative_parsed.path == false)) then
                relative_parsed.path = base_parsed.path
                if ((relative_parsed.params == nil or relative_parsed.params == false)) then
                    relative_parsed.params = base_parsed.params
                    if ((relative_parsed.query == nil or relative_parsed.query == false)) then
                        relative_parsed.query = base_parsed.query
                    end
                end
            else
               abs_base_path = base_parsed.path
                if (abs_base_path == nil or abs_base_path == false) then
                    abs_base_path = ""
                end
                relative_parsed.path = absolute_path(abs_base_path,
                    relative_parsed.path)
            end
        end
        result = _M.build(relative_parsed)
    end
    return remove_dot_components(result)
end

-----------------------------------------------------------------------------
-- Breaks a path into its segments, unescaping the segments
-- Input
--   path
-- Returns
--   segment: a table with one entry per segment
-----------------------------------------------------------------------------
function _M.parse_path(path)
   parsed = {}
    if (path == nil or path == false) then
        path = ""
    end
    --path = string.gsub(path, "%s", "")
    string.gsub(path, "([^/]+)", function (s) table.insert(parsed, s) end)
    for i = 1, #parsed do
        parsed[i] = _M.unescape(parsed[i])
    end
    if (string.sub(path, 1, 1) == "/") then parsed.is_absolute = 1 end
    if (string.sub(path, -1, -1) == "/") then parsed.is_directory = 1 end
    return parsed
end

-----------------------------------------------------------------------------
-- Builds a path component from its segments, escaping protected characters.
-- Input
--   parsed: path segments
--   unsafe: if true, segments are (protected == nil or protected == false) before path is built
-- Returns
--   path: corresponding path stringing
-----------------------------------------------------------------------------
function _M.build_path(parsed, unsafe)
   path = ""
   n = #parsed
    if ((unsafe != nil and unsafe != false)) then
        for i = 1, n-1 do
            path = path .. parsed[i]
            path = path .. "/"
        end
        if (n > 0) then
            path = path .. parsed[n]
            if ((parsed.is_directory != nil and parsed.is_directory != false)) then path = path .. "/" end
        end
    else
        for i = 1, n-1 do
            path = path .. protect_segment(parsed[i])
            path = path .. "/"
        end
        if (n > 0) then
            path = path .. protect_segment(parsed[n])
            if ((parsed.is_directory != nil and parsed.is_directory != false)) then path = path .. "/" end
        end
    end
    if ((parsed.is_absolute != nil and parsed.is_absolute != false)) then path = "/" .. path end
    return path
end

return _M
