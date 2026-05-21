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

_M = ({})

-----------------------------------------------------------------------------
-- Module version
-----------------------------------------------------------------------------
_M._VERSION = "URL 1.0.3"

-----------------------------------------------------------------------------
-- Helper functions
-----------------------------------------------------------------------------
function make_set(t)
    s_set = ({})
    for i_set,v_set in base.ipairs(t) do
        s_set[v_set] = 1
    end
    return s_set
end

-- Is character a-z, A-Z, 0-9, '-', '.', '_', '~'?
function is_unreserved(c)
    return (string.find(c, "^[%w%-%.%_%~]$") != nil and string.find(c, "^[%w%-%.%_%~]$") != false)
end

-- Is character a-z, A-Z, 0-9, '-', '.', '_', '~', '!', '$', '&', "'", '(', ')', '*', '+', ',', ';', '='?
function is_sub_delims(c)
    return (string.find(c, "^[%!%$%&%'%(%)%*%+%,%;%=]$") != nil and string.find(c, "^[%!%$%&%'%(%)%*%+%,%;%=]$") != false)
end

-- Is character a sub-delim or unreserved?
function is_pchar(c)
    return (is_unreserved(c) != nil and is_unreserved(c) != false) or (is_sub_delims(c) != nil and is_sub_delims(c) != false) or c == ":" or c == "@"
end

-----------------------------------------------------------------------------
-- Standard URL characters
-----------------------------------------------------------------------------
schemes = make_set(({"http", "https", "ftp", "tftp", "telnet", "rtsp", "mms", "prospero", "gopher", "wais", "nntp", "snews", "news", "file", "mailto" }))

-----------------------------------------------------------------------------
-- Property tables for each component
-----------------------------------------------------------------------------
function protect_segment(s)
    res_gsub, n_gsub = string.gsub(s, "([^%w%-%.%_%~%!%$%&%'%(%)%*%+%,%;%=%:%@])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return res_gsub
end

function _M.escape(s)
    res_gsub, n_gsub = string.gsub(s, "([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return res_gsub
end

function _M.unescape(s)
    res_gsub, n_gsub = string.gsub(s, "%%(%x%x)", function(hex)
        return string.char(base.tonumber(hex, 16))
    end)
    return res_gsub
end

function absolute_path(base_path, relative_path)
    if (string.sub(relative_path, 1, 1) == "/") then return relative_path end
    path_res = string.gsub(base_path, "[^/]*$", "")
    path_res = path_res .. relative_path
    path_res = string.gsub(path_res, "([^/]+%/%.%./)", "")
    path_res = string.gsub(path_res, "%/%.%/", "/")
    return path_res
end

function _M.parse(url_in, default_in)
    parsed_res = ({})
    if (url_in == nil or url_in == false) then return parsed_res end
    
    match_scheme = ({ string.match(url_in, "^([%w%.%+%a%-]+):(.*)") })
    scheme_res = match_scheme[1]
    rest_res = match_scheme[2]
    if (scheme_res != nil and scheme_res != false) then
        parsed_res.scheme = string.lower(scheme_res)
        url_in = rest_res
    end
    
    match_auth = ({ string.match(url_in, "^//([^/]*)(.*)") })
    auth_res = match_auth[1]
    rest_res = match_auth[2]
    if (auth_res != nil and auth_res != false) then
        parsed_res.authority = auth_res
        url_in = rest_res
    end
    
    match_frag = ({ string.match(url_in, "^(.*)#([^/]*)$") })
    rest_res = match_frag[1]
    frag_res = match_frag[2]
    if (frag_res != nil and frag_res != false) then
        parsed_res.fragment = frag_res
        url_in = rest_res
    end
    
    match_query = ({ string.match(url_in, "^(.*)%?([^/]*)$") })
    rest_res = match_query[1]
    query_res = match_query[2]
    if (query_res != nil and query_res != false) then
        parsed_res.query = query_res
        url_in = rest_res
    end
    
    if url_in != "" then parsed_res.path = url_in end
    
    for i_kv,v_kv in base.pairs(default_in or ({})) do
        if (parsed_res[i_kv] == nil or parsed_res[i_kv] == false) then parsed_res[i_kv] = v_kv end
    end
    
    if (parsed_res.authority != nil and parsed_res.authority != false) then
        match_user = ({ string.match(parsed_res.authority, "^([^@]*)@(.*)") })
        userinfo_res = match_user[1]
        hostport_res = match_user[2]
        if (userinfo_res != nil and userinfo_res != false) then
            parsed_res.userinfo = userinfo_res
            parsed_res.authority = hostport_res
        end
        
        match_host = ({ string.match(parsed_res.authority, "^([^:]*):(.*)$") })
        host_res = match_host[1]
        port_res = match_host[2]
        if (host_res != nil and host_res != false) then
            parsed_res.host = host_res
            parsed_res.port = base.tonumber(port_res)
        else
            parsed_res.host = parsed_res.authority
        end
    end
    
    return parsed_res
end

function _M.build(parsed_in)
    url_out = ""
    if (parsed_in.scheme != nil and parsed_in.scheme != false) then url_out = url_out .. parsed_in.scheme .. ":" end
    if (parsed_in.authority != nil and parsed_in.authority != false) then
        url_out = url_out .. "//" .. parsed_in.authority
    elseif (parsed_in.host != nil and parsed_in.host != false) then
        url_out = url_out .. "//"
        if (parsed_in.userinfo != nil and parsed_in.userinfo != false) then url_out = url_out .. parsed_in.userinfo .. "@" end
        url_out = url_out .. parsed_in.host
        if (parsed_in.port != nil and parsed_in.port != false) then url_out = url_out .. ":" .. base.tostring(parsed_in.port) end
    end
    if (parsed_in.path != nil and parsed_in.path != false) then url_out = url_out .. parsed_in.path end
    if (parsed_in.query != nil and parsed_in.query != false) then url_out = url_out .. "?" .. parsed_in.query end
    if (parsed_in.fragment != nil and parsed_in.fragment != false) then url_out = url_out .. "#" .. parsed_in.fragment end
    return url_out
end

function _M.absolute(base_url_in, relative_url_in)
    if (base_url_in == nil or base_url_in == false) then return relative_url_in end
    base_parsed_res = _M.parse(base_url_in)
    relative_parsed_res = _M.parse(relative_url_in)
    if (relative_parsed_res.scheme != nil and relative_parsed_res.scheme != false) then return relative_url_in end
    relative_parsed_res.scheme = base_parsed_res.scheme
    if (relative_parsed_res.authority == nil or relative_parsed_res.authority == false) then
        relative_parsed_res.authority = base_parsed_res.authority
        if (relative_parsed_res.path == nil or relative_parsed_res.path == false) then
            relative_parsed_res.path = base_parsed_res.path
            if (relative_parsed_res.query == nil or relative_parsed_res.query == false) then
                relative_parsed_res.query = base_parsed_res.query
            end
        else
            relative_parsed_res.path = absolute_path(base_parsed_res.path or "", relative_parsed_res.path)
        end
    end
    return _M.build(relative_parsed_res)
end

function _M.parse_path(path_in)
    t_res = ({})
    path_in = path_in or ""
    string.gsub(path_in, "([^/]+)", function(s_gsub) table.insert(t_res, s_gsub) end)
    if (string.sub(path_in, 1, 1) == "/") then t_res.is_absolute = 1 end
    if (string.sub(path_in, -1, -1) == "/") then t_res.is_directory = 1 end
    return t_res
end

function _M.build_path(parsed_in, unsafe_in)
    path_out = ""
    n_res = #parsed_in
    if (unsafe_in != nil and unsafe_in != false) then
        for i_res = 1, n_res do
            path_out = path_out .. "/" .. parsed_in[i_res]
        end
    else
        for i_res = 1, n_res do
            path_out = path_out .. "/" .. protect_segment(parsed_in[i_res])
        end
    end
    if (parsed_in.is_absolute != nil and parsed_in.is_absolute != false) then path_out = path_out .. "/" end
    if (parsed_in.is_directory != nil and parsed_in.is_directory != false) then path_out = path_out .. "/" end
    return (string.sub(path_out, 2))
end

return _M
