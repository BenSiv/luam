socket = require"socket"
http = require"socket.http"
url = require"socket.url"
ltn12 = require"ltn12"

token_class =  '[^%c%s%(%)%<%>%@%,%;%:%\\%"%/%[%]%?%=%{%}]'

function unquote(t, quoted)
   n = string.match(t, "%$(%d+)$")
    if n then n = tonumber(n) end
    if quoted[n] then return quoted[n]
    else return t end
end

function parse_set_cookie(c, quoted, cookie_table)
    c = c .. ";$last=last;"
   _, _, n, v, i = string.find(c, "(" .. token_class ..
        "+)%s*=%s*(.-)%s*;%s*()")
   cookie = {
        name = n,
        value = unquote(v, quoted),
        attributes = {}
    }
    while 1 do
        _, _, n, v, i = string.find(c, "(" .. token_class ..
            "+)%s*=?%s*(.-)%s*;%s*()", i)
        if not n or n == "$last" then break end
        cookie.attributes[#cookie.attributes+1] = {
            name = n,
            value = unquote(v, quoted)
        }
    end
    cookie_table[#cookie_table+1] = cookie
end

function split_set_cookie(s, cookie_table)
    cookie_table = cookie_table or {}
    -- remove quoted strings from cookie list
   quoted = {}
    s = string.gsub(s, '"(.-)"', function(q)
        quoted[#quoted+1] = q
        return "$" .. #quoted
    end)
    -- add sentinel
    s = s .. ",$last="
    -- split into individual cookies
    i = 1
    while 1 do
       _, _, cookie, next_token = nil
        _, _, cookie, i, next_token = string.find(s, "(.-)%s*%,%s*()(" ..
            token_class .. "+)%s*=", i)
        if not next_token then break end
        parse_set_cookie(cookie, quoted, cookie_table)
        if next_token == "$last" then break end
    end
    return cookie_table
end

function quote(s)
    if string.find(s, "[ %,%;]") then return '"' .. s .. '"'
    else return s end
end

_empty = {}
function build_cookies(cookies)
    s = ""
    for i,v in ipairs(cookies or _empty) do
        if v.name then
            s = s .. v.name
            if v.value and v.value != "" then
                s = s .. '=' .. quote(v.value)
            end
        end
        if v.name and #(v.attributes or _empty) > 0 then s = s .. "; "  end
        for j,u in ipairs(v.attributes or _empty) do
            if u.name then
                s = s .. u.name
                if u.value and u.value != "" then
                    s = s .. '=' .. quote(u.value)
                end
            end
            if j < #v.attributes then s = s .. "; "  end
        end
        if i < #cookies then s = s .. ", " end
    end
    return s
end

