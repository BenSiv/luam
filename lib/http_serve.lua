-- Pure-Luam HTTP/1.1 loopback & local-gateway server over `lib/net` and `lib/task`.
--
-- Supports:
--   - Cooperative concurrent connections via `lib/task` + `lib/poll`
--   - `Content-Length` and incoming `Transfer-Encoding: chunked` request bodies
--   - `Expect: 100-continue` immediate handshake
--   - HTTP/1.1 keep-alive with idle timeouts and `Connection: close`
--   - `port = 0` ephemeral port binding + atomic `port_file` publication
--   - Attaching onto an existing `task` loop (`opts.loop`) for multi-service daemons

const paths = require("paths")
const task = require("task")

has_net, net = pcall(require, "net")
has_poll, poll = pcall(require, "poll")

const http_serve = {}

const REASON_PHRASES = {
    [100] = "Continue",
    [200] = "OK",
    [201] = "Created",
    [202] = "Accepted",
    [204] = "No Content",
    [301] = "Moved Permanently",
    [302] = "Found",
    [303] = "See Other",
    [304] = "Not Modified",
    [307] = "Temporary Redirect",
    [308] = "Permanent Redirect",
    [400] = "Bad Request",
    [401] = "Unauthorized",
    [403] = "Forbidden",
    [404] = "Not Found",
    [405] = "Method Not Allowed",
    [408] = "Request Timeout",
    [413] = "Content Too Large",
    [431] = "Request Header Fields Too Large",
    [500] = "Internal Server Error",
    [502] = "Bad Gateway",
    [503] = "Service Unavailable",
    [504] = "Gateway Timeout",
}

function http_serve.is_available()
    return has_net == true and type(net) == "table" and has_poll == true and type(poll) == "table"
end

function percent_decode_path(raw)
    if raw == nil or raw == "" then
        return "/"
    end
    return (string.gsub(raw, "%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

function extract_remote_addr(peer)
    if peer == nil or peer == "" then
        return "127.0.0.1"
    end
    ipv6 = string.match(peer, "^%[([^%]]+)%]:%d+$")
    if ipv6 != nil then
        return ipv6
    end
    ipv4 = string.match(peer, "^([^:]+):%d+$")
    if ipv4 != nil then
        return ipv4
    end
    return peer
end

function has_ctl(s)
    return string.find(s, "[\r\n%z]") != nil
end

function default_val(val, fallback)
    if val == nil then
        return fallback
    end
    return val
end

-- Parses an HTTP/1.x request header block (up to, not necessarily including, `\r\n\r\n`).
-- Returns `req_tbl, nil, nil` or `nil, http_status, err_msg`.
function http_serve.parse_request_head(head_bytes)
    if type(head_bytes) != "string" or head_bytes == "" then
        return nil, 400, "empty request header"
    end

    normalized = string.gsub(head_bytes, "\r\n", "\n")
    lines = string.split(normalized, "\n")
    if #lines == 0 or lines[1] == "" then
        return nil, 400, "missing request line"
    end

    req_line = lines[1]
    sp1 = string.index_of(req_line, " ")
    if sp1 == nil or sp1 <= 1 then
        return nil, 400, "malformed request line"
    end
    sp2 = string.index_of(req_line, " ", sp1 + 1)
    if sp2 == nil or sp2 <= sp1 + 1 or string.index_of(req_line, " ", sp2 + 1) != nil then
        return nil, 400, "malformed request line"
    end
    method = string.sub(req_line, 1, sp1 - 1)
    target = string.sub(req_line, sp1 + 1, sp2 - 1)
    version = string.sub(req_line, sp2 + 1)
    if string.match(method, "^[%w!#$%%&'*+%-%.^_`|~]+$") == nil or string.find(target, "%c") != nil then
        return nil, 400, "malformed request line"
    end
    if version != "HTTP/1.1" and version != "HTTP/1.0" then
        return nil, 400, "unsupported HTTP version"
    end

    raw_path = target
    query = ""
    q_idx = string.index_of(target, "?")
    if q_idx != nil then
        raw_path = string.sub(target, 1, q_idx - 1)
        query = string.sub(target, q_idx + 1)
    end
    if raw_path == "" then
        raw_path = "/"
    end
    decoded_path = percent_decode_path(raw_path)
    if string.contains(decoded_path, "\0") then
        return nil, 400, "NUL byte in request path"
    end

    headers = {}
    raw_headers = {}
    seen_content_length = nil

    i = 2
    while i <= #lines do
        line = lines[i]
        if line != "" then
            colon = string.index_of(line, ":")
            if colon == nil or colon <= 1 then
                return nil, 400, "malformed header line"
            end
            h_name = string.sub(line, 1, colon - 1)
            if string.find(h_name, "[ \t%c]") != nil then
                return nil, 400, "invalid header field name"
            end
            h_val = string.trim(string.sub(line, colon + 1))
            if string.contains(h_val, "\0") then
                return nil, 400, "NUL byte in header value"
            end
            low = string.lower(h_name)
            if low == "content-length" then
                if string.match(h_val, "^%d+$") == nil then
                    return nil, 400, "invalid Content-Length"
                end
                if seen_content_length != nil and seen_content_length != h_val then
                    return nil, 400, "conflicting Content-Length headers"
                end
                seen_content_length = h_val
                headers[low] = h_val
            elseif headers[low] != nil then
                if low == "cookie" then
                    headers[low] = headers[low] .. "; " .. h_val
                else
                    headers[low] = headers[low] .. ", " .. h_val
                end
            else
                headers[low] = h_val
            end
            table.insert(raw_headers, {name = h_name, value = h_val})
        end
        i = i + 1
    end

    if version == "HTTP/1.1" and headers["host"] == nil then
        return nil, 400, "missing Host header in HTTP/1.1 request"
    end

    return {
        method = method,
        target = target,
        raw_path = raw_path,
        path = decoded_path,
        query = query,
        version = version,
        headers = headers,
        raw_headers = raw_headers,
        body = "",
    }, nil, nil
end

-- Serializes `{status, reason, headers, body}` into HTTP/1.1 wire bytes.
-- When `head_only == true`, preserves `Content-Length` while omitting payload bytes.
function http_serve.format_response(resp, head_only, force_close)
    status_code = 200
    reason = nil
    if resp != nil and resp.status != nil then
        if type(resp.status) == "number" then
            status_code = math.floor(resp.status)
        elseif type(resp.status) == "string" then
            code_str, msg_str = string.match(resp.status, "^(%d%d%d)%s*(.*)$")
            if code_str != nil then
                status_code = tonumber(code_str)
                if msg_str != nil and msg_str != "" then
                    reason = msg_str
                end
            end
        end
    end
    if resp != nil and type(resp.reason) == "string" and resp.reason != "" then
        reason = resp.reason
    end
    if reason == nil or reason == "" then
        reason = REASON_PHRASES[status_code]
        if reason == nil then
            reason = "OK"
        end
    end
    if has_ctl(reason) then
        error("invalid CR/LF/NUL in HTTP status reason", 0)
    end

    body = ""
    if resp != nil and resp.body != nil then
        body = tostring(resp.body)
    end

    header_lines = {string.format("HTTP/1.1 %d %s", status_code, reason)}
    has_content_length = false
    has_content_type = false
    has_connection = false

    function push_hdr(k, v)
        ks = tostring(k)
        vs = tostring(v)
        if ks == "" or has_ctl(ks) or string.contains(ks, ":") or has_ctl(vs) then
            error("invalid HTTP response header", 0)
        end
        low = string.lower(ks)
        if low == "content-length" then
            has_content_length = true
        elseif low == "content-type" then
            has_content_type = true
        elseif low == "connection" then
            has_connection = true
        end
        table.insert(header_lines, ks .. ": " .. vs)
    end

    if resp != nil and type(resp.headers) == "table" then
        for k, v in pairs(resp.headers) do
            if type(k) == "number" then
                if type(v) == "table" and v[1] != nil and v[2] != nil then
                    push_hdr(v[1], v[2])
                elseif type(v) == "string" then
                    colon = string.index_of(v, ":")
                    if colon == nil or colon <= 1 then
                        error("invalid raw HTTP header line: " .. v, 0)
                    end
                    push_hdr(string.sub(v, 1, colon - 1), string.trim(string.sub(v, colon + 1)))
                end
            else
                push_hdr(k, v)
            end
        end
    end

    if not has_content_type and status_code != 204 and status_code != 304 and #body > 0 then
        table.insert(header_lines, "Content-Type: text/plain; charset=utf-8")
    end
    if not has_content_length and status_code != 204 and status_code != 304 then
        table.insert(header_lines, "Content-Length: " .. tostring(#body))
    end
    if not has_connection then
        if force_close == true then
            table.insert(header_lines, "Connection: close")
        else
            table.insert(header_lines, "Connection: keep-alive")
        end
    end

    head_wire = table.concat(header_lines, "\r\n") .. "\r\n\r\n"
    if head_only == true or status_code == 204 or status_code == 304 or #body == 0 then
        return head_wire, status_code
    end
    return head_wire .. body, status_code
end

function write_all(conn, data, timeout_ms)
    total = #data
    pos = 1
    while pos <= total do
        nw, err = net.write(conn, data, pos)
        if nw == nil then
            return false, err
        end
        if nw > 0 then
            pos = pos + nw
        else
            ev, why = task.wait_fd(net.fd(conn), "w", timeout_ms)
            if ev == nil then
                return false, why
            end
        end
    end
    return true, nil
end

function read_more(conn, max_bytes, timeout_ms)
    while true do
        chunk, eof = net.read(conn, max_bytes)
        if chunk == nil then
            return nil, false, tostring(eof)
        end
        if #chunk > 0 or eof then
            return chunk, eof, nil
        end
        ev, why = task.wait_fd(net.fd(conn), "r", timeout_ms)
        if ev == nil then
            return nil, false, why
        end
    end
end

function find_header_end(buf)
    idx = string.index_of(buf, "\r\n\r\n")
    if idx != nil then
        return idx, idx + 4
    end
    idx2 = string.index_of(buf, "\n\n")
    if idx2 != nil then
        return idx2, idx2 + 2
    end
    return nil, nil
end

function read_fixed_body(conn, initial, need_len, timeout_ms)
    if need_len == 0 then
        return "", initial, nil
    end
    if #initial >= need_len then
        return string.sub(initial, 1, need_len), string.sub(initial, need_len + 1), nil
    end

    parts = {}
    have = 0
    if #initial > 0 then
        table.insert(parts, initial)
        have = #initial
    end
    while have < need_len do
        want = need_len - have
        if want > 32768 then
            want = 32768
        end
        chunk, eof, rerr = read_more(conn, want, timeout_ms)
        if chunk == nil then
            return nil, "", rerr
        end
        if #chunk > 0 then
            table.insert(parts, chunk)
            have = have + #chunk
        end
        if eof and have < need_len then
            return nil, "", "unexpected EOF in request body"
        end
    end
    joined = table.concat(parts)
    return string.sub(joined, 1, need_len), string.sub(joined, need_len + 1), nil
end

function read_chunked_body(conn, initial, max_body_bytes, timeout_ms)
    buf = initial
    chunks = {}
    total = 0

    function ensure_bytes(min_len)
        while #buf < min_len do
            more, eof, rerr = read_more(conn, 16384, timeout_ms)
            if more == nil then
                return false, rerr
            end
            if #more > 0 then
                buf = buf .. more
            end
            if eof and #buf < min_len then
                return false, "unexpected EOF in chunked body"
            end
        end
        return true, nil
    end

    function read_line_crlf()
        while true do
            nl = string.index_of(buf, "\r\n")
            if nl != nil then
                line = string.sub(buf, 1, nl - 1)
                buf = string.sub(buf, nl + 2)
                return line, nil
            end
            if #buf > 4096 then
                return nil, "chunk header line too long"
            end
            more, eof, rerr = read_more(conn, 8192, timeout_ms)
            if more == nil then
                return nil, rerr
            end
            if #more > 0 then
                buf = buf .. more
            elseif eof then
                return nil, "unexpected EOF reading chunk size"
            end
        end
    end

    while true do
        size_line, lerr = read_line_crlf()
        if size_line == nil then
            return nil, "", 400, lerr
        end
        -- Strip optional `;ext=val` chunk extensions
        semi = string.index_of(size_line, ";")
        if semi != nil then
            size_line = string.sub(size_line, 1, semi - 1)
        end
        size_hex = string.trim(size_line)
        if string.match(size_hex, "^%x+$") == nil then
            return nil, "", 400, "invalid chunk size"
        end
        chunk_len = tonumber(size_hex, 16)
        if chunk_len == nil or chunk_len < 0 then
            return nil, "", 400, "invalid chunk size"
        end
        if chunk_len == 0 then
            -- Consume trailing headers up to empty line `\r\n`
            while true do
                tr_line, terr = read_line_crlf()
                if tr_line == nil then
                    return nil, "", 400, terr
                end
                if tr_line == "" then
                    break
                end
            end
            return table.concat(chunks), buf, nil, nil
        end

        if total + chunk_len > max_body_bytes then
            return nil, "", 413, "chunked body exceeds max_body_bytes"
        end

        ok_b, berr = ensure_bytes(chunk_len + 2)
        if not ok_b then
            return nil, "", 400, berr
        end
        if string.sub(buf, chunk_len + 1, chunk_len + 2) != "\r\n" then
            return nil, "", 400, "missing CRLF after chunk payload"
        end
        table.insert(chunks, string.sub(buf, 1, chunk_len))
        total = total + chunk_len
        buf = string.sub(buf, chunk_len + 3)
    end
end

function should_close_conn(req, resp, srv)
    if srv.once == true or srv.stopping == true or srv.keep_alive_timeout_ms <= 0 then
        return true
    end
    req_conn = string.lower(tostring(default_val(req.headers["connection"], "")))
    if string.contains(req_conn, "close") then
        return true
    end
    if req.version == "HTTP/1.0" and not string.contains(req_conn, "keep-alive") then
        return true
    end
    if resp != nil and type(resp.headers) == "table" then
        for k, v in pairs(resp.headers) do
            if type(k) == "string" and string.lower(k) == "connection" and string.contains(string.lower(tostring(v)), "close") then
                return true
            end
        end
    end
    return false
end

function serve_connection(srv, conn, peer)
    srv.active_conns = srv.active_conns + 1
    leftover = ""
    reqs_on_conn = 0

    while not srv.stopping do
        wait_timeout = srv.header_timeout_ms
        if reqs_on_conn > 0 then
            wait_timeout = srv.keep_alive_timeout_ms
        end

        head_end = nil
        after_head = nil
        read_aborted = false

        while true do
            head_end, after_head = find_header_end(leftover)
            if head_end != nil then
                if (head_end - 1) > srv.max_header_bytes then
                    err_wire, _ = http_serve.format_response({status = 431, body = "Request Header Fields Too Large\n"}, false, true)
                    write_all(conn, err_wire, 2000)
                    read_aborted = true
                end
                break
            end
            if #leftover > srv.max_header_bytes then
                err_wire, _ = http_serve.format_response({status = 431, body = "Request Header Fields Too Large\n"}, false, true)
                write_all(conn, err_wire, 2000)
                read_aborted = true
                break
            end
            chunk, eof, rerr = read_more(conn, 8192, wait_timeout)
            if chunk == nil then
                -- Clean idle keep-alive timeout when no bytes arrived yet
                if #leftover > 0 and rerr == "timeout" then
                    err_wire, _ = http_serve.format_response({status = 408, body = "Request Timeout\n"}, false, true)
                    write_all(conn, err_wire, 2000)
                end
                read_aborted = true
                break
            end
            if #chunk > 0 then
                leftover = leftover .. chunk
            end
            if eof then
                read_aborted = true
                break
            end
        end

        if read_aborted or head_end == nil then
            break
        end

        head_raw = string.sub(leftover, 1, head_end - 1)
        leftover = string.sub(leftover, after_head)

        req, bad_status, bad_msg = http_serve.parse_request_head(head_raw)
        if req == nil then
            err_wire, _ = http_serve.format_response({status = bad_status, body = tostring(bad_msg) .. "\n"}, false, true)
            write_all(conn, err_wire, 2000)
            break
        end

        req.peer = peer
        req.remote_addr = extract_remote_addr(peer)
        req.server_host = srv.host
        req.server_port = srv.actual_port

        expect_hdr = req.headers["expect"]
        if expect_hdr != nil and string.lower(expect_hdr) == "100-continue" then
            ok_100, _ = write_all(conn, "HTTP/1.1 100 Continue\r\n\r\n", 2000)
            if not ok_100 then
                break
            end
        end

        te_hdr = req.headers["transfer-encoding"]
        cl_hdr = req.headers["content-length"]
        if te_hdr != nil and string.contains(string.lower(te_hdr), "chunked") then
            body_bytes, rest, c_status, c_err = read_chunked_body(conn, leftover, srv.max_body_bytes, srv.body_timeout_ms)
            if body_bytes == nil then
                err_wire, _ = http_serve.format_response({status = c_status, body = tostring(c_err) .. "\n"}, false, true)
                write_all(conn, err_wire, 2000)
                break
            end
            req.body = body_bytes
            leftover = rest
        elseif cl_hdr != nil then
            need_len = tonumber(cl_hdr)
            if need_len > srv.max_body_bytes then
                err_wire, _ = http_serve.format_response({status = 413, body = "Content Too Large\n"}, false, true)
                write_all(conn, err_wire, 2000)
                break
            end
            body_bytes, rest, b_err = read_fixed_body(conn, leftover, need_len, srv.body_timeout_ms)
            if body_bytes == nil then
                err_wire, _ = http_serve.format_response({status = 400, body = tostring(b_err) .. "\n"}, false, true)
                write_all(conn, err_wire, 2000)
                break
            end
            req.body = body_bytes
            leftover = rest
        else
            req.body = ""
        end

        -- Invoke handler directly inside this coroutine so async handlers (`cgi_serve`, proxies) may yield on `srv.loop`!
        resp = srv.handler(req, srv.loop)
        if type(resp) != "table" then
            resp = {status = 500, body = "Invalid server handler response\n"}
        end

        close_after = should_close_conn(req, resp, srv)
        ok_fmt, wire_or_err, status_num = pcall(http_serve.format_response, resp, req.method == "HEAD", close_after)
        if not ok_fmt then
            wire_or_err, status_num = http_serve.format_response({status = 500, body = "Response serialization error\n"}, req.method == "HEAD", true)
            close_after = true
        end

        if srv.on_log != nil then
            srv.on_log(req, status_num, peer)
        end

        ok_w, _ = write_all(conn, wire_or_err, srv.body_timeout_ms)
        reqs_on_conn = reqs_on_conn + 1
        srv.handled_requests = srv.handled_requests + 1

        if srv.once == true then
            http_serve.stop(srv)
            break
        end
        if not ok_w or close_after then
            break
        end
    end

    net.close(conn)
    srv.active_conns = srv.active_conns - 1
end

function accept_loop(srv)
    while not srv.stopping do
        if srv.active_conns >= srv.max_conns then
            task.sleep_ms(10)
        else
            conn, peer_or_why = net.accept(srv.listener)
            if conn != nil then
                task.spawn(srv.loop, function(c, p)
                    serve_connection(srv, c, p)
                end, conn, peer_or_why)
                if srv.once == true then
                    -- Stop accepting additional connections once the single request is in flight
                    net.close(srv.listener)
                    break
                end
            elseif peer_or_why == "again" then
                task.wait_fd(net.fd(srv.listener), "r", 250)
            else
                if not srv.stopping then
                    task.sleep_ms(10)
                end
            end
        end
    end
end

function write_port_file_atomic(port_file, port_num)
    tmp = port_file .. ".tmp." .. tostring(os.time_ms())
    ok_w, err_w = paths.write_file(tmp, tostring(port_num) .. "\n")
    if not ok_w then
        return false, err_w
    end
    ok_rn, err_rn = os.rename(tmp, port_file)
    if ok_rn == nil then
        os.remove(tmp)
        return false, tostring(err_rn)
    end
    return true, nil
end

function http_serve.open(opts)
    if type(opts) != "table" then
        return nil, "http_serve.open expects an options table"
    end
    if not http_serve.is_available() then
        return nil, "net and poll modules are required for http_serve"
    end
    if type(opts.handler) != "function" then
        return nil, "http_serve.open requires opts.handler function"
    end

    host = opts.host
    if host == nil or host == "" then
        host = "127.0.0.1"
    end

    port = 8000
    if opts.port != nil then
        pnum = tonumber(opts.port)
        if pnum == nil or pnum < 0 or pnum > 65535 then
            return nil, "opts.port must be between 0 and 65535"
        end
        port = math.floor(pnum)
    end

    listener, lerr = net.listen_tcp(host, port, {nonblocking = true, backlog = opts.backlog})
    if listener == nil then
        return nil, lerr
    end
    actual_port = net.local_port(listener)

    owns_loop = false
    loop = opts.loop
    if loop == nil then
        loop, loop_err = task.new({
            on_error = function(err_msg)
                if opts.quiet != true then
                    io.write(io.stderr, "[http_serve] handler error: " .. tostring(err_msg) .. "\n")
                end
            end,
        })
        if loop == nil then
            net.close(listener)
            return nil, loop_err
        end
        owns_loop = true
    end

    srv = {
        host = host,
        actual_port = actual_port,
        listener = listener,
        loop = loop,
        owns_loop = owns_loop,
        handler = opts.handler,
        on_log = opts.on_log,
        once = (opts.once == true),
        quiet = (opts.quiet == true),
        max_conns = default_val(opts.max_conns, 128),
        max_header_bytes = default_val(opts.max_header_bytes, 32768),
        max_body_bytes = default_val(opts.max_body_bytes, 67108864),
        header_timeout_ms = default_val(opts.header_timeout_ms, 10000),
        body_timeout_ms = default_val(opts.body_timeout_ms, 30000),
        keep_alive_timeout_ms = default_val(opts.keep_alive_timeout_ms, 5000),
        active_conns = 0,
        handled_requests = 0,
        stopping = false,
        closed = false,
    }

    if opts.port_file != nil and opts.port_file != "" then
        ok_pf, err_pf = write_port_file_atomic(opts.port_file, actual_port)
        if not ok_pf then
            net.close(listener)
            if owns_loop then
                task.close(loop)
            end
            return nil, "failed writing port_file: " .. tostring(err_pf)
        end
    end

    task.spawn(loop, function()
        accept_loop(srv)
    end)

    return srv, nil
end

function http_serve.port(srv)
    return srv.actual_port
end

function http_serve.stop(srv)
    if srv != nil and not srv.stopping then
        srv.stopping = true
        net.close(srv.listener)
    end
    return true
end

function http_serve.close(srv)
    if srv != nil and not srv.closed then
        srv.closed = true
        srv.stopping = true
        net.close(srv.listener)
        if srv.owns_loop then
            task.close(srv.loop)
        end
    end
    return true
end

function http_serve.run(opts)
    srv, err = http_serve.open(opts)
    if srv == nil then
        return false, err
    end

    sig_h = nil
    if opts.handle_signals != false then
        sh, _ = poll.signal_open({"INT", "TERM"})
        if sh != nil then
            sig_h = sh
            task.spawn(srv.loop, function()
                sfd = poll.signal_fd(sig_h)
                while not srv.stopping do
                    sname = poll.signal_read(sig_h)
                    if sname != nil then
                        http_serve.stop(srv)
                        break
                    end
                    task.wait_fd(sfd, "r", 250)
                end
            end)
        end
    end

    if opts.on_ready != nil then
        opts.on_ready(srv.actual_port, srv)
    end

    ok_run, run_err = pcall(task.run, srv.loop)
    if sig_h != nil then
        poll.signal_close(sig_h)
    end
    http_serve.close(srv)

    if not ok_run then
        return false, tostring(run_err)
    end
    return true, nil
end

return http_serve
