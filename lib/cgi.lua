-- Shared CGI helpers: environment detection, request routing,
-- response headers, and query parameter parsing.

cgi = {}

-- Helper to safely coalesce nil values in Luam (where `or` requires booleans)
function default_val(val, fallback)
    if val == nil then return fallback end
    return val
end

-- True if currently executing under a CGI server environment.
function cgi.is_cgi()
    gateway = os.getenv("GATEWAY_INTERFACE")
    method  = os.getenv("REQUEST_METHOD")
    return (gateway != nil and gateway != "") or (method != nil and method != "")
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

-- Write standard CGI HTTP response headers and body to stdout.
function cgi.respond(opts)
    status = default_val(opts.status, "200 OK")
    content_type = default_val(opts.content_type, "text/html; charset=utf-8")
    body = default_val(opts.body, "")

    io.write("Status: " .. status .. "\r\n")
    io.write("Content-Type: " .. content_type .. "\r\n")
    if opts.cache_control != nil then
        io.write("Cache-Control: " .. opts.cache_control .. "\r\n")
    end
    if opts.headers != nil then
        for k, v in pairs(opts.headers) do
            io.write(k .. ": " .. v .. "\r\n")
        end
    end
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
