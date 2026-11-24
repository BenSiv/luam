-- Outbound HTTP client and RFC 3986 URL / query helpers.
-- Uses `proc` (argv-safe, no shell) when available, falling back seamlessly
-- to `external_tool` so static binaries work with or without `with = {"proc"}`.

const dkjson = require("dkjson")
const ext = require("external_tool")
const paths = require("paths")

has_proc, proc_mod = pcall(require, "proc")
USE_PROC = (has_proc == true and type(proc_mod) == "table" and type(proc_mod.exec) == "function")

const http = {}

function has_ctl_chars(s)
    return string.find(s, "[\r\n%z]") != nil
end

function sorted_string_keys(tbl)
    keys = {}
    for k, _ in pairs(tbl) do
        table.insert(keys, tostring(k))
    end
    table.sort(keys)
    return keys
end

-- RFC 3986 percent-encoding (unreserved: A-Z a-z 0-9 - _ . ~; spaces -> %20).
function http.url_encode(str)
    if str == nil then
        return ""
    end
    s = tostring(str)
    return (string.gsub(s, "([^%w%-_%.~])", function(ch)
        return string.format("%%%02X", string.byte(ch, 1))
    end))
end

-- Percent-decoding; converts `+` to space when `plus_as_space == true`.
function http.url_decode(str, plus_as_space)
    if str == nil then
        return ""
    end
    s = tostring(str)
    if plus_as_space == true then
        s = string.gsub(s, "+", " ")
    end
    return (string.gsub(s, "%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

-- Deterministically builds a query string from `{k = v}` (supports array values).
function http.build_query(params)
    if params == nil or type(params) != "table" then
        return ""
    end
    key_map = {}
    keys = {}
    for k, v in pairs(params) do
        if v != nil then
            ks = tostring(k)
            key_map[ks] = v
            table.insert(keys, ks)
        end
    end
    table.sort(keys)

    parts = {}
    for _, ks in ipairs(keys) do
        val = key_map[ks]
        enc_k = http.url_encode(ks)
        if type(val) == "table" then
            for _, item in ipairs(val) do
                if item != nil then
                    table.insert(parts, enc_k .. "=" .. http.url_encode(tostring(item)))
                end
            end
        else
            table.insert(parts, enc_k .. "=" .. http.url_encode(tostring(val)))
        end
    end
    return table.concat(parts, "&")
end

function append_query(url, query_tbl)
    q = http.build_query(query_tbl)
    if q == "" then
        return url
    end
    if string.contains(url, "?") then
        if string.ends_with(url, "?") or string.ends_with(url, "&") then
            return url .. q
        end
        return url .. "&" .. q
    end
    return url .. "?" .. q
end

-- Parses the final HTTP header block from a `-D` dump file (handling 100 Continue / 3xx redirects).
function parse_header_dump(raw_dump)
    lower_map = {}
    raw_lines = {}
    if raw_dump == nil or raw_dump == "" then
        return lower_map, raw_lines
    end

    normalized = string.gsub(raw_dump, "\r\n", "\n")
    blocks = {}
    current = {}
    for _, line in ipairs(string.split(normalized, "\n")) do
        if line == "" then
            if #current > 0 then
                table.insert(blocks, current)
                current = {}
            end
        else
            table.insert(current, line)
        end
    end
    if #current > 0 then
        table.insert(blocks, current)
    end

    last_http_block = nil
    for _, blk in ipairs(blocks) do
        if #blk > 0 and string.starts_with(blk[1], "HTTP/") then
            last_http_block = blk
        end
    end
    if last_http_block == nil then
        return lower_map, raw_lines
    end

    for idx = 2, #last_http_block do
        hline = last_http_block[idx]
        table.insert(raw_lines, hline)
        colon = string.index_of(hline, ":")
        if colon != nil and colon > 1 then
            hname = string.lower(string.trim(string.sub(hline, 1, colon - 1)))
            hval = string.trim(string.sub(hline, colon + 1))
            if lower_map[hname] != nil then
                lower_map[hname] = lower_map[hname] .. ", " .. hval
            else
                lower_map[hname] = hval
            end
        end
    end
    return lower_map, raw_lines
end

function normalize_headers_list(headers_opt, has_json)
    list = {}
    has_content_type = false
    if headers_opt != nil then
        if type(headers_opt) != "table" then
            return nil, "opts.headers must be a table"
        end
        -- Handle both array of "Name: Value" strings and map of {Name = Value}
        for k, v in pairs(headers_opt) do
            if type(k) == "number" then
                line = tostring(v)
                if has_ctl_chars(line) then
                    return nil, "invalid CR/LF/NUL in HTTP header"
                end
                if string.starts_with(string.lower(line), "content-type:") then
                    has_content_type = true
                end
                table.insert(list, line)
            else
                ks = tostring(k)
                vs = tostring(v)
                if has_ctl_chars(ks) or has_ctl_chars(vs) or string.contains(ks, ":") then
                    return nil, "invalid HTTP header name or value"
                end
                if string.lower(ks) == "content-type" then
                    has_content_type = true
                end
                table.insert(list, ks .. ": " .. vs)
            end
        end
    end
    table.sort(list)
    if has_json and (not has_content_type) then
        table.insert(list, 1, "Content-Type: application/json")
    end
    return list, nil
end

function execute_curl(argv, body_bytes, timeout_sec)
    if USE_PROC then
        proc_opts = {
            timeout_ms = math.floor((timeout_sec + 5) * 1000),
        }
        if body_bytes != nil then
            proc_opts.stdin = body_bytes
        end
        res, spawn_err = proc_mod.exec(argv, proc_opts)
        if res == nil then
            return false, "", tostring(spawn_err)
        end
        return res.ok, res.stdout, res.stderr
    end

    -- Fallback to external_tool when proc.so is not linked
    body_tmp = nil
    final_parts = {}
    for _, tok in ipairs(argv) do
        if tok == "@-" and body_bytes != nil then
            body_tmp = os.tmpname()
            ok_w, err_w = paths.write_file(body_tmp, body_bytes)
            if not ok_w then
                os.remove(body_tmp)
                return false, "", tostring(err_w)
            end
            table.insert(final_parts, ext.shell_quote("@" .. body_tmp))
        else
            table.insert(final_parts, ext.shell_quote(tok))
        end
    end

    out, ok_exec, _ = ext.exec(table.concat(final_parts, " "))
    if body_tmp != nil then
        os.remove(body_tmp)
    end
    return ok_exec, out, out
end

-- Executes an HTTP request via curl.
-- Returns `resp, nil` or `nil, err_string`.
function http.request(opts)
    if type(opts) != "table" then
        return nil, "http.request expects an options table"
    end
    raw_url = opts.url
    if type(raw_url) != "string" or raw_url == "" then
        return nil, "opts.url must be a non-empty string"
    end
    if has_ctl_chars(raw_url) then
        return nil, "invalid CR/LF/NUL in URL"
    end

    full_url = append_query(raw_url, opts.query)
    method = "GET"
    if opts.method != nil and opts.method != "" then
        method = string.upper(tostring(opts.method))
    elseif opts.body != nil or opts.json != nil then
        method = "POST"
    end
    if has_ctl_chars(method) or string.match(method, "^[%u]+$") == nil then
        return nil, "invalid HTTP method"
    end

    body_bytes = opts.body
    has_json = (opts.json != nil)
    if has_json then
        encoded_json = dkjson.encode(opts.json)
        if type(encoded_json) != "string" then
            return nil, "failed to encode opts.json"
        end
        body_bytes = encoded_json
    elseif body_bytes != nil then
        body_bytes = tostring(body_bytes)
    end

    hdr_list, hdr_err = normalize_headers_list(opts.headers, has_json)
    if hdr_list == nil then
        return nil, hdr_err
    end

    timeout_sec = 30
    if opts.timeout != nil then
        tnum = tonumber(opts.timeout)
        if tnum == nil or tnum <= 0 then
            return nil, "opts.timeout must be a positive number"
        end
        timeout_sec = tnum
    end

    hdr_tmp = os.tmpname()
    out_tmp = os.tmpname()
    if opts.output_path != nil and opts.output_path != "" then
        -- Still download to temp first; caller moves atomically on 2xx
    end

    argv = {
        "curl",
        "-sS",
        "--globoff",
        "--max-time", tostring(timeout_sec),
        "-X", method,
        "-D", hdr_tmp,
        "-o", out_tmp,
        "-w", "%{http_code}",
    }

    if opts.follow_redirects == true then
        table.insert(argv, "-L")
        if opts.max_redirects != nil and tonumber(opts.max_redirects) != nil then
            table.insert(argv, "--max-redirs")
            table.insert(argv, tostring(math.floor(tonumber(opts.max_redirects))))
        end
    end

    if opts.insecure == true then
        table.insert(argv, "-k")
    end

    for _, hline in ipairs(hdr_list) do
        table.insert(argv, "-H")
        table.insert(argv, hline)
    end

    if body_bytes != nil then
        table.insert(argv, "--data-binary")
        table.insert(argv, "@-")
    end

    table.insert(argv, "--")
    table.insert(argv, full_url)

    ok_curl, stdout_str, stderr_str = execute_curl(argv, body_bytes, timeout_sec)
    if not ok_curl then
        os.remove(hdr_tmp)
        os.remove(out_tmp)
        detail = string.trim(tostring(stderr_str))
        if detail == "" then
            detail = "curl request failed"
        end
        return nil, detail
    end

    raw_hdr = paths.read_file(hdr_tmp)
    resp_body = paths.read_file(out_tmp)
    os.remove(hdr_tmp)
    os.remove(out_tmp)

    if resp_body == nil then
        resp_body = ""
    end

    code_str = string.match(string.trim(tostring(stdout_str)), "(%d%d%d)$")
    status_num = nil
    if code_str != nil then
        status_num = tonumber(code_str)
    end
    if status_num == nil or status_num == 0 then
        return nil, "invalid or empty HTTP status from curl"
    end

    parsed_headers, raw_header_lines = parse_header_dump(raw_hdr)

    decoded_json = nil
    ct = parsed_headers["content-type"]
    if ct != nil and string.contains(string.lower(ct), "application/json") and resp_body != "" then
        val, _, jerr = dkjson.decode(resp_body)
        if jerr == nil then
            decoded_json = val
        end
    end

    resp = {
        ok = (status_num >= 200 and status_num < 300),
        status = status_num,
        headers = parsed_headers,
        raw_headers = raw_header_lines,
        body = resp_body,
        json = decoded_json,
    }
    return resp, nil
end

function shallow_merge_opts(opts)
    merged = {}
    if opts != nil and type(opts) == "table" then
        for k, v in pairs(opts) do
            merged[k] = v
        end
    end
    return merged
end

function http.get(url, opts)
    req = shallow_merge_opts(opts)
    req.method = "GET"
    req.url = url
    return http.request(req)
end

function http.post(url, body, opts)
    req = shallow_merge_opts(opts)
    req.method = "POST"
    req.url = url
    req.body = body
    return http.request(req)
end

function http.post_json(url, payload_tbl, opts)
    req = shallow_merge_opts(opts)
    req.method = "POST"
    req.url = url
    req.json = payload_tbl
    return http.request(req)
end

-- Downloads `url` and writes it atomically to `dest_path` only on HTTP 2xx.
function http.download(url, dest_path, opts)
    if type(dest_path) != "string" or dest_path == "" then
        return false, "dest_path must be a non-empty string"
    end
    req = shallow_merge_opts(opts)
    if req.follow_redirects == nil then
        req.follow_redirects = true
    end
    req.method = "GET"
    req.url = url

    resp, err = http.request(req)
    if resp == nil then
        return false, err
    end
    if not resp.ok then
        return false, "HTTP " .. tostring(resp.status)
    end

    ok_w, err_w = paths.write_atomic(dest_path, resp.body)
    if not ok_w then
        return false, err_w
    end
    return true, resp.status
end

return http
