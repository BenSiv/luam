-- Test suite for `lib/http_serve.lua` and Python-free `lib/cgi_serve.lua`:
--   1. `parse_request_head` & `format_response` edge cases + CRLF/NUL/smuggling guards
--   2. HTTP/1.1 keep-alive, `Transfer-Encoding: chunked`, `Expect: 100-continue`, `HEAD`, `413`/`431`
--   3. `laws.forall` HTTP request/response loopback round-trip over shared `task` loop
--   4. Zero-Python `cgi_serve` proof (`PATH` stripped of `python3`), httpoxy (`Proxy:`) block,
--      multiple `Set-Cookie` headers, 256 KB binary POST CGI pipe streaming, CGI timeout (`502`),
--      and standalone `luam build` static binary serving CGI

const cgi_serve = require("cgi_serve")
const dkjson = require("dkjson")
const ext = require("external_tool")
const git = require("git")
const http = require("http")
const http_serve = require("http_serve")
const laws = require("laws")
const lfs = require("lfs")
const net = require("net")
const paths = require("paths")
const proc = require("proc")
const t = require("test")
const task = require("task")

tmp_dir = os.tmpname()
os.remove(tmp_dir)
paths.ensure_dir(tmp_dir)

-- ---- 1. Parser & response serializer guards ----
t.run("parser_and_serializer_guards", function()
    req_ok, st_ok, _ = http_serve.parse_request_head(table.concat({
        "POST /items/hello%20world?x=1&y=2 HTTP/1.1",
        "Host: 127.0.0.1:8080",
        "Cookie: a=1",
        "Cookie: b=2",
        "X-Tag: first",
        "X-Tag: second",
        "Content-Length: 5",
    }, "\r\n"))
    t.eq(st_ok, nil, "valid request head status nil")
    t.eq(req_ok.method, "POST", "parsed method")
    t.eq(req_ok.path, "/items/hello world", "percent-decoded path")
    t.eq(req_ok.raw_path, "/items/hello%20world", "preserved raw_path")
    t.eq(req_ok.query, "x=1&y=2", "parsed query")
    t.eq(req_ok.headers["cookie"], "a=1; b=2", "cookies joined with '; '")
    t.eq(req_ok.headers["x-tag"], "first, second", "duplicate headers joined with ', '")

    r_no_host, st_no_host, _ = http_serve.parse_request_head("GET / HTTP/1.1\r\nUser-Agent: x")
    t.eq(r_no_host, nil, "HTTP/1.1 without Host rejected")
    t.eq(st_no_host, 400, "missing Host -> 400")

    r_smug, st_smug, _ = http_serve.parse_request_head("POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4\r\nContent-Length: 8")
    t.eq(r_smug, nil, "conflicting Content-Length rejected")
    t.eq(st_smug, 400, "conflicting Content-Length -> 400")

    r_nul, st_nul, _ = http_serve.parse_request_head("GET /a%00b HTTP/1.1\r\nHost: localhost")
    t.eq(r_nul, nil, "percent-encoded NUL in path rejected")
    t.eq(st_nul, 400, "NUL path -> 400")

    t.throws(function()
        http_serve.format_response({status = 200, headers = {["X-Bad"] = "ok\r\nInjected: 1"}, body = "hi"})
    end, "invalid", "CRLF injection in response header rejected")

    head_wire, head_code = http_serve.format_response({
        status = "201 Created",
        headers = {
            {"Set-Cookie", "s1=a; Path=/"},
            {"Set-Cookie", "s2=b; Path=/"},
        },
        body = "HELLO",
    }, true, false)
    t.eq(head_code, 201, "format_response status 201")
    t.check(string.contains(head_wire, "Content-Length: 5\r\n"), "HEAD response retains Content-Length")
    t.check(string.contains(head_wire, "Set-Cookie: s1=a; Path=/\r\nSet-Cookie: s2=b; Path=/\r\n"), "multiple Set-Cookie headers emitted")
    t.check(string.ends_with(head_wire, "\r\n\r\n"), "HEAD response omits body bytes")
end)

-- ---- 2. HTTP/1.1 keep-alive, chunked request body, 100-continue, HEAD, 413/431 ----
t.run("http11_wire_features", function()
    loop = task.new()
    srv, err = http_serve.open({
        host = "127.0.0.1",
        port = 0,
        loop = loop,
        max_header_bytes = 1024,
        max_body_bytes = 4096,
        keep_alive_timeout_ms = 2000,
        handler = function(req)
            return {
                status = 200,
                headers = {["Content-Type"] = "application/json"},
                body = dkjson.encode({
                    method = req.method,
                    path = req.path,
                    len = #req.body,
                    body = req.body,
                }),
            }
        end,
    })
    t.eq(err, nil, "http_serve.open ok")
    port = http_serve.port(srv)

    function read_http_resp(conn)
        buf = ""
        while string.index_of(buf, "\r\n\r\n") == nil do
            ch, eof = net.read(conn, 4096)
            if #ch > 0 then
                buf = buf .. ch
            elseif eof then
                break
            else
                task.wait_fd(net.fd(conn), "r", 1000)
            end
        end
        sep = string.index_of(buf, "\r\n\r\n")
        hdr_part = string.sub(buf, 1, sep - 1)
        rest = string.sub(buf, sep + 4)
        status = tonumber(string.match(hdr_part, "^HTTP/1%.1 (%d%d%d)"))
        cl_str = string.match(string.lower(hdr_part), "content%-length:%s*(%d+)")
        need = 0
        if cl_str != nil then
            need = tonumber(cl_str)
        end
        return status, hdr_part, rest, need
    end

    function read_exact_body(conn, rest, need)
        while #rest < need do
            ch, eof = net.read(conn, need - #rest)
            if #ch > 0 then
                rest = rest .. ch
            elseif eof then
                break
            else
                task.wait_fd(net.fd(conn), "r", 1000)
            end
        end
        return string.sub(rest, 1, need)
    end

    task.spawn(loop, function()
        -- Single TCP connection carrying 3 sequential keep-alive requests:
        --   (a) Expect: 100-continue POST
        --   (b) Transfer-Encoding: chunked PUT with chunk extension
        --   (c) HEAD request
        c, cerr = net.connect_tcp("127.0.0.1", port, 1000)
        t.eq(cerr, nil, "client connected")
        net.set_nonblocking(c, true)

        -- (a) Expect: 100-continue
        net.write(c, "POST /expect HTTP/1.1\r\nHost: localhost\r\nExpect: 100-continue\r\nContent-Length: 9\r\n\r\n")
        st_100, _, rest_100, _ = read_http_resp(c)
        t.eq(st_100, 100, "received 100 Continue")
        net.write(c, "CONT_BODY")
        -- If bytes arrived right after 100 Continue, rest_100 is empty here
        st_a, _, rest_a, need_a = read_http_resp(c)
        body_a = read_exact_body(c, rest_a, need_a)
        t.eq(st_a, 200, "100-continue POST 200")
        dec_a = dkjson.decode(body_a)
        t.eq(dec_a.body, "CONT_BODY", "100-continue body intact")

        -- (b) Chunked request on the SAME keep-alive connection
        chunk_wire = table.concat({
            "PUT /chunked HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n",
            "5;ext=foo\r\nHELLO\r\n",
            "6\r\n_WORLD\r\n",
            "0\r\nX-Trailer: ignored\r\n\r\n",
        })
        net.write(c, chunk_wire)
        st_b, _, rest_b, need_b = read_http_resp(c)
        body_b = read_exact_body(c, rest_b, need_b)
        t.eq(st_b, 200, "chunked PUT on keep-alive connection 200")
        dec_b = dkjson.decode(body_b)
        t.eq(dec_b.body, "HELLO_WORLD", "chunked body reassembled")

        -- (c) HEAD request on the SAME keep-alive connection + Connection: close
        net.write(c, "HEAD /head-check HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        st_c, _, rest_c, need_c = read_http_resp(c)
        t.eq(st_c, 200, "HEAD 200")
        t.check(need_c > 10, "HEAD advertised non-zero Content-Length")
        t.eq(#rest_c, 0, "HEAD emitted 0 body bytes")
        net.close(c)

        -- Oversized body -> 413
        c413, _ = net.connect_tcp("127.0.0.1", port, 1000)
        net.set_nonblocking(c413, true)
        net.write(c413, "POST /big HTTP/1.1\r\nHost: localhost\r\nContent-Length: 99999\r\n\r\n")
        st_413, _, _, _ = read_http_resp(c413)
        t.eq(st_413, 413, "oversized Content-Length -> 413")
        net.close(c413)

        -- Oversized headers -> 431
        c431, _ = net.connect_tcp("127.0.0.1", port, 1000)
        net.set_nonblocking(c431, true)
        net.write(c431, "GET / HTTP/1.1\r\nHost: localhost\r\nX-Huge: " .. string.rep("A", 1500) .. "\r\n\r\n")
        st_431, _, _, _ = read_http_resp(c431)
        t.eq(st_431, 431, "oversized headers -> 431")
        net.close(c431)

        http_serve.stop(srv)
    end)

    task.run(loop)
    http_serve.close(srv)
    task.close(loop)
end)

-- ---- 3. laws.forall HTTP/1.1 loopback round-trip ----
t.run("laws_http_roundtrip", function()
    req_gen = laws.record({
        seg = laws.text({min_len = 1, max_len = 16, alphabet = "abcdefghijklmnopqrstuvwxyz0123456789-_ "}),
        qval = laws.text({min_len = 0, max_len = 16, alphabet = "abc123 &="}),
        hdr = laws.text({min_len = 1, max_len = 20, alphabet = "ABCDEF0123456789-_"}),
        body = laws.map(laws.list(laws.int(0, 255), {min_len = 0, max_len = 64}), function(xs)
            out = {}
            for i = 1, #xs do
                out[i] = string.char(xs[i])
            end
            return table.concat(out)
        end),
    })

    laws.forall("http_serve loopback preserves decoded path, query, header, and binary body", req_gen, function(case)
        loop = task.new()
        captured = nil
        srv, err = http_serve.open({
            host = "127.0.0.1",
            port = 0,
            once = true,
            loop = loop,
            handler = function(req)
                captured = req
                return {
                    status = 200,
                    headers = {["Content-Type"] = "application/octet-stream"},
                    body = req.body,
                }
            end,
        })
        if srv == nil then
            error(err)
        end
        pnum = http_serve.port(srv)
        enc_seg = http.url_encode(case.seg)
        enc_q = http.build_query({v = case.qval})

        wire_resp = ""
        task.spawn(loop, function()
            c, _ = net.connect_tcp("127.0.0.1", pnum, 1000)
            net.set_nonblocking(c, true)
            wire_req = string.format(
                "POST /%s?%s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nX-Law: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n",
                enc_seg, enc_q, pnum, case.hdr, #case.body
            ) .. case.body
            pos = 1
            while pos <= #wire_req do
                nw, _ = net.write(c, wire_req, pos)
                if nw > 0 then
                    pos = pos + nw
                else
                    task.wait_fd(net.fd(c), "w", 1000)
                end
            end
            parts = {}
            while true do
                ch, eof = net.read(c, 4096)
                if #ch > 0 then
                    table.insert(parts, ch)
                elseif eof then
                    break
                else
                    task.wait_fd(net.fd(c), "r", 1000)
                end
            end
            wire_resp = table.concat(parts)
            net.close(c)
        end)

        task.run(loop)
        http_serve.close(srv)
        task.close(loop)

        sep = string.index_of(wire_resp, "\r\n\r\n")
        if sep == nil or captured == nil then
            return false
        end
        resp_body = string.sub(wire_resp, sep + 4)
        return captured.path == ("/" .. case.seg)
            and captured.query == enc_q
            and captured.headers["x-law"] == case.hdr
            and captured.body == case.body
            and resp_body == case.body
    end, {trials = 50})
    t.check(true, "laws.forall http_serve round-trip passed")
end)

-- ---- 4. Zero-Python `cgi_serve` + httpoxy guard + 256 KB binary CGI + static binary ----
t.run("python_free_cgi_serve_and_static_binary", function()
    t.eq(cgi_serve.is_available(), true, "cgi_serve.is_available() true")

    luam_root = package.luam_root
    if luam_root == nil or luam_root == "" then
        luam_root = lfs.currentdir()
    end
    luam_bin = paths.joinpath(luam_root, "bin", "luam")
    luam_head = git.rev_parse("HEAD", luam_root)

    -- Create an isolated directory with NO python/python3 anywhere on PATH!
    nopy_bin_dir = paths.joinpath(tmp_dir, "nopy_bin")
    paths.ensure_dir(nopy_bin_dir)

    cgi_script = paths.joinpath(tmp_dir, "test_cgi_entry.lua")
    paths.write_file(cgi_script, """
const cgi = require("cgi")
const dkjson = require("dkjson")

path = os.getenv("PATH_INFO")
if path == "/hang" then
    os.sleep(2000)
    cgi.respond({status = "200 OK", body = "late"})
    os.exit(0)
end

len_s = os.getenv("CONTENT_LENGTH")
body = ""
if len_s != nil and tonumber(len_s) != nil and tonumber(len_s) > 0 then
    body = io.read(io.stdin, tonumber(len_s))
end

if path == "/echo-bin" then
    cgi.respond({
        status = "200 OK",
        content_type = "application/octet-stream",
        body = body,
    })
    os.exit(0)
end

cgi.respond({
    status = "200 OK",
    content_type = "application/json",
    headers = {
        cgi.set_cookie_header("c1", "v1", 60, true),
        cgi.set_cookie_header("c2", "v2", 60, false),
    },
    body = dkjson.encode({
        method = os.getenv("REQUEST_METHOD"),
        path = path,
        query = os.getenv("QUERY_STRING"),
        http_proxy = os.getenv("HTTP_PROXY"),
        cookie = os.getenv("HTTP_COOKIE"),
        python_in_path = os.getenv("PATH"),
    }),
})
""")

    -- Run cgi_serve inside a child `luam` whose PATH is ONLY `nopy_bin_dir` (zero python3!)
    port_file = paths.joinpath(tmp_dir, "nopy.port")
    runner_script = paths.joinpath(tmp_dir, "nopy_runner.lua")
    paths.write_file(runner_script, string.format("""
const cgi_serve = require("cgi_serve")
const ext = require("external_tool")
assert(ext.available("python3") == false, "python3 must NOT exist on PATH")
assert(cgi_serve.is_available() == true, "cgi_serve must work without python3")
ok, err = cgi_serve.run({
    script = %q,
    luam_bin = %q,
    host = "127.0.0.1",
    port = 0,
    port_file = %q,
    timeout_ms = 250,
    quiet = true,
})
if not ok then
    io.write(io.stderr, tostring(err) .. "\\n")
    os.exit(1)
end
""", cgi_script, luam_bin, port_file))

    srv_ch, serr = proc.spawn({luam_bin, runner_script}, {
        clear_env = true,
        env = {
            PATH = nopy_bin_dir,
            LUA_PATH = package.path,
            LUA_CPATH = package.cpath,
        },
        new_pgid = true,
    })
    t.eq(serr, nil, "spawned python-free cgi_serve child")

    waited = 0
    while (not paths.file_exists(port_file)) and waited < 150 do
        os.sleep(20)
        waited = waited + 1
    end
    srv_port = tonumber(string.trim(tostring(paths.read_file(port_file))))
    t.check(srv_port != nil and srv_port > 0, "python-free cgi_serve bound port " .. tostring(srv_port))

    base_url = "http://127.0.0.1:" .. tostring(srv_port)

    -- (a) Verify httpoxy (`Proxy:`) header is stripped and multiple cookies/headers work
    r_info, err_info = http.get(base_url .. "/inspect", {
        query = {k = "val"},
        headers = {
            ["Proxy"] = "http://attacker.invalid:8080",
            ["Cookie"] = "a=1; b=2",
        },
        timeout = 5,
    })
    t.eq(err_info, nil, "GET /inspect ok")
    t.eq(r_info.status, 200, "GET /inspect 200")
    t.eq(r_info.json.http_proxy, nil, "Proxy header blocked from becoming HTTP_PROXY (httpoxy guard)")
    t.eq(r_info.json.cookie, "a=1; b=2", "Cookie forwarded")
    t.eq(r_info.json.python_in_path, nopy_bin_dir, "CGI ran under python-free PATH")

    -- (b) 256 KB binary NUL payload streamed through CGI stdin -> stdout without deadlock
    b256 = {}
    for i = 0, 255 do
        b256[i + 1] = string.char(i)
    end
    big_bin = string.rep(table.concat(b256), 1024)
    r_bin, err_bin = http.post(base_url .. "/echo-bin", big_bin, {
        headers = {["Content-Type"] = "application/octet-stream"},
        timeout = 10,
    })
    t.eq(err_bin, nil, "256 KB POST /echo-bin transport ok")
    t.eq(r_bin.status, 200, "256 KB POST /echo-bin status 200")
    t.eq(#r_bin.body, 262144, "256 KB POST /echo-bin exact byte length")
    t.eq(r_bin.body == big_bin, true, "256 KB POST /echo-bin binary content exact")

    -- (c) Hung CGI script killed after timeout_ms=250 -> HTTP 502
    r_hang, _ = http.get(base_url .. "/hang", {timeout = 5})
    t.eq(r_hang.status, 502, "hung CGI script times out cleanly with 502")

    -- Graceful SIGTERM shutdown -> exit code 0!
    proc.kill(srv_ch, "TERM", false)
    w_srv = proc.wait(srv_ch, false)
    err_log, _ = proc.read(srv_ch, "stderr", 4096)
    proc.close(srv_ch)
    t.eq(w_srv.ok, true, "cgi_serve exited 0 on SIGTERM: " .. tostring(err_log))

    -- (d) Standalone `luam build` static binary serving `--once` CGI with empty environment!
    proj_dir = paths.joinpath(tmp_dir, "cgi_static_proj")
    paths.ensure_dir(paths.joinpath(proj_dir, "src"))
    paths.ensure_dir(paths.joinpath(proj_dir, "bld"))

    paths.write_file(paths.joinpath(proj_dir, "bld", "package.lua"), string.format("""
return {
    bin = "self_cgi_app",
    entry = "main.lua",
    luam = %q,
    with = {"lfs", "poll", "net", "proc"},
}
""", luam_head))

    paths.write_file(paths.joinpath(proj_dir, "src", "main.lua"), """
const cgi = require("cgi")
const cgi_serve = require("cgi_serve")

if cgi.is_cgi() then
    cgi.respond({
        status = "200 OK",
        content_type = "text/plain; charset=utf-8",
        body = "SELF_STATIC_CGI:" .. tostring(os.getenv("PATH_INFO")),
    })
    os.exit(0)
end

ok, err = cgi_serve.run({
    bin = arg[1],
    host = "127.0.0.1",
    port = 0,
    port_file = arg[2],
    once = true,
    quiet = true,
})
if not ok then
    io.write(io.stderr, tostring(err) .. "\\n")
    os.exit(1)
end
""")

    clean_env = "env -u LUA_PATH -u LUA_CPATH -u LUAM_DIR "
    _, bld_ok, _ = ext.exec(clean_env .. ext.shell_quote(luam_bin) .. " build -C " .. ext.shell_quote(proj_dir))
    t.eq(bld_ok, true, "built standalone self-serving CGI binary")

    self_bin = paths.joinpath(proj_dir, "bin", "self_cgi_app")
    static_pf = paths.joinpath(tmp_dir, "static_cgi.port")
    st_ch, _ = proc.spawn({self_bin, self_bin, static_pf}, {
        clear_env = true,
        env = {PATH = nopy_bin_dir},
        new_pgid = true,
    })

    waited2 = 0
    while (not paths.file_exists(static_pf)) and waited2 < 150 do
        os.sleep(20)
        waited2 = waited2 + 1
    end
    st_port = tonumber(string.trim(tostring(paths.read_file(static_pf))))
    t.check(st_port != nil and st_port > 0, "standalone CGI binary bound port " .. tostring(st_port))

    r_self, _ = http.get("http://127.0.0.1:" .. tostring(st_port) .. "/hello-static", {timeout = 5})
    t.eq(r_self.status, 200, "standalone self-serving CGI binary returned 200")
    t.eq(r_self.body, "SELF_STATIC_CGI:/hello-static", "standalone self-serving CGI response body")

    w_st = proc.wait(st_ch, false)
    proc.close(st_ch)
    t.eq(w_st.ok, true, "standalone --once CGI server exited 0 after 1 request")
end)

ext.exec("rm -rf " .. ext.shell_quote(tmp_dir))
t.finish("test_http_cgi_serve")
