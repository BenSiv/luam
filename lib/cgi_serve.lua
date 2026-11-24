-- Local HTTP-to-CGI development & integration-test server.
--
-- Dispatches loopback HTTP requests to either a compiled Luam CGI binary
-- (`opts.bin`) or an interpreted Luam CGI entry script (`opts.script`),
-- forwarding standard RFC 3875 CGI environment variables and all `HTTP_*`
-- request headers. Supports `port = 0` + `opts.port_file` for race-free
-- ephemeral port allocation in automated tests.

const ext = require("external_tool")
const lfs = require("lfs")
const paths = require("paths")

has_proc, proc_mod = pcall(require, "proc")
USE_PROC = (has_proc == true and type(proc_mod) == "table" and type(proc_mod.run) == "function")

const cgi_serve = {}

const PYTHON_CGI_BRIDGE = """
import http.server, os, subprocess, sys, urllib.parse

CMD_BIN = os.environ["LUAM_CGI_CMD_BIN"]
CMD_SCRIPT = os.environ.get("LUAM_CGI_CMD_SCRIPT", "")
ROOT = os.environ["LUAM_CGI_ROOT"]
HOST = os.environ["LUAM_CGI_HOST"]
PORT = int(os.environ["LUAM_CGI_PORT"])
ONCE = os.environ.get("LUAM_CGI_ONCE") == "1"
QUIET = os.environ.get("LUAM_CGI_QUIET") == "1"
PORT_FILE = os.environ.get("LUAM_CGI_PORT_FILE", "")

class LuamCGIHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        if not QUIET:
            sys.stderr.write("[cgi_serve] %s - %s\\n" % (self.address_string(), fmt % args))

    def _dispatch_cgi(self):
        parsed = urllib.parse.urlsplit(self.path)
        path_info = urllib.parse.unquote(parsed.path or "/")
        query_string = parsed.query or ""

        length_hdr = self.headers.get("Content-Length")
        body = b""
        if length_hdr:
            body = self.rfile.read(int(length_hdr))

        env = dict(os.environ)
        env["GATEWAY_INTERFACE"] = "CGI/1.1"
        env["DOCUMENT_ROOT"] = ROOT
        env["REQUEST_METHOD"] = self.command
        env["PATH_INFO"] = path_info
        env["QUERY_STRING"] = query_string
        env["SERVER_NAME"] = HOST
        env["SERVER_PORT"] = str(self.server.server_address[1])
        env["REMOTE_ADDR"] = self.client_address[0]

        for hk, hv in self.headers.items():
            low = hk.lower()
            if low == "content-type":
                env["CONTENT_TYPE"] = hv
            elif low == "content-length":
                env["CONTENT_LENGTH"] = hv
            else:
                env_key = "HTTP_" + hk.upper().replace("-", "_")
                if env_key in env and hk.lower() == "cookie":
                    env["HTTP_COOKIE"] = hv
                else:
                    env[env_key] = hv

        cmd = [CMD_BIN]
        if CMD_SCRIPT != "":
            cmd.append(CMD_SCRIPT)

        proc = subprocess.run(
            cmd,
            input=body,
            stdout=subprocess.PIPE,
            stderr=sys.stderr,
            cwd=ROOT,
            env=env,
        )
        raw = proc.stdout
        sep = b"\\r\\n\\r\\n"
        idx = raw.find(sep)
        if idx < 0:
            sep = b"\\n\\n"
            idx = raw.find(sep)
        if idx < 0:
            self.send_response(500)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"Invalid CGI response")
            return

        hdr_bytes = raw[:idx].decode("iso-8859-1")
        payload = raw[idx + len(sep):]

        status_code = 200
        status_msg = "OK"
        out_headers = []
        for line in hdr_bytes.splitlines():
            if ":" not in line:
                continue
            k, v = line.split(":", 1)
            k = k.strip()
            v = v.strip()
            if k.lower() == "status":
                parts = v.split(" ", 1)
                status_code = int(parts[0])
                status_msg = parts[1] if len(parts) > 1 else ""
            else:
                out_headers.append((k, v))

        self.send_response(status_code, status_msg)
        has_len = False
        for k, v in out_headers:
            if k.lower() == "content-length":
                has_len = True
            self.send_header(k, v)
        if not has_len:
            self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(payload)

    def do_GET(self):
        self._dispatch_cgi()

    def do_POST(self):
        self._dispatch_cgi()

    def do_PUT(self):
        self._dispatch_cgi()

    def do_DELETE(self):
        self._dispatch_cgi()

    def do_HEAD(self):
        self._dispatch_cgi()

class ReusableHTTPServer(http.server.HTTPServer):
    allow_reuse_address = True

httpd = ReusableHTTPServer((HOST, PORT), LuamCGIHandler)
actual_port = httpd.server_address[1]
if PORT_FILE != "":
    tmp_pf = PORT_FILE + ".tmp"
    with open(tmp_pf, "w", encoding="utf-8") as fh:
        fh.write(str(actual_port) + "\\n")
    os.replace(tmp_pf, PORT_FILE)

if not QUIET:
    sys.stderr.write("Serving CGI at http://%s:%d/\\n" % (HOST, actual_port))
    sys.stderr.flush()

try:
    if ONCE:
        httpd.handle_request()
    else:
        httpd.serve_forever()
except KeyboardInterrupt:
    pass
finally:
    httpd.server_close()
"""

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
    return ext.available("python3")
end

-- Runs the local HTTP-to-CGI bridge until interrupted (or for 1 request when `opts.once == true`).
-- Returns `true, nil` on clean exit or `false, err_string`.
function cgi_serve.run(opts)
    if type(opts) != "table" then
        return false, "cgi_serve.run expects an options table"
    end
    if not cgi_serve.is_available() then
        return false, "python3 is required on PATH for cgi_serve"
    end

    has_bin = (type(opts.bin) == "string" and opts.bin != "")
    has_script = (type(opts.script) == "string" and opts.script != "")
    if (not has_bin) and (not has_script) then
        return false, "cgi_serve.run requires either opts.bin or opts.script"
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

    cmd_bin = ""
    cmd_script = ""
    if has_bin then
        cmd_bin = opts.bin
        if string.sub(cmd_bin, 1, 1) != "/" then
            cmd_bin = paths.joinpath(cwd, cmd_bin)
        end
        if not paths.file_exists(cmd_bin) then
            return false, "CGI binary not found: " .. cmd_bin
        end
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
            return false, "CGI script not found: " .. cmd_script
        end
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

    env_map = {}
    if opts.env != nil and type(opts.env) == "table" then
        for k, v in pairs(opts.env) do
            env_map[tostring(k)] = tostring(v)
        end
    end
    if has_script then
        if env_map["LUA_PATH"] == nil then
            env_map["LUA_PATH"] = package.path
        end
        if env_map["LUA_CPATH"] == nil then
            env_map["LUA_CPATH"] = package.cpath
        end
    end

    env_map["LUAM_CGI_CMD_BIN"] = cmd_bin
    env_map["LUAM_CGI_CMD_SCRIPT"] = cmd_script
    env_map["LUAM_CGI_ROOT"] = root
    env_map["LUAM_CGI_HOST"] = host
    env_map["LUAM_CGI_PORT"] = tostring(port)
    if opts.once == true then
        env_map["LUAM_CGI_ONCE"] = "1"
    else
        env_map["LUAM_CGI_ONCE"] = "0"
    end
    if opts.quiet == true then
        env_map["LUAM_CGI_QUIET"] = "1"
    else
        env_map["LUAM_CGI_QUIET"] = "0"
    end
    if opts.port_file != nil and opts.port_file != "" then
        pf = opts.port_file
        if string.sub(pf, 1, 1) != "/" then
            pf = paths.joinpath(cwd, pf)
        end
        env_map["LUAM_CGI_PORT_FILE"] = pf
    end

    if USE_PROC then
        ok_run, why_run, code_run = proc_mod.run({"python3", "-c", PYTHON_CGI_BRIDGE}, {env = env_map, cwd = root})
        if ok_run == true then
            return true, nil
        end
        return false, "cgi_serve exited (" .. tostring(why_run) .. " " .. tostring(code_run) .. ")"
    end

    -- Fallback to external_tool when proc.so is not available
    assigns = {}
    for k, v in pairs(env_map) do
        table.insert(assigns, k .. "=" .. ext.shell_quote(v))
    end
    table.sort(assigns)
    shell_cmd = table.concat(assigns, " ") .. " python3 -c " .. ext.shell_quote(PYTHON_CGI_BRIDGE)
    ok_sh, why_sh, code_sh = ext.run(shell_cmd)
    if ok_sh == true then
        return true, nil
    end
    return false, "cgi_serve exited (" .. tostring(why_sh) .. " " .. tostring(code_sh) .. ")"
end

return cgi_serve
