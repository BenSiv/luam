-- Core standard library additions test suite:
--   1. `os.clock_ms()`, `os.time_ms()`, and `os.sleep(ms)`
--   2. `crypto.hex_encode` / `crypto.hex_decode` (+ `laws` binary round-trip)
--   3. `base64` RFC 4648 standard & URL-safe (+ `laws` binary round-trips)
--   4. `proc.exec` & `proc.run` (argv shell-injection immunity, 256 KB pipe
--      multiplexing with NUL bytes, stdout/stderr split & merge, cwd, env,
--      clear_env, non-zero exit, signals, timeout_ms, missing binary err)
--   5. `dates` civil calendar & ISO-8601 / RFC 3339 (+ `laws` round-trips)
--   6. `http` + `cgi_serve` live loopback HTTP/JSON/query/header/download suite

const base64 = require("base64")
const cgi_serve = require("cgi_serve")
const crypto = require("crypto")
const dates = require("dates")
const dkjson = require("dkjson")
const ext = require("external_tool")
const http = require("http")
const laws = require("laws")
const lfs = require("lfs")
const paths = require("paths")
const proc = require("proc")
const t = require("test")

-- ---- 1. High-resolution clocks & sleep ----
c0 = os.clock_ms()
w0 = os.time_ms()
t.check(type(c0) == "number" and c0 >= 0, "os.clock_ms returns non-negative number")
t.check(type(w0) == "number" and w0 > 1700000000000, "os.time_ms returns epoch milliseconds")
t.eq(os.sleep(0), true, "os.sleep(0) returns true immediately")
t.eq(os.sleep(-5), true, "os.sleep(-5) returns true immediately")
t.eq(os.sleep(25), true, "os.sleep(25) returns true")
c1 = os.clock_ms()
t.check((c1 - c0) >= 18.0, "os.clock_ms advanced across 25ms sleep: " .. tostring(c1 - c0))

-- ---- 2. crypto.hex_encode / crypto.hex_decode ----
t.eq(crypto.hex_encode(""), "", "hex_encode empty")
t.eq(crypto.hex_encode("Luam\x00\xff"), "4c75616d00ff", "hex_encode binary")
t.eq(crypto.hex_decode(""), "", "hex_decode empty")
t.eq(crypto.hex_decode("4C75616d00FF"), "Luam\x00\xff", "hex_decode mixed case")

bad_odd, err_odd = crypto.hex_decode("abc")
t.eq(bad_odd, nil, "hex_decode rejects odd length")
t.check(string.contains(tostring(err_odd), "even"), "hex_decode odd error message")

bad_chr, err_chr = crypto.hex_decode("4g")
t.eq(bad_chr, nil, "hex_decode rejects non-hex")
t.check(string.contains(tostring(err_chr), "hex"), "hex_decode non-hex error message")

bin_gen = laws.map(laws.list(laws.int(0, 255), {min_len = 0, max_len = 128}), function(arr)
    chars = {}
    for i = 1, #arr do
        chars[i] = string.char(arr[i])
    end
    return table.concat(chars)
end)

laws.forall("crypto.hex_encode/decode", bin_gen, function(raw)
    val, err = crypto.hex_decode(crypto.hex_encode(raw))
    return err == nil and val == raw
end, {trials = 120})
t.check(true, "laws crypto.hex_encode/decode passed")

-- ---- 3. base64 (RFC 4648 standard & URL-safe) ----
const RFC4648_VECTORS = {
    {"", ""},
    {"f", "Zg=="},
    {"fo", "Zm8="},
    {"foo", "Zm9v"},
    {"foob", "Zm9vYg=="},
    {"fooba", "Zm9vYmE="},
    {"foobar", "Zm9vYmFy"},
}
for _, vec_pair in ipairs(RFC4648_VECTORS) do
    raw_in = vec_pair[1]
    exp_b64 = vec_pair[2]
    t.eq(base64.encode(raw_in), exp_b64, "base64.encode RFC vector: " .. raw_in)
    dec_out, dec_err = base64.decode(exp_b64)
    t.eq(dec_err, nil, "base64.decode err nil")
    t.eq(dec_out, raw_in, "base64.decode RFC vector: " .. exp_b64)
end

-- Bytes 0xfb, 0xff, 0xfe produce `+` and `/` in standard Base64 and `-` and `_` in base64url
url_sample = "\xfb\xff\xfe\xff"
t.eq(base64.encode(url_sample), "+//+/w==", "standard base64 uses + and /")
t.eq(base64.encode_url(url_sample), "-__-_w", "base64.encode_url unpadded by default")
t.eq(base64.encode_url(url_sample, false), "-__-_w==", "base64.encode_url padded when no_padding=false")
u_dec1, _ = base64.decode_url("-__-_w")
u_dec2, _ = base64.decode_url("-__-_w==")
t.eq(u_dec1, url_sample, "base64.decode_url unpadded")
t.eq(u_dec2, url_sample, "base64.decode_url padded")

ws_dec, _ = base64.decode("Zm9v\r\n YmFy\t", {ignore_whitespace = true})
t.eq(ws_dec, "foobar", "base64.decode ignore_whitespace")

inv_b64, _ = base64.decode("abc")
t.eq(inv_b64, nil, "base64.decode rejects invalid length")
inv_pad, _ = base64.decode("=m9v")
t.eq(inv_pad, nil, "base64.decode rejects leading =")
inv_url, _ = base64.decode_url("a")
t.eq(inv_url, nil, "base64.decode_url rejects mod-4 == 1")

laws.forall("base64.encode/decode", bin_gen, function(raw)
    v, err = base64.decode(base64.encode(raw))
    return err == nil and v == raw
end, {trials = 120})
laws.forall("base64.encode_url/decode_url", bin_gen, function(raw)
    v, err = base64.decode_url(base64.encode_url(raw))
    return err == nil and v == raw
end, {trials = 120})
t.check(true, "laws base64 round-trips passed")

-- ---- 4. proc.exec & proc.run ----
-- (a) Shell metacharacter immunity (no /bin/sh interpretation)
dangerous_arg = "; echo PWNED; $HOME `uname` 'single' \"double\"\nline2"
r_meta, err_meta = proc.exec({"printf", "%s", dangerous_arg})
t.eq(err_meta, nil, "proc.exec printf error nil")
t.eq(r_meta.ok, true, "proc.exec printf ok")
t.eq(r_meta.stdout, dangerous_arg, "proc.exec preserves shell metacharacters verbatim")
t.eq(r_meta.stderr, "", "proc.exec empty stderr")

-- (b) 256 KB binary payload with NUL bytes over stdin -> cat -> stdout (non-blocking poll)
chunk_256 = {}
for i = 0, 255 do
    chunk_256[i + 1] = string.char(i)
end
big_payload = string.rep(table.concat(chunk_256), 1024)
t.eq(#big_payload, 262144, "256 KB payload size")
r_cat, _ = proc.exec({"cat"}, {stdin = big_payload})
t.eq(r_cat.ok, true, "proc.exec 256 KB cat ok")
t.eq(#r_cat.stdout, 262144, "proc.exec 256 KB stdout length")
t.eq(r_cat.stdout == big_payload, true, "proc.exec 256 KB binary NUL round-trip exact")

-- (c) Separate stdout/stderr vs merge_stderr
r_split, _ = proc.exec({"sh", "-c", "printf 'OUT_PART'; printf 'ERR_PART' >&2; exit 7"})
t.eq(r_split.ok, false, "non-zero exit ok=false")
t.eq(r_split.why, "exit", "non-zero exit why='exit'")
t.eq(r_split.code, 7, "non-zero exit code=7")
t.eq(r_split.stdout, "OUT_PART", "separate stdout")
t.eq(r_split.stderr, "ERR_PART", "separate stderr")

r_merged, _ = proc.exec({"sh", "-c", "printf 'A'; printf 'B' >&2"}, {merge_stderr = true})
t.eq(r_merged.ok, true, "merge_stderr ok")
t.eq(r_merged.stdout, "AB", "merge_stderr combined stdout")
t.eq(r_merged.stderr, "", "merge_stderr empty stderr")

-- (d) cwd, env, clear_env
tmp_dir = os.tmpname()
os.remove(tmp_dir)
paths.ensure_dir(tmp_dir)

r_env, _ = proc.exec({"sh", "-c", "pwd; printf '|%s|%s' \"$CUSTOM_VAR\" \"$PATH\""}, {
    cwd = tmp_dir,
    env = {CUSTOM_VAR = "hello_proc", PATH = "/bin:/usr/bin"},
    clear_env = true,
})
t.eq(r_env.ok, true, "proc.exec cwd + clear_env ok")
t.check(string.ends_with(r_env.stdout, tmp_dir .. "\n|hello_proc|/bin:/usr/bin"), "proc.exec cwd and clean env applied: " .. tostring(r_env.stdout))

-- (e) Signal & timeout_ms
r_sig, _ = proc.exec({"sh", "-c", "kill -9 $$"})
t.eq(r_sig.ok, false, "killed process ok=false")
t.eq(r_sig.why, "signal", "killed process why='signal'")
t.eq(r_sig.code, 9, "killed process code=9")

t_start = os.clock_ms()
r_to, _ = proc.exec({"sleep", "10"}, {timeout_ms = 80})
t_elapsed = os.clock_ms() - t_start
t.eq(r_to.ok, false, "timed-out process ok=false")
t.eq(r_to.why, "timeout", "timed-out process why='timeout'")
t.eq(r_to.code, -1, "timed-out process code=-1")
t.check(t_elapsed < 3000.0, "timeout killed sleep promptly in " .. tostring(t_elapsed) .. "ms")

-- (f) Missing executable & bad chdir surface (nil, err) via FD_CLOEXEC pipe
r_missing, err_missing = proc.exec({"definitely_nonexistent_exec_xyz_999"})
t.eq(r_missing, nil, "missing executable returns nil")
t.check(err_missing != nil and #err_missing > 0, "missing executable returns descriptive error: " .. tostring(err_missing))

r_badcwd, err_badcwd = proc.exec({"true"}, {cwd = paths.joinpath(tmp_dir, "no_such_dir")})
t.eq(r_badcwd, nil, "nonexistent cwd returns nil")
t.check(string.contains(tostring(err_badcwd), "chdir"), "nonexistent cwd reports chdir failure")

run_ok, run_why, run_code = proc.run({"sh", "-c", "exit 5"})
t.eq(run_ok, false, "proc.run exit 5 ok=false")
t.eq(run_why, "exit", "proc.run exit 5 why='exit'")
t.eq(run_code, 5, "proc.run exit 5 code=5")

-- ---- 5. dates (civil calendar + ISO-8601 + laws) ----
t.eq(dates.civil_days("1970-01-01"), 0, "epoch day 0")
t.eq(dates.civil_days("1969-12-31"), -1, "day -1")
t.eq(dates.civil_days("2000-02-29"), 11016, "2000 leap day valid")
t.eq(dates.civil_days("1900-02-29"), nil, "1900 non-leap Feb 29 rejected")
t.eq(dates.civil_days("2025-02-29"), nil, "2025 non-leap Feb 29 rejected")
t.eq(dates.add_days("2024-02-28", 1), "2024-02-29", "add_days across leap day")
t.eq(dates.diff_days("2024-03-01", "2024-02-28"), 2, "diff_days across 2024 leap year")

t.eq(dates.format_iso8601(0), "1970-01-01T00:00:00Z", "format_iso8601 epoch 0")
ts_parsed, ts_parts = dates.parse_iso8601("2026-11-24T07:30:00+02:00")
t.eq(ts_parsed, dates.parse_iso8601("2026-11-24T05:30:00Z"), "parse_iso8601 +02:00 matches UTC")
t.eq(ts_parts.offset_sec, 7200, "parse_iso8601 offset_sec=7200")

laws.forall("dates.ymd_from_days/civil_days", laws.int(-300000, 300000), function(d)
    return dates.civil_days(dates.ymd_from_days(d)) == d
end, {trials = 150})
laws.forall("dates.format_iso8601/parse_iso8601", laws.int(-2000000000, 4000000000), function(ts)
    sec, _ = dates.parse_iso8601(dates.format_iso8601(ts))
    return sec == ts
end, {trials = 150})
t.check(true, "laws dates civil & ISO-8601 round-trips passed")

-- ---- 6. http + cgi_serve live loopback integration ----
t.eq(http.url_encode("a b+c&d=1~2"), "a%20b%2Bc%26d%3D1~2", "http.url_encode RFC 3986")
t.eq(http.url_decode("a%20b+c%21", false), "a b+c!", "http.url_decode raw +")
t.eq(http.url_decode("a%20b+c%21", true), "a b c!", "http.url_decode form +")
t.eq(http.build_query({z = "last", a = "first value", tag = {"x", "y"}}), "a=first%20value&tag=x&tag=y&z=last", "http.build_query deterministic")

if cgi_serve.is_available() and ext.available("curl") then
    cgi_app_script = paths.joinpath(tmp_dir, "app_cgi.lua")
    paths.write_file(cgi_app_script, """
const cgi = require("cgi")
const dkjson = require("dkjson")

method = os.getenv("REQUEST_METHOD")
path = os.getenv("PATH_INFO")
query = cgi.parse_query(os.getenv("QUERY_STRING"))
custom_hdr = os.getenv("HTTP_X_CUSTOM_TOKEN")
len_s = os.getenv("CONTENT_LENGTH")
req_body = ""
if len_s != nil and tonumber(len_s) != nil and tonumber(len_s) > 0 then
    req_body = io.read(io.stdin, tonumber(len_s))
end

if path == "/blob" then
    cgi.respond({
        status = "200 OK",
        content_type = "application/octet-stream",
        body = "BIN\x00PAYLOAD\xffEND",
    })
    os.exit(0)
end

payload = {
    method = method,
    path = path,
    q = query["q"],
    token = custom_hdr,
    echo = nil,
}
if req_body != "" then
    decoded = dkjson.decode(req_body)
    payload.echo = decoded
end

cgi.respond({
    status = "201 Created",
    content_type = "application/json",
    headers = {
        ["X-Server-Tag"] = "luam-cgi",
        cgi.set_cookie_header("sid", "xyz123", 60, true),
    },
    body = dkjson.encode(payload),
})
""")

    port_file = paths.joinpath(tmp_dir, "cgi.port")
    srv_runner = paths.joinpath(tmp_dir, "run_srv.lua")
    paths.write_file(srv_runner, string.format("""
const cgi_serve = require("cgi_serve")
-- Serve 2 requests cleanly by running two --once cycles? No, serve_forever and let parent kill pid!
cgi_serve.run({
    script = %q,
    host = "127.0.0.1",
    port = 0,
    port_file = %q,
    quiet = true,
})
""", cgi_app_script, port_file))

    luam_bin = paths.joinpath(lfs.currentdir(), "bin", "luam")
    if not paths.file_exists(luam_bin) and package.exec_dir != nil then
        luam_bin = paths.joinpath(package.exec_dir, "luam")
    end
    pid_file = paths.joinpath(tmp_dir, "srv.pid")
    bg_cmd = string.format(
        "LUA_PATH=%s LUA_CPATH=%s %s %s >/dev/null 2>&1 & echo $! > %s",
        ext.shell_quote(package.path),
        ext.shell_quote(package.cpath),
        ext.shell_quote(luam_bin),
        ext.shell_quote(srv_runner),
        ext.shell_quote(pid_file)
    )
    ext.must(bg_cmd, "launch background cgi_serve")
    srv_pid = string.trim(tostring(paths.read_file(pid_file)))

    -- Wait up to 3 seconds for port_file
    waited = 0
    while (not paths.file_exists(port_file)) and waited < 150 do
        os.sleep(20)
        waited = waited + 1
    end

    srv_port_str = paths.read_file(port_file)
    srv_port = nil
    if srv_port_str != nil then
        srv_port = tonumber(string.trim(srv_port_str))
    end
    t.check(srv_port != nil and srv_port > 0, "cgi_serve bound ephemeral port: " .. tostring(srv_port))

    if srv_port != nil and srv_port > 0 then
        base_url = "http://127.0.0.1:" .. tostring(srv_port)
        resp, herr = http.post_json(base_url .. "/api/items", {count = 42, items = {"a", "b"}}, {
            query = {q = "hello world"},
            headers = {["X-Custom-Token"] = "sec_777"},
            timeout = 5,
        })
        t.eq(herr, nil, "http.post_json error nil")
        t.check(resp != nil and resp.ok == true, "http.post_json 2xx ok")
        if resp != nil then
            t.eq(resp.status, 201, "http.post_json status 201")
            t.eq(resp.headers["x-server-tag"], "luam-cgi", "response custom header parsed")
            t.check(string.contains(tostring(resp.headers["set-cookie"]), "sid=xyz123"), "response cookie header parsed")
            t.check(resp.json != nil, "response JSON auto-decoded")
            if resp.json != nil then
                t.eq(resp.json.method, "POST", "CGI received POST")
                t.eq(resp.json.path, "/api/items", "CGI received PATH_INFO")
                t.eq(resp.json.q, "hello world", "CGI received decoded query param")
                t.eq(resp.json.token, "sec_777", "CGI received HTTP_X_CUSTOM_TOKEN")
                t.eq(resp.json.echo.count, 42, "CGI echoed JSON body")
            end
        end

        dl_dest = paths.joinpath(tmp_dir, "downloaded.bin")
        dl_ok, dl_status = http.download(base_url .. "/blob", dl_dest, {timeout = 5})
        t.eq(dl_ok, true, "http.download binary succeeded")
        t.eq(dl_status, 200, "http.download status 200")
        t.eq(paths.read_file(dl_dest), "BIN\x00PAYLOAD\xffEND", "http.download preserved NUL and 0xFF bytes atomically")
    end

    if srv_pid != "" then
        os.execute("kill " .. ext.shell_quote(srv_pid) .. " >/dev/null 2>&1 || true")
    end
end

ext.must("rm -rf " .. ext.shell_quote(tmp_dir), "cleanup tmp_dir")
t.finish("test_stdlib_core.lua")
