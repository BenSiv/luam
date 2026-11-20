-- Shared CGI helpers: environment detection, request routing,
-- cookies, response headers, and query parameter parsing.

cgi = {}

-- Helper to safely coalesce nil values in Luam (where `or` requires booleans)
function default_val(val, fallback)
    if val == nil then return fallback end
    return val
end

function check_header_value(val, label)
    s = tostring(val)
    if string.find(s, "[\r\n%z]") != nil then
        error("invalid CR/LF/NUL in HTTP " .. label, 2)
    end
    return s
end

function check_cookie_part(val, label, forbid_equals)
    s = tostring(val)
    if string.find(s, "[\r\n%z;]") != nil then
        error("invalid character in cookie " .. label, 2)
    end
    if forbid_equals and (s == "" or string.find(s, "=", 1, true) != nil) then
        error("invalid cookie name", 2)
    end
    return s
end

-- True if currently executing under a CGI server environment.
function cgi.is_cgi()
    gateway = os.getenv("GATEWAY_INTERFACE")
    method  = os.getenv("REQUEST_METHOD")
    return (gateway != nil and gateway != "") or (method != nil and method != "")
end

-- True when the browser reached us over TLS (via the standard CGI HTTPS env var).
function cgi.is_https()
    https = os.getenv("HTTPS")
    return https != nil and https != "" and string.lower(https) != "off"
end

-- URL-decode a string value.
function cgi.url_decode(str)
    if str == nil then return "" end
    return (string.gsub(string.gsub(str, "+", " "), "%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

-- Parse query string (e.g. "a=1&b=two") into a table.
function cgi.parse_query(query_str)
    params = {}
    if query_str == nil or query_str == "" then
        return params
    end
    for k, v in string.gmatch(query_str, "([^&=]+)=([^&=]*)") do
        params[cgi.url_decode(k)] = cgi.url_decode(v)
    end
    return params
end

-- Parses the raw "k1=v1; k2=v2" HTTP_COOKIE env var into a table.
function cgi.parse_cookies(cookie_header)
    cookies = {}
    if cookie_header == nil then
        return cookies
    end
    for pair in string.gmatch(cookie_header, "([^;]+)") do
        key, value = string.match(pair, "%s*([^=]+)=(.*)")
        if key != nil then
            cookies[key] = value
        end
    end
    return cookies
end

-- Builds one Set-Cookie header line. Marks Secure automatically whenever
-- the request itself arrived over TLS (HTTPS env var).
function cgi.set_cookie_header(name, value, max_age_seconds, http_only)
    safe_name = check_cookie_part(name, "name", true)
    safe_value = check_cookie_part(value, "value", false)
    parts = {safe_name .. "=" .. safe_value, "Path=/", "SameSite=Lax"}
    if max_age_seconds != nil then
        age_num = tonumber(max_age_seconds)
        if age_num == nil then
            error("cookie max_age_seconds must be a number", 2)
        end
        table.insert(parts, "Max-Age=" .. tostring(math.floor(age_num)))
    end
    if http_only == true then
        table.insert(parts, "HttpOnly")
    end
    if cgi.is_https() then
        table.insert(parts, "Secure")
    end
    return "Set-Cookie: " .. table.concat(parts, "; ")
end

function cgi.clear_cookie_header(name)
    safe_name = check_cookie_part(name, "name", true)
    return "Set-Cookie: " .. safe_name .. "=; Path=/; Max-Age=0"
end

-- Write standard CGI HTTP response headers and body to stdout.
-- `opts.headers` may contain either a list of raw "Name: value" header lines
-- (needed when emitting multiple Set-Cookie headers) or key/value pairs.
function cgi.respond(opts)
    status = check_header_value(default_val(opts.status, "200 OK"), "status")
    content_type = check_header_value(default_val(opts.content_type, "text/html; charset=utf-8"), "content_type")
    body = default_val(opts.body, "")

    io.write("Status: " .. status .. "\r\n")
    io.write("Content-Type: " .. content_type .. "\r\n")
    if opts.cache_control != nil then
        io.write("Cache-Control: " .. check_header_value(opts.cache_control, "cache_control") .. "\r\n")
    end
    if opts.headers != nil then
        for k, v in pairs(opts.headers) do
            if type(k) == "number" then
                io.write(check_header_value(v, "header") .. "\r\n")
            else
                io.write(check_header_value(k, "header name") .. ": " .. check_header_value(v, "header value") .. "\r\n")
            end
        end
    end
    io.write("Content-Length: " .. string.len(body) .. "\r\n")
    io.write("\r\n")
    if body != "" then
        io.write(body)
    end
end

-- Respond with 500 error.
function cgi.respond_error(err)
    cgi.respond({
        status = "500 Internal Server Error",
        content_type = "text/plain; charset=utf-8",
        body = "Internal Server Error: " .. tostring(err) .. "\n"
    })
end

-- Simple router dispatching based on PATH_INFO.
-- routes table maps path string to handler function, with optional fallback / 404 handler.
function cgi.dispatch(routes, fallback_fn)
    path = os.getenv("PATH_INFO")
    if path == nil or path == "" then
        path = "/"
    end

    handler = routes[path]
    if handler != nil then
        handler()
    elseif fallback_fn != nil then
        fallback_fn(path)
    else
        cgi.respond({
            status = "404 Not Found",
            content_type = "text/plain; charset=utf-8",
            body = "Not Found: " .. path .. "\n"
        })
    end
end

return cgi
