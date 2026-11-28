-- Local HTTP-to-CGI development & integration-test server.
--
-- Pure-Luam implementation over `lib/http_serve` and `lib/proc` (zero Python
-- runtime dependency). Dispatches HTTP requests to either a compiled Luam CGI
-- binary (`opts.bin`) or an interpreted Luam CGI entry script (`opts.script`),
-- forwarding standard RFC 3875 CGI environment variables and `HTTP_*` headers.

const http_serve = require("http_serve")
const lfs = require("lfs")
const paths = require("paths")
const task = require("task")

has_proc, proc_mod = pcall(require, "proc")

const cgi_serve = {}

function default_val(val, fallback)
    if val == nil then
        return fallback
    end
    return val
end

function default_luam_bin()
    if package.exec_dir != nil and package.exec_dir != "" then
        cand = paths.joinpath(package.exec_dir, "luam")
        if paths.file_exists(cand) then
            return cand
        end
    end
    if arg != nil and arg[-1] != nil and arg[-1] != "" then
        return arg[-1]
    end
    return "luam"
end

function cgi_serve.is_available()
    return http_serve.is_available() and has_proc == true and type(proc_mod) == "table" and type(proc_mod.spawn) == "function"
end

function parse_cgi_output(raw, req_method)
    sep_start = string.index_of(raw, "\r\n\r\n")
    sep_after = nil
    if sep_start != nil then
        sep_after = sep_start + 4
    else
        sep_start = string.index_of(raw, "\n\n")
        if sep_start != nil then
            sep_after = sep_start + 2
        end
    end

    if sep_start == nil then
        return {
            status = 500,
            headers = {["Content-Type"] = "text/plain; charset=utf-8"},
            body = "Invalid CGI response",
        }
    end

    hdr_block = string.gsub(string.sub(raw, 1, sep_start - 1), "\r\n", "\n")
    payload = string.sub(raw, sep_after)

    status_code = 200
    reason = "OK"
    out_headers = {}
    has_len = false

    for _, line in ipairs(string.split(hdr_block, "\n")) do
        colon = string.index_of(line, ":")
        if colon != nil and colon > 1 then
            k = string.trim(string.sub(line, 1, colon - 1))
            v = string.trim(string.sub(line, colon + 1))
            if string.lower(k) == "status" then
                c_str, m_str = string.match(v, "^(%d%d%d)%s*(.*)$")
                if c_str != nil then
                    status_code = tonumber(c_str)
                    reason = default_val(m_str, "")
                end
            else
                if string.lower(k) == "content-length" then
                    has_len = true
                end
                table.insert(out_headers, {k, v})
            end
        end
    end

    if not has_len then
        table.insert(out_headers, {"Content-Length", tostring(#payload)})
    end

    out_body = payload
    if req_method == "HEAD" then
        out_body = ""
    end

    return {
        status = status_code,
        reason = reason,
        headers = out_headers,
        body = out_body,
    }
end

function build_cgi_env(base_env, root, req)
    env = {}
    for k, v in pairs(base_env) do
        env[k] = v
    end

    env["GATEWAY_INTERFACE"] = "CGI/1.1"
    env["SERVER_PROTOCOL"] = default_val(req.version, "HTTP/1.1")
    env["DOCUMENT_ROOT"] = root
    env["REQUEST_METHOD"] = req.method
    env["PATH_INFO"] = req.path
    env["QUERY_STRING"] = req.query
    env["SERVER_NAME"] = tostring(default_val(req.server_host, "127.0.0.1"))
    env["SERVER_PORT"] = tostring(default_val(req.server_port, 80))
    env["REMOTE_ADDR"] = tostring(default_val(req.remote_addr, "127.0.0.1"))

    -- Clear per-request vars so parent process environment cannot bleed through
    env["CONTENT_TYPE"] = ""
    env["CONTENT_LENGTH"] = ""
    env["HTTP_COOKIE"] = ""

    for _, hdr in ipairs(req.raw_headers) do
        low = string.lower(hdr.name)
        if low == "content-type" then
            env["CONTENT_TYPE"] = hdr.value
        elseif low == "content-length" then
            env["CONTENT_LENGTH"] = hdr.value
        elseif low != "proxy" then
            -- Never map incoming `Proxy:` to `HTTP_PROXY` (RFC 3875 httpoxy mitigation).
            env_key = "HTTP_" .. string.upper((string.gsub(hdr.name, "%-", "_")))
            if env[env_key] != nil and env[env_key] != "" then
                if low == "cookie" then
                    env[env_key] = env[env_key] .. "; " .. hdr.value
                else
                    env[env_key] = env[env_key] .. ", " .. hdr.value
                end
            else
                env[env_key] = hdr.value
            end
        end
    end

    if (env["CONTENT_LENGTH"] == nil or env["CONTENT_LENGTH"] == "") and #req.body > 0 then
        env["CONTENT_LENGTH"] = tostring(#req.body)
    end

    return env
end

function execute_cgi_async(cmd_argv, root, cgi_env, body_bytes, quiet, loop, timeout_ms)
    has_stdin = (#body_bytes > 0)
    child, serr = proc_mod.spawn(cmd_argv, {
        cwd = root,
        env = cgi_env,
        stdin_pipe = has_stdin,
        stdout_pipe = true,
        stderr_pipe = true,
        new_pgid = true,
    })
    if child == nil then
        return nil, serr
    end

    deadline_ms = os.clock_ms() + timeout_ms

    if has_stdin then
        task.spawn(loop, function()
            pos = 1
            total = #body_bytes
            in_fd = proc_mod.stdin_fd(child)
            while pos <= total and in_fd != nil do
                nw, werr = proc_mod.write(child, body_bytes, pos)
                if nw == nil then
                    break
                end
                if nw > 0 then
                    pos = pos + nw
                else
                    rem = math.ceil(deadline_ms - os.clock_ms())
                    if rem <= 0 then
                        break
                    end
                    ev, _ = task.wait_fd(in_fd, "w", rem)
                    if ev == nil then
                        break
                    end
                end
            end
            proc_mod.close_stdin(child)
        end)
    end

    task.spawn(loop, function()
        err_fd = proc_mod.stderr_fd(child)
        while err_fd != nil do
            echunk, eeof = proc_mod.read(child, "stderr", 8192)
            if echunk == nil then
                break
            end
            if #echunk > 0 and not quiet then
                io.write(io.stderr, echunk)
            end
            if eeof then
                break
            end
            if #echunk == 0 then
                rem = math.ceil(deadline_ms - os.clock_ms())
                if rem <= 0 then
                    break
                end
                ev, _ = task.wait_fd(err_fd, "r", rem)
                if ev == nil then
                    break
                end
            end
        end
    end)

    out_parts = {}
    out_fd = proc_mod.stdout_fd(child)
    timed_out = false
    while out_fd != nil do
        chunk, eof = proc_mod.read(child, "stdout", 16384)
        if chunk == nil then
            break
        end
        if #chunk > 0 then
            table.insert(out_parts, chunk)
        end
        if eof then
            break
        end
        if #chunk == 0 then
            rem = math.ceil(deadline_ms - os.clock_ms())
            if rem <= 0 then
                timed_out = true
                break
            end
            ev, why = task.wait_fd(out_fd, "r", rem)
            if ev == nil and why == "timeout" then
                timed_out = true
                break
            end
        end
    end

    if timed_out then
        proc_mod.kill(child, "KILL", true)
        proc_mod.wait(child, false)
        proc_mod.close(child)
        return nil, "CGI process timed out"
    end

    -- Reap child non-blockingly with short poll backoff
    while true do
        st = proc_mod.wait(child, true)
        if st == nil or st.done == true then
            break
        end
        if os.clock_ms() >= deadline_ms then
            proc_mod.kill(child, "KILL", true)
            proc_mod.wait(child, false)
            break
        end
        task.sleep_ms(2)
    end
    proc_mod.close(child)
    return table.concat(out_parts), nil
end

-- Builds a reusable `http_serve` handler `(req, loop) -> resp` and resolved server config.
function cgi_serve.make_handler(opts)
    if type(opts) != "table" then
        return nil, nil, "cgi_serve expects an options table"
    end
    if not cgi_serve.is_available() then
        return nil, nil, "net, poll, and proc modules are required for cgi_serve"
    end

    has_bin = (type(opts.bin) == "string" and opts.bin != "")
    has_script = (type(opts.script) == "string" and opts.script != "")
    if (not has_bin) and (not has_script) then
        return nil, nil, "cgi_serve.run requires either opts.bin or opts.script"
    end

    cwd = lfs.currentdir()
    if cwd == nil then
        cwd = "."
    end

    root = opts.root
    if root == nil or root == "" then
        root = cwd
    elseif string.sub(root, 1, 1) != "/" then
        root = paths.joinpath(cwd, root)
    end

    cmd_argv = {}
    if has_bin then
        cmd_bin = opts.bin
        if string.sub(cmd_bin, 1, 1) != "/" then
            cmd_bin = paths.joinpath(cwd, cmd_bin)
        end
        if not paths.file_exists(cmd_bin) then
            return nil, nil, "CGI binary not found: " .. cmd_bin
        end
        cmd_argv = {cmd_bin}
    else
        cmd_bin = opts.luam_bin
        if cmd_bin == nil or cmd_bin == "" then
            cmd_bin = default_luam_bin()
        end
        cmd_script = opts.script
        if string.sub(cmd_script, 1, 1) != "/" then
            cmd_script = paths.joinpath(cwd, cmd_script)
        end
        if not paths.file_exists(cmd_script) then
            return nil, nil, "CGI script not found: " .. cmd_script
        end
        cmd_argv = {cmd_bin, cmd_script}
    end

    base_env = {}
    if opts.env != nil and type(opts.env) == "table" then
        for k, v in pairs(opts.env) do
            base_env[tostring(k)] = tostring(v)
        end
    end
    if has_script then
        if base_env["LUA_PATH"] == nil then
            base_env["LUA_PATH"] = package.path
        end
        if base_env["LUA_CPATH"] == nil then
            base_env["LUA_CPATH"] = package.cpath
        end
    end

    quiet = (opts.quiet == true)
    cgi_timeout_ms = default_val(opts.timeout_ms, 60000)

    function handler(req, loop)
        cgi_env = build_cgi_env(base_env, root, req)
        raw_out, exec_err = execute_cgi_async(cmd_argv, root, cgi_env, req.body, quiet, loop, cgi_timeout_ms)
        if raw_out == nil then
            return {
                status = 502,
                headers = {["Content-Type"] = "text/plain; charset=utf-8"},
                body = "CGI execution failed: " .. tostring(exec_err) .. "\n",
            }
        end
        return parse_cgi_output(raw_out, req.method)
    end

    return handler, {root = root, cwd = cwd, quiet = quiet}, nil
end

-- Runs the local HTTP-to-CGI server until interrupted (or for 1 request when `opts.once == true`).
-- Returns `true, nil` on clean exit or `false, err_string`.
function cgi_serve.run(opts)
    if type(opts) != "table" then
        return false, "cgi_serve.run expects an options table"
    end
    handler, meta, herr = cgi_serve.make_handler(opts)
    if handler == nil then
        return false, herr
    end

    host = opts.host
    if host == nil or host == "" then
        host = "127.0.0.1"
    end

    port = 8000
    if opts.port != nil then
        pnum = tonumber(opts.port)
        if pnum == nil or pnum < 0 or pnum > 65535 then
            return false, "opts.port must be between 0 and 65535"
        end
        port = math.floor(pnum)
    end

    port_file = nil
    if opts.port_file != nil and opts.port_file != "" then
        pf = opts.port_file
        if string.sub(pf, 1, 1) != "/" then
            pf = paths.joinpath(meta.cwd, pf)
        end
        port_file = pf
    end

    function log_req(req, status_code, peer)
        if not meta.quiet then
            io.write(io.stderr, string.format("[cgi_serve] %s - \"%s %s %s\" %d\n",
                tostring(peer), req.method, req.target, req.version, status_code))
        end
    end

    function announce_ready(actual_port)
        if not meta.quiet then
            io.write(io.stderr, string.format("Serving CGI at http://%s:%d/\n", host, actual_port))
        end
    end

    return http_serve.run({
        host = host,
        port = port,
        once = (opts.once == true),
        quiet = meta.quiet,
        port_file = port_file,
        handler = handler,
        on_log = log_req,
        on_ready = announce_ready,
        handle_signals = opts.handle_signals,
        loop = opts.loop,
    })
end

return cgi_serve
