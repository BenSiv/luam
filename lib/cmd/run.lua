-- lib/cmd/run.lua
-- Runs a Luam project (`bld/package.lua`) or script (`<file>.lua`) directly.

script_dir = string.match(arg[0], "^(.*/)")
if script_dir == nil then
    script_dir = "./"
end
lib_dir = script_dir .. "../"
package.path = lib_dir .. "?.lua;" .. lib_dir .. "?/init.lua;" .. package.path
package.cpath = lib_dir .. "?.so;" .. lib_dir .. "?/?.so;" .. package.cpath

const cli = require("cli")
const data = require("data")
const ext = require("external_tool")
const git = require("git")
const lfs = require("lfs")
const paths = require("paths")

const PACKAGE_SCHEMA = {
    fields = {
        bin = "string",
        entry = "string",
        src = "string",
        luam = "string",
        luam_pin = "string",
        with = {list_of = "string"},
        always_include = {list_of = "string"},
        define_git_commit = "string",
        symlinks = {list_of = "string"},
        native = {
            list_of = {
                fields = {
                    name = "string",
                    luaopen = "string",
                    sources = {list_of = "string"},
                    cxx = "boolean",
                    includes = {list_of = "string"},
                    cflags = {list_of = "string"},
                    link = {list_of = "string"},
                    cflags_env = "string",
                    ldflags_env = "string",
                },
                required = {"name", "luaopen", "sources"},
            },
        },
    },
}

const HELP = """
Usage: luam run [options] [--] [script.lua | args...]

Runs a Luam project from `bld/package.lua` (in-process when pure Luam/stdlib,
or building `bin/<bin>` first when custom `native` C/C++ sources are declared),
or executes a `.lua` script directly.
"""

const FLAG_SPECS = {
    {short = "p", long = "package", kind = "string", metavar = "<file>", desc = "Declarative package manifest (default: bld/package.lua)"},
    {short = "C", long = "dir", kind = "string", metavar = "<dir>", desc = "Change to <dir> before running"},
    {short = "h", long = "help", kind = "boolean", desc = "Show help message"},
}

initial_cwd = lfs.currentdir()

function make_abs(p, base)
    if p == nil or p == "" then
        return p
    end
    if string.sub(p, 1, 1) == "/" then
        return p
    end
    return paths.joinpath(base, p)
end

-- Derive luam binary and luam root before any chdir.
luam_bin = "luam"
if package.exec_dir != nil and package.exec_dir != "" then
    cand = paths.joinpath(package.exec_dir, "luam")
    if paths.file_exists(cand) then
        luam_bin = cand
    end
elseif arg != nil and arg[-1] != nil and arg[-1] != "" then
    if string.contains(arg[-1], "/") then
        luam_bin = make_abs(arg[-1], initial_cwd)
    else
        luam_bin = arg[-1]
    end
end

arg0_luam_root = nil
if arg != nil and arg[0] != nil and arg[0] != "" then
    arg0_abs = make_abs(arg[0], initial_cwd)
    d1 = paths.get_parent_dir(arg0_abs)
    d2 = paths.get_parent_dir(d1)
    d3 = paths.get_parent_dir(d2)
    if paths.file_exists(paths.joinpath(d3, "lib", "static", "build.lua")) then
        arg0_luam_root = d3
    end
end

luam_dir = nil
env_luam = os.getenv("LUAM_DIR")
if env_luam != nil and env_luam != "" then
    cand_env = make_abs(env_luam, initial_cwd)
    if paths.is_dir(cand_env) then
        luam_dir = cand_env
    else
        luam_dir = env_luam
    end
end
if luam_dir == nil and package.luam_root != nil and package.luam_root != "" then
    luam_dir = package.luam_root
end
if luam_dir == nil and arg0_luam_root != nil then
    luam_dir = arg0_luam_root
end
if luam_dir == nil then
    luam_dir = paths.joinpath("..", "luam")
end

-- Parse leading `luam run` flags only before `--` or the first non-run-flag token.
opt_package = nil
opt_dir = nil
opt_help = false
remaining = {}

n_args = 0
if arg != nil then
    n_args = #arg
end

i = 1
while i <= n_args do
    tok = arg[i]
    if tok == "--" then
        i = i + 1
        while i <= n_args do
            table.insert(remaining, arg[i])
            i = i + 1
        end
        break
    elseif tok == "-h" or tok == "--help" then
        opt_help = true
        i = i + 1
    elseif tok == "-p" or tok == "--package" then
        if i + 1 > n_args then
            io.write(io.stderr, "Error: missing value for option '" .. tok .. "'\n\n" .. cli.render_help(HELP, FLAG_SPECS) .. "\n")
            os.exit(1)
        end
        opt_package = arg[i + 1]
        i = i + 2
    elseif string.starts_with(tok, "--package=") then
        opt_package = string.sub(tok, #"--package=" + 1)
        i = i + 1
    elseif tok == "-C" or tok == "--dir" then
        if i + 1 > n_args then
            io.write(io.stderr, "Error: missing value for option '" .. tok .. "'\n\n" .. cli.render_help(HELP, FLAG_SPECS) .. "\n")
            os.exit(1)
        end
        opt_dir = arg[i + 1]
        i = i + 2
    elseif string.starts_with(tok, "--dir=") then
        opt_dir = string.sub(tok, #"--dir=" + 1)
        i = i + 1
    else
        while i <= n_args do
            table.insert(remaining, arg[i])
            i = i + 1
        end
        break
    end
end

if opt_help then
    print(cli.render_help(HELP, FLAG_SPECS))
    os.exit(0)
end

if opt_dir != nil and opt_dir != "" then
    ok_cd, err_cd = lfs.chdir(opt_dir)
    if ok_cd != true then
        io.write(io.stderr, "Error: cannot change directory to '" .. opt_dir .. "': " .. tostring(err_cd) .. "\n")
        os.exit(1)
    end
end

function strip_trailing_slashes(d)
    if d == "/" then
        return d
    end
    return (string.gsub(d, "/+$", ""))
end

function prepend_src_to_package_path(src_dir)
    clean_src = strip_trailing_slashes(src_dir)
    prefix = clean_src .. "/?.lua;" .. clean_src .. "/?/init.lua;"
    package.path = prefix .. package.path
end

function exec_lua_in_process(script_path, app_args)
    new_arg = {}
    new_arg[-1] = luam_bin
    new_arg[0] = script_path
    for idx = 1, #app_args do
        new_arg[idx] = app_args[idx]
    end
    _G.arg = new_arg

    chunk, load_err = loadfile(script_path, "t")
    if chunk == nil then
        io.write(io.stderr, "Error: " .. tostring(load_err) .. "\n")
        os.exit(1)
    end
    return chunk(table.unpack(app_args, 1, #app_args))
end

-- 1. Script mode: first remaining token ends with `.lua` and exists (when no `--package`).
if opt_package == nil and #remaining >= 1 and string.ends_with(remaining[1], ".lua") and paths.file_exists(remaining[1]) then
    script_target = remaining[1]
    script_args = {}
    for idx = 2, #remaining do
        table.insert(script_args, remaining[idx])
    end
    if paths.is_dir("./src") then
        prepend_src_to_package_path("./src")
    end
    exec_lua_in_process(script_target, script_args)
    os.exit(0)
end

-- 2. Project manifest mode.
pkg_path = opt_package
if pkg_path == nil or pkg_path == "" then
    pkg_path = "bld/package.lua"
elseif not paths.file_exists(pkg_path) and opt_dir != nil and opt_dir != "" then
    alt_pkg = make_abs(pkg_path, initial_cwd)
    if paths.file_exists(alt_pkg) then
        pkg_path = alt_pkg
    end
end

if not paths.file_exists(pkg_path) then
    io.write(io.stderr, "Error: manifest '" .. pkg_path .. "' not found (pass a script.lua or run inside a Luam project).\n")
    os.exit(1)
end

ok_load, pkg_or_err = pcall(data.load, pkg_path, {required = true})
if not ok_load then
    io.write(io.stderr, "Error: " .. tostring(pkg_or_err) .. "\n")
    os.exit(1)
end
pkg = pkg_or_err

ok_val, val_err = pcall(data.must_validate, pkg, PACKAGE_SCHEMA, pkg_path)
if not ok_val then
    io.write(io.stderr, "Error: " .. tostring(val_err) .. "\n")
    os.exit(1)
end

-- Verify luam floor / pin against LUAM_DIR.
allow_mismatch = os.getenv("LUAM_ALLOW_MISMATCH") == "1"
if not allow_mismatch and luam_dir != nil and git.is_repo(luam_dir) then
    if pkg.luam != nil and pkg.luam != "" then
        if not git.is_ancestor(pkg.luam, "HEAD", luam_dir) then
            head_short = git.short_head(luam_dir)
            io.write(io.stderr, "Error: luam checkout at " .. luam_dir .. " (" .. tostring(head_short) ..
                ") does not contain required commit " .. pkg.luam .. " (from " .. tostring(pkg_path) .. ").\n")
            os.exit(1)
        end
    end
    if pkg.luam_pin != nil and pkg.luam_pin != "" then
        pin_sha = git.rev_parse(pkg.luam_pin, luam_dir)
        head_sha = git.rev_parse("HEAD", luam_dir)
        if pin_sha == nil or head_sha != pin_sha then
            io.write(io.stderr, "Error: luam checkout at " .. luam_dir .. " does not match exact pin " ..
                pkg.luam_pin .. " (set LUAM_ALLOW_MISMATCH=1 to override).\n")
            os.exit(1)
        end
    end
end

-- Native C/C++ project fallback: build into bin/<pkg.bin> quietly, then exec it.
if pkg.native != nil and #pkg.native > 0 then
    if pkg.bin == nil or pkg.bin == "" then
        io.write(io.stderr, "Error: 'bin' is required in " .. pkg_path .. " when native modules are declared.\n")
        os.exit(1)
    end
    build_script = paths.joinpath(luam_dir, "lib", "static", "build.lua")
    build_cmd = ext.shell_quote(luam_bin) .. " " .. ext.shell_quote(build_script) ..
        " --luamdir " .. ext.shell_quote(luam_dir)
    if opt_package != nil and opt_package != "" then
        build_cmd = build_cmd .. " --package " .. ext.shell_quote(pkg_path)
    end
    b_out, b_ok, _ = ext.exec(build_cmd)
    if not b_ok then
        io.write(io.stderr, b_out)
        if not string.ends_with(b_out, "\n") then
            io.write(io.stderr, "\n")
        end
        os.exit(1)
    end

    bin_path = paths.joinpath("bin", pkg.bin)
    cmd_parts = {ext.shell_quote(bin_path)}
    for _, a in ipairs(remaining) do
        table.insert(cmd_parts, ext.shell_quote(a))
    end
    ok_exec, _, exit_code = os.execute(table.concat(cmd_parts, " "))
    if ok_exec == true then
        os.exit(0)
    end
    if type(exit_code) == "number" and exit_code > 0 then
        os.exit(exit_code)
    end
    os.exit(1)
end

-- Fast in-process execution (zero C compile).
src_dir = pkg.src
if src_dir == nil or src_dir == "" then
    src_dir = "src"
end

if pkg.entry == nil or pkg.entry == "" then
    io.write(io.stderr, "Error: 'entry' is required in " .. pkg_path .. ".\n")
    os.exit(1)
end

entry_path = paths.joinpath(src_dir, pkg.entry)
if not paths.file_exists(entry_path) then
    if paths.file_exists(pkg.entry) then
        entry_path = pkg.entry
    else
        io.write(io.stderr, "Error: entry file '" .. pkg.entry .. "' not found in '" .. src_dir .. "'.\n")
        os.exit(1)
    end
end

prepend_src_to_package_path(src_dir)

if pkg.define_git_commit != nil and pkg.define_git_commit != "" then
    commit_val = git.describe(".")
    if commit_val == nil or commit_val == "" then
        commit_val = "unknown"
    end
    package.preload[pkg.define_git_commit] = function()
        return commit_val
    end
end

exec_lua_in_process(entry_path, remaining)
