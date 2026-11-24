-- lib/cmd/test.lua
-- Discovers and executes Luam test suites in isolated subprocesses.

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
const lfs = require("lfs")
const paths = require("paths")

const HELP = """
Usage: luam test [options] [test_files...]

Discovers and runs project tests with `LUA_PATH` and `LUA_CPATH` automatically
configured. Runs `tst/run_tests.lua` if present (when no `--filter` or explicit
files are given), or discovers `tst/**/test_*.lua` and `tst/**/tst_*.lua`.
"""

const FLAG_SPECS = {
    {short = "C", long = "dir", kind = "string", metavar = "<dir>", desc = "Run tests in <dir>"},
    {short = "v", long = "verbose", kind = "boolean", desc = "Stream test output live"},
    {short = "f", long = "filter", kind = "string", metavar = "<substr>", desc = "Only run test paths containing <substr>"},
    {long = "bats", kind = "boolean", desc = "Also discover and run .bats suites under tst/"},
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

opts, explicit_targets, parse_err = cli.parse_flags(arg, FLAG_SPECS)
if parse_err != nil then
    io.write(io.stderr, "Error: " .. parse_err .. "\n\n" .. cli.render_help(HELP, FLAG_SPECS) .. "\n")
    os.exit(1)
end
if opts.help == true then
    print(cli.render_help(HELP, FLAG_SPECS))
    os.exit(0)
end

if opts.dir != nil and opts.dir != "" then
    ok_cd, err_cd = lfs.chdir(opts.dir)
    if ok_cd != true then
        io.write(io.stderr, "Error: cannot change directory to '" .. opts.dir .. "': " .. tostring(err_cd) .. "\n")
        os.exit(1)
    end
end

VERBOSE = opts.verbose == true
FILTER = opts.filter
RUN_BATS = opts.bats == true

-- Determine project source directory for LUA_PATH.
src_dir = "src"
if paths.file_exists("bld/package.lua") then
    ok_pkg, pkg = pcall(data.load, "bld/package.lua")
    if ok_pkg and type(pkg) == "table" and type(pkg.src) == "string" and pkg.src != "" then
        src_dir = pkg.src
    end
end
clean_src = string.gsub(src_dir, "/+$", "")

-- Configure child LUA_PATH & LUA_CPATH so project src/tst and the active luam's
-- own lib/ always take precedence over any older system-wide LUA_PATH/LUA_CPATH.
lua_path_prefix = "./" .. clean_src .. "/?.lua;./" .. clean_src .. "/?/init.lua;./tst/?.lua;"
if luam_dir != nil and luam_dir != "" then
    lua_path_prefix = lua_path_prefix .. luam_dir .. "/lib/?.lua;" .. luam_dir .. "/lib/?/init.lua;"
end

existing_lua_path = os.getenv("LUA_PATH")
child_lua_path = lua_path_prefix .. ";"
if existing_lua_path != nil and existing_lua_path != "" then
    if string.contains(existing_lua_path, ";;") then
        child_lua_path = lua_path_prefix .. existing_lua_path
    else
        child_lua_path = lua_path_prefix .. existing_lua_path .. ";;"
    end
end

env_prefix = "LUA_PATH=" .. ext.shell_quote(child_lua_path) .. " "
cpath_prefix = ""
if luam_dir != nil and luam_dir != "" then
    cpath_prefix = luam_dir .. "/lib/?.so;" .. luam_dir .. "/lib/?/?.so;" .. luam_dir .. "/bin/?.so;"
end
existing_lua_cpath = os.getenv("LUA_CPATH")
if existing_lua_cpath != nil and existing_lua_cpath != "" then
    child_cpath = cpath_prefix .. existing_lua_cpath
    if not string.contains(child_cpath, ";;") then
        child_cpath = child_cpath .. ";;"
    end
    env_prefix = env_prefix .. "LUA_CPATH=" .. ext.shell_quote(child_cpath) .. " "
elseif cpath_prefix != "" then
    env_prefix = env_prefix .. "LUA_CPATH=" .. ext.shell_quote(cpath_prefix .. ";") .. " "
end

discover_tests = nil
discover_tests = function(dir, lua_out, bats_out)
    entries = {}
    for name in lfs.dir(dir) do
        if name != "." and name != ".." then
            table.insert(entries, name)
        end
    end
    table.sort(entries)
    for _, name in ipairs(entries) do
        full = paths.joinpath(dir, name)
        mode = lfs.attributes(full, "mode")
        if mode == "directory" then
            discover_tests(full, lua_out, bats_out)
        elseif name != "test_framework.lua" and (string.match(name, "^test_.*%.lua$") != nil or string.match(name, "^tst_.*%.lua$") != nil) then
            table.insert(lua_out, full)
        elseif RUN_BATS and string.match(name, "%.bats$") != nil then
            table.insert(bats_out, full)
        end
    end
end

function matches_filter(relpath)
    if FILTER == nil or FILTER == "" then
        return true
    end
    return string.contains(relpath, FILTER)
end

function run_one_cmd(label, cmd)
    if VERBOSE then
        ok_v = os.execute(cmd)
        if ok_v == true then
            print("PASS " .. label)
            return true
        end
        print("FAIL " .. label)
        return false
    end

    out, ok_c, _ = ext.exec(cmd)
    if ok_c then
        print("PASS " .. label)
        return true
    end
    print("FAIL " .. label)
    if out != nil and out != "" then
        io.write(io.stderr, out)
        if not string.ends_with(out, "\n") then
            io.write(io.stderr, "\n")
        end
    end
    return false
end

-- Custom runner shortcut when no explicit files and no --filter are passed.
if #explicit_targets == 0 and (FILTER == nil or FILTER == "") and paths.file_exists("tst/run_tests.lua") then
    runner_cmd = env_prefix .. ext.shell_quote(luam_bin) .. " tst/run_tests.lua"
    ok_runner = os.execute(runner_cmd)
    runner_ok = (ok_runner == true)

    bats_failed = 0
    if RUN_BATS and paths.is_dir("tst") then
        bats_list = {}
        unused_lua = {}
        discover_tests("tst", unused_lua, bats_list)
        table.sort(bats_list)
        if #bats_list > 0 then
            if not ext.available("bats") then
                io.write(io.stderr, "Error: 'bats' is not installed on PATH.\n")
                os.exit(1)
            end
            for _, bfile in ipairs(bats_list) do
                if not run_one_cmd(bfile, env_prefix .. "bats " .. ext.shell_quote(bfile)) then
                    bats_failed = bats_failed + 1
                end
            end
        end
    end

    if runner_ok and bats_failed == 0 then
        os.exit(0)
    end
    os.exit(1)
end

lua_tests = {}
bats_tests = {}

if #explicit_targets > 0 then
    for _, target in ipairs(explicit_targets) do
        if paths.is_dir(target) then
            discover_tests(target, lua_tests, bats_tests)
        elseif paths.file_exists(target) then
            if string.ends_with(target, ".bats") then
                table.insert(bats_tests, target)
            else
                table.insert(lua_tests, target)
            end
        else
            io.write(io.stderr, "Error: test target not found: " .. target .. "\n")
            os.exit(1)
        end
    end
else
    if paths.is_dir("tst") then
        discover_tests("tst", lua_tests, bats_tests)
    end
end

table.sort(lua_tests)
table.sort(bats_tests)

filtered_lua = {}
for _, rel in ipairs(lua_tests) do
    if matches_filter(rel) then
        table.insert(filtered_lua, rel)
    end
end

filtered_bats = {}
for _, rel in ipairs(bats_tests) do
    if matches_filter(rel) then
        table.insert(filtered_bats, rel)
    end
end

if #filtered_lua == 0 and #filtered_bats == 0 then
    io.write(io.stderr, "Error: no tests found.\n")
    os.exit(1)
end

if #filtered_bats > 0 and not ext.available("bats") then
    io.write(io.stderr, "Error: 'bats' is not installed on PATH.\n")
    os.exit(1)
end

passed = 0
failed = 0

for _, relpath in ipairs(filtered_lua) do
    cmd = env_prefix .. ext.shell_quote(luam_bin) .. " " .. ext.shell_quote(relpath)
    if run_one_cmd(relpath, cmd) then
        passed = passed + 1
    else
        failed = failed + 1
    end
end

for _, relpath in ipairs(filtered_bats) do
    cmd = env_prefix .. "bats " .. ext.shell_quote(relpath)
    if run_one_cmd(relpath, cmd) then
        passed = passed + 1
    else
        failed = failed + 1
    end
end

print(string.format("\nPassed: %d, Failed: %d", passed, failed))
if failed > 0 then
    os.exit(1)
end
os.exit(0)
