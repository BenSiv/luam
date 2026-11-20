-- lib/static/build.lua
-- Orchestrates standalone native binary builds for Luam projects.
--
-- Supports both declarative `bld/package.lua` manifests and explicit CLI flags:
--   luam lib/static/build.lua                         # reads bld/package.lua
--   luam lib/static/build.lua --entry main.lua --bin app --with sqlite3,lfs

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

-- ---- Built-in C-extension registry ----

const MODULES = {
    sqlite3 = {
        sources = {"lib/sqlite/lsqlite3.c"},
        link = {"-lsqlite3"},
        luaopen = "luaopen_sqlite3",
    },
    lfs = {
        sources = {"lib/lfs/src/lfs.c"},
        link = {},
        luaopen = "luaopen_lfs",
    },
    bcrypt = {
        sources = {"lib/bcrypt/bcrypt.c"},
        link = {"-lcrypt"},
        luaopen = "luaopen_bcrypt",
    },
    hmac = {
        sources = {"lib/hmac/hmac.c"},
        link = {"-lcrypto"},
        luaopen = "luaopen_hmac",
    },
    crypto = {
        sources = {"lib/crypto/crypto.c"},
        link = {"-lcrypto"},
        luaopen = "luaopen_crypto",
    },
    vec = {
        sources = {"lib/vec/vec.c"},
        link = {"-lm"},
        luaopen = "luaopen_vec",
    },
    yaml = {
        sources = {
            "lib/yaml/lyaml.c", "lib/yaml/api.c", "lib/yaml/b64.c",
            "lib/yaml/dumper.c", "lib/yaml/emitter.c", "lib/yaml/loader.c",
            "lib/yaml/parser.c", "lib/yaml/reader.c", "lib/yaml/scanner.c",
            "lib/yaml/writer.c",
        },
        link = {},
        luaopen = "luaopen_yaml",
        extra_include = {"lib/yaml"},
    },
    mariadb = {
        sources = {"lib/mariadb/lmariadb.c"},
        link = {"-lmariadb"},
        luaopen = "luaopen_mariadb",
        extra_include = {"/usr/include/mariadb", "/usr/include/mariadb/mysql"},
        available = function()
            return paths.file_exists("/usr/include/mariadb/mysql.h")
        end,
    },
}

const FLATTEN_MODULES = {"dkjson"}

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
Usage: luam lib/static/build.lua [options]

Builds a standalone native executable from a Luam project. When `bld/package.lua`
exists (or `--package <file>` is given), settings are loaded from that manifest
and CLI options act as overrides/additions.
"""

const FLAG_SPECS = {
    {short = "p", long = "package", kind = "string", metavar = "<file>", desc = "Declarative package manifest (default: bld/package.lua if present)"},
    {short = "e", long = "entry", kind = "string", metavar = "<file>", desc = "Entry point Lua file relative to --src"},
    {short = "b", long = "bin", kind = "string", metavar = "<name>", desc = "Output binary name written to ./bin/<name>"},
    {short = "w", long = "with", kind = "string", metavar = "<mods>", desc = "Comma-separated C extension modules"},
    {short = "s", long = "src", kind = "string", metavar = "<dir>", desc = "Project Lua source directory (default: src)"},
    {short = "l", long = "luamdir", kind = "string", metavar = "<dir>", desc = "Path to built luam checkout (default: $LUAM_DIR or ../luam)"},
    {short = "a", long = "always_include", kind = "string", metavar = "<dirs>", desc = "Comma-separated directories force-bundled for dynamic require()"},
    {short = "v", long = "verbose", kind = "boolean", desc = "Print full compiler commands and output"},
}

opts, _, parse_err = cli.parse_flags(arg, FLAG_SPECS)
if parse_err != nil then
    io.write(io.stderr, "Error: " .. parse_err .. "\n\n" .. cli.render_help(HELP, FLAG_SPECS) .. "\n")
    os.exit(1)
end
if opts.help == true then
    print(cli.render_help(HELP, FLAG_SPECS))
    os.exit(0)
end

-- ---- Load optional bld/package.lua manifest ----

pkg = {}
pkg_path = opts.package
if pkg_path != nil and pkg_path != "" then
    pkg = data.load(pkg_path, {required = true})
    data.must_validate(pkg, PACKAGE_SCHEMA, pkg_path)
elseif opts.entry == nil and opts.bin == nil and paths.file_exists("bld/package.lua") then
    pkg_path = "bld/package.lua"
    pkg = data.load(pkg_path, {required = true})
    data.must_validate(pkg, PACKAGE_SCHEMA, pkg_path)
elseif paths.file_exists("bld/package.lua") and opts.package == nil then
    -- Allow partial CLI overrides (e.g. --luamdir or --verbose) over bld/package.lua
    if opts.entry == nil or opts.bin == nil then
        pkg_path = "bld/package.lua"
        pkg = data.load(pkg_path, {required = true})
        data.must_validate(pkg, PACKAGE_SCHEMA, pkg_path)
    end
end

VERBOSE = opts.verbose == true

SRC_DIR = opts.src
if SRC_DIR == nil then
    SRC_DIR = pkg.src
end
if SRC_DIR == nil then
    SRC_DIR = "src"
end

ENTRY = opts.entry
if ENTRY == nil then
    ENTRY = pkg.entry
end

BIN_NAME = opts.bin
if BIN_NAME == nil then
    BIN_NAME = pkg.bin
end

if ENTRY == nil or ENTRY == "" or BIN_NAME == nil or BIN_NAME == "" then
    io.write(io.stderr, "Error: --entry and --bin are required (either via bld/package.lua or CLI flags).\n\n" .. cli.render_help(HELP, FLAG_SPECS) .. "\n")
    os.exit(1)
end

ALWAYS_INCLUDE_DIRS = {}
seen_always = {}
function add_always_dir(d)
    if d != nil and d != "" and seen_always[d] != true then
        seen_always[d] = true
        table.insert(ALWAYS_INCLUDE_DIRS, d)
    end
end
if pkg.always_include != nil then
    for _, d in ipairs(pkg.always_include) do
        add_always_dir(d)
    end
end
if opts.always_include != nil then
    for d in string.gmatch(opts.always_include, "[^,]+") do
        add_always_dir(d)
    end
end

LUAM_DIR = opts.luamdir
if LUAM_DIR == nil then
    LUAM_DIR = os.getenv("LUAM_DIR")
end
if LUAM_DIR == nil then
    LUAM_DIR = paths.joinpath("..", "luam")
end
LUAM_LIB = paths.joinpath(LUAM_DIR, "obj", "liblua.a")
if not paths.file_exists(LUAM_LIB) then
    io.write(io.stderr, "Error: " .. LUAM_LIB .. " not found. Pass --luamdir or set LUAM_DIR to a built luam checkout.\n")
    os.exit(1)
end

-- ---- Verify minimum luam commit / exact pin when declared ----

allow_mismatch = os.getenv("LUAM_ALLOW_MISMATCH") == "1"
if not allow_mismatch and git.is_repo(LUAM_DIR) then
    if pkg.luam != nil and pkg.luam != "" then
        if not git.is_ancestor(pkg.luam, "HEAD", LUAM_DIR) then
            head_short = git.short_head(LUAM_DIR)
            io.write(io.stderr, "Error: luam checkout at " .. LUAM_DIR .. " (" .. tostring(head_short) ..
                ") does not contain required commit " .. pkg.luam .. " (from " .. tostring(pkg_path) .. ").\n")
            os.exit(1)
        end
    end
    if pkg.luam_pin != nil and pkg.luam_pin != "" then
        pin_sha = git.rev_parse(pkg.luam_pin, LUAM_DIR)
        head_sha = git.rev_parse("HEAD", LUAM_DIR)
        if pin_sha == nil or head_sha != pin_sha then
            io.write(io.stderr, "Error: luam checkout at " .. LUAM_DIR .. " does not match exact pin " ..
                pkg.luam_pin .. " (set LUAM_ALLOW_MISMATCH=1 to override).\n")
            os.exit(1)
        end
    end
end

-- ---- Collect built-in & custom native C/C++ modules ----

WITH_MODULES = {}
seen_with = {}
function request_builtin_module(name)
    if seen_with[name] == true then
        return
    end
    seen_with[name] = true
    entry = MODULES[name]
    if entry == nil then
        io.write(io.stderr, "Error: unknown module '" .. name .. "' -- see MODULES in " .. arg[0] .. "\n")
        os.exit(1)
    end
    if entry.available != nil and entry.available() == false then
        io.write(io.stderr, "Warning: '" .. name .. "' requested but its system dependency isn't present -- skipping, building without it.\n")
    else
        table.insert(WITH_MODULES, {name = name, spec = entry})
    end
end

if pkg.with != nil then
    for _, name in ipairs(pkg.with) do
        request_builtin_module(name)
    end
end
if opts.with != nil then
    for name in string.gmatch(opts.with, "[^,]+") do
        request_builtin_module(name)
    end
end

NATIVE_MODULES = {}
if pkg.native != nil then
    for _, nat in ipairs(pkg.native) do
        table.insert(NATIVE_MODULES, nat)
    end
end

-- ---- Logging ----

BUILD_LOG = os.tmpname()
LOG_FILE = io.open(BUILD_LOG, "w")

function log_write(line)
    io.write(LOG_FILE, line .. "\n")
end

function run_cmd(command)
    full_command = command
    if VERBOSE then
        print(command)
    else
        log_write(command)
        full_command = command .. " >> " .. ext.shell_quote(BUILD_LOG) .. " 2>&1"
    end
    ok = os.execute(full_command)
    return ok == true
end

function fail(message)
    io.write(io.stderr, "Build failed: " .. message .. "\n")
    if not VERBOSE then
        io.write(io.stderr, "Re-run with --verbose for full output. Last build log lines:\n")
        io.close(LOG_FILE)
        tail_file = io.open(BUILD_LOG, "r")
        if tail_file != nil then
            lines = {}
            while true do
                line = io.read(tail_file, "*line")
                if line == nil then
                    break
                end
                table.insert(lines, line)
            end
            io.close(tail_file)
            start = #lines - 40
            if start < 1 then
                start = 1
            end
            i = start
            while i <= #lines do
                io.write(io.stderr, lines[i] .. "\n")
                i = i + 1
            end
        end
    end
    os.remove(BUILD_LOG)
    os.exit(1)
end

-- ---- Temp working directory ----

PROJECT_ROOT = lfs.currentdir()
TMPDIR = os.tmpname()
os.remove(TMPDIR)
lfs.mkdir(TMPDIR)

function resolve_project_path(p)
    if string.sub(p, 1, 1) == "/" then
        return p
    end
    return paths.joinpath(PROJECT_ROOT, p)
end

function copy_file(from_path, to_path)
    input = io.open(from_path, "rb")
    if input == nil then
        fail("cannot read " .. from_path)
    end
    content = io.read(input, "*all")
    io.close(input)
    parent = paths.get_parent_dir(to_path)
    if parent != nil and parent != "." then
        paths.ensure_dir(parent)
    end
    output = io.open(to_path, "wb")
    if output == nil then
        fail("cannot write " .. to_path)
    end
    io.write(output, content)
    io.close(output)
end

function copy_lua_tree(from_dir, to_dir)
    for entry_name in lfs.dir(from_dir) do
        if entry_name != "." and entry_name != ".." then
            from_path = paths.joinpath(from_dir, entry_name)
            attrs = lfs.attributes(from_path)
            if attrs != nil and attrs.mode == "directory" then
                to_subdir = paths.joinpath(to_dir, entry_name)
                paths.ensure_dir(to_subdir)
                copy_lua_tree(from_path, to_subdir)
            elseif string.match(entry_name, "%.lua$") != nil then
                copy_file(from_path, paths.joinpath(to_dir, entry_name))
            end
        end
    end
end

print("Preparing build")

if not paths.is_dir(SRC_DIR) then
    fail("source directory '" .. SRC_DIR .. "' does not exist")
end
copy_lua_tree(SRC_DIR, TMPDIR)

-- Allow a root-level entry file (e.g. `entry.lua`) if not inside SRC_DIR.
if not paths.file_exists(paths.joinpath(TMPDIR, ENTRY)) and paths.file_exists(ENTRY) then
    copy_file(ENTRY, paths.joinpath(TMPDIR, paths.get_file_name(ENTRY)))
    ENTRY = paths.get_file_name(ENTRY)
end

-- Generate virtual build_commit module directly inside TMPDIR without dirtying src/.
if pkg.define_git_commit != nil and pkg.define_git_commit != "" then
    commit_val = git.describe(PROJECT_ROOT)
    if commit_val == nil or commit_val == "" then
        commit_val = "unknown"
    end
    mod_relpath = (string.gsub(pkg.define_git_commit, "%.", "/")) .. ".lua"
    commit_dest = paths.joinpath(TMPDIR, mod_relpath)
    ok_w, err_w = paths.write_file(commit_dest, "return " .. string.format("%q", commit_val) .. "\n")
    if not ok_w then
        fail("could not write generated commit module: " .. tostring(err_w))
    end
end

-- Copy Luam flat stdlib modules, checking for name collisions.
for entry_name in lfs.dir(paths.joinpath(LUAM_DIR, "lib")) do
    if string.match(entry_name, "%.lua$") != nil then
        dest_path = paths.joinpath(TMPDIR, entry_name)
        if paths.file_exists(dest_path) then
            fail("project source file '" .. entry_name .. "' collides with Luam stdlib module 'lib/" .. entry_name .. "'")
        end
        copy_file(paths.joinpath(LUAM_DIR, "lib", entry_name), dest_path)
    end
end

for _, name in ipairs(FLATTEN_MODULES) do
    init_path = paths.joinpath(LUAM_DIR, "lib", name, "init.lua")
    if paths.file_exists(init_path) then
        dest_path = paths.joinpath(TMPDIR, name .. ".lua")
        if paths.file_exists(dest_path) then
            fail("project source file '" .. name .. ".lua' collides with Luam vendored module 'lib/" .. name .. "/init.lua'")
        end
        copy_file(init_path, dest_path)
    end
end

-- ---- Reachability & Asset Discovery ----

function list_lua_tree(dir, prefix, out)
    for entry_name in lfs.dir(dir) do
        if entry_name != "." and entry_name != ".." then
            full_path = paths.joinpath(dir, entry_name)
            relative_path = entry_name
            if prefix != "" then
                relative_path = prefix .. "/" .. entry_name
            end
            attrs = lfs.attributes(full_path)
            if attrs != nil and attrs.mode == "directory" then
                list_lua_tree(full_path, relative_path, out)
            elseif string.match(entry_name, "%.lua$") != nil then
                table.insert(out, relative_path)
            end
        end
    end
end

function extract_requires(source)
    names = {}
    for quote, name in string.gmatch(source, "require%s*%(%s*([\"'])([%w_./%-]+)%1%s*%)") do
        table.insert(names, name)
    end
    return names
end

function extract_assets(source, caller_relpath)
    found = {}
    len = #source
    i = 1
    while i <= len do
        c = string.sub(source, i, i)
        if c == "-" and string.sub(source, i, i + 1) == "--" then
            nl_pos = string.index_of(source, "\n", i + 2)
            if nl_pos == nil then
                i = len + 1
            else
                i = nl_pos + 1
            end
        elseif c == "\"" and string.sub(source, i, i + 2) == "\"\"\"" then
            j = i + 3
            while j <= len do
                jc = string.sub(source, j, j)
                if jc == "\\" then
                    j = j + 2
                elseif jc == "\"" and string.sub(source, j, j + 2) == "\"\"\"" then
                    j = j + 3
                    break
                else
                    j = j + 1
                end
            end
            i = j
        elseif c == "\"" then
            j = i + 1
            while j <= len do
                jc = string.sub(source, j, j)
                if jc == "\\" then
                    j = j + 2
                elseif jc == "\"" then
                    j = j + 1
                    break
                else
                    j = j + 1
                end
            end
            i = j
        else
            matched = false
            if c == "a" then
                prev = ""
                if i > 1 then
                    prev = string.sub(source, i - 1, i - 1)
                end
                if prev == "" or string.match(prev, "[%w_.]") == nil then
                    s_start, s_end, relpath = string.find(source, "^asset%s*%.%s*read%s*%(%s*\"([^\"]*)\"%s*%)", i)
                    if s_start != nil then
                        table.insert(found, relpath)
                        i = s_end + 1
                        matched = true
                    elseif caller_relpath != "asset.lua" and string.find(source, "^asset%s*%.%s*read%s*%(", i) != nil then
                        fail("non-literal asset.read(...) in " .. caller_relpath .. ": pass a string literal so static builds can bundle the asset")
                    end
                end
            end
            if not matched then
                i = i + 1
            end
        end
    end
    return found
end

function validate_asset_relpath(relpath, caller_relpath)
    if relpath == "" or string.starts_with(relpath, "/") or string.ends_with(relpath, "/") or
       string.contains(relpath, "\\") or string.contains(relpath, "//") then
        fail("invalid asset.read(\"" .. relpath .. "\") path in " .. caller_relpath)
    end
    for _, part in ipairs(string.split(relpath, "/")) do
        if part == "" or part == "." or part == ".." then
            fail("invalid asset.read(\"" .. relpath .. "\") path in " .. caller_relpath)
        end
    end
end

function module_name_to_relpath(name)
    return (string.gsub(name, "%.", "/")) .. ".lua"
end

VISITED = {}
FILES = {}
BUNDLED_ASSET_SEEN = {}
BUNDLED_ASSET_LIST = {}

function record_asset(relpath, caller_relpath)
    validate_asset_relpath(relpath, caller_relpath)
    if BUNDLED_ASSET_SEEN[relpath] == true then
        return
    end
    BUNDLED_ASSET_SEEN[relpath] = true
    src_asset_path = paths.joinpath(SRC_DIR, relpath)
    asset_file = io.open(src_asset_path, "rb")
    if asset_file == nil then
        fail("asset.read(\"" .. relpath .. "\") referenced in " .. caller_relpath .. ", but '" .. src_asset_path .. "' does not exist")
    end
    asset_bytes = io.read(asset_file, "*all")
    io.close(asset_file)
    if asset_bytes == nil then
        asset_bytes = ""
    end
    table.insert(BUNDLED_ASSET_LIST, {relpath = relpath, bytes = asset_bytes})
end

function visit(relpath)
    if VISITED[relpath] == true then
        return
    end
    VISITED[relpath] = true
    full_path = paths.joinpath(TMPDIR, relpath)
    if not paths.file_exists(full_path) then
        return
    end
    table.insert(FILES, relpath)
    source_file = io.open(full_path, "r")
    source = io.read(source_file, "*all")
    io.close(source_file)
    for _, asset_relpath in ipairs(extract_assets(source, relpath)) do
        record_asset(asset_relpath, relpath)
    end
    for _, name in ipairs(extract_requires(source)) do
        visit(module_name_to_relpath(name))
    end
end

if not paths.file_exists(paths.joinpath(TMPDIR, ENTRY)) then
    fail("entry file '" .. ENTRY .. "' not found in '" .. SRC_DIR .. "'")
end
visit(ENTRY)

for _, dir in ipairs(ALWAYS_INCLUDE_DIRS) do
    dir_path = paths.joinpath(TMPDIR, dir)
    if paths.is_dir(dir_path) then
        dir_files = {}
        list_lua_tree(dir_path, dir, dir_files)
        for _, relpath in ipairs(dir_files) do
            visit(relpath)
        end
    elseif paths.file_exists(dir_path) then
        visit(dir)
    else
        mod_rel = module_name_to_relpath(dir)
        if paths.file_exists(paths.joinpath(TMPDIR, mod_rel)) then
            visit(mod_rel)
        end
    end
end

if VISITED["asset.lua"] == true or #BUNDLED_ASSET_LIST > 0 then
    bundled_assets_path = paths.joinpath(TMPDIR, "_bundled_assets.lua")
    if paths.file_exists(bundled_assets_path) then
        fail("project source file '_bundled_assets.lua' collides with generated asset bundle")
    end
    bundle_parts = {"return {\n"}
    for _, item in ipairs(BUNDLED_ASSET_LIST) do
        table.insert(bundle_parts, string.format("    [%q] = %q,\n", item.relpath, item.bytes))
    end
    table.insert(bundle_parts, "}\n")
    bundle_out = io.open(bundled_assets_path, "wb")
    io.write(bundle_out, table.concat(bundle_parts, ""))
    io.close(bundle_out)
    table.insert(FILES, "_bundled_assets.lua")
end

print("Files to bundle: " .. table.concat(FILES, " "))

-- ---- Generate C source via static/init.lua ----

print("Generating C source")
STATIC_TOOL = paths.joinpath(resolve_project_path(LUAM_DIR), "lib", "static", "init.lua")
LUAM_ABS = resolve_project_path(LUAM_DIR)
LUAM_BIN = paths.joinpath(LUAM_ABS, "bin", "luam")
LUAM_LIB_ABS = paths.joinpath(LUAM_ABS, "obj", "liblua.a")

old_dir = lfs.currentdir()
lfs.chdir(TMPDIR)

file_args = table.concat(FILES, " ")
ok = run_cmd(
    "CC=\"\" " .. ext.shell_quote(LUAM_BIN) .. " " .. ext.shell_quote(STATIC_TOOL) .. " " ..
    file_args .. " " .. ext.shell_quote(LUAM_LIB_ABS) .. " -I " .. ext.shell_quote(paths.joinpath(LUAM_ABS, "src")) .. " " ..
    "-lm -ldl -lreadline -lpthread"
)
if not ok then
    fail("static bundler (init.lua) failed to generate C source")
end

ENTRY_STEM = string.match(ENTRY, "(.+)%.lua$")
if ENTRY_STEM == nil then
    ENTRY_STEM = ENTRY
end
C_FILE = ENTRY_STEM .. ".static.c"

-- ---- Inject C/C++ preload registrations ----

ALL_PRELOADS = {}
for _, module in ipairs(WITH_MODULES) do
    table.insert(ALL_PRELOADS, {name = module.name, luaopen = module.spec.luaopen})
end
for _, nat in ipairs(NATIVE_MODULES) do
    table.insert(ALL_PRELOADS, {name = nat.name, luaopen = nat.luaopen})
end

if #ALL_PRELOADS > 0 then
    c_source = paths.read_file(C_FILE)
    declarations = {}
    registrations = {}
    for _, preload in ipairs(ALL_PRELOADS) do
        table.insert(declarations, "  int " .. preload.luaopen .. "(lua_State *L);")
        table.insert(registrations, "  lua_pushcfunction(L, " .. preload.luaopen .. ");")
        table.insert(registrations, "  lua_setfield(L, -2, " .. string.format("%q", preload.name) .. ");")
    end

    injection = table.concat(declarations, "\n") .. "\n" ..
        "  lua_getglobal(L, \"package\");\n" ..
        "  lua_getfield(L, -1, \"preload\");\n" ..
        table.concat(registrations, "\n") .. "\n" ..
        "  lua_pop(L, 2);\n"

    anchor = "luaL_openlibs(L);\n"
    anchor_pos = string.find(c_source, anchor, 1, true)
    if anchor_pos == nil then
        fail("could not find luaL_openlibs(L); in generated " .. C_FILE .. " to inject preload registration")
    end
    insert_at = anchor_pos + string.len(anchor)
    c_source = string.sub(c_source, 1, insert_at - 1) .. injection .. string.sub(c_source, insert_at)
    paths.write_file(C_FILE, c_source)
end

-- ---- Compile C/C++ extension objects ----

OBJECT_FILES = {}
obj_counter = 0
NEED_CXX = false

for _, module in ipairs(WITH_MODULES) do
    extra_includes = ""
    if module.spec.extra_include != nil then
        for _, dir in ipairs(module.spec.extra_include) do
            resolved_dir = dir
            if string.sub(dir, 1, 1) != "/" then
                resolved_dir = paths.joinpath(LUAM_ABS, dir)
            end
            extra_includes = extra_includes .. " -I" .. ext.shell_quote(resolved_dir)
        end
    end
    for _, source in ipairs(module.spec.sources) do
        obj_counter = obj_counter + 1
        object_name = string.format("mod_%d_%s.o", obj_counter, string.gsub(paths.get_file_name(source), "%.[^.]+$", ""))
        ok = run_cmd(
            "cc -c -O2 -fstack-protector-strong -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2 -I" .. ext.shell_quote(paths.joinpath(LUAM_ABS, "src")) .. extra_includes ..
            " " .. ext.shell_quote(paths.joinpath(LUAM_ABS, source)) .. " -o " .. object_name
        )
        if not ok then
            fail("failed compiling " .. source .. " (module '" .. module.name .. "')")
        end
        table.insert(OBJECT_FILES, object_name)
    end
end

extra_links = ""
for _, module in ipairs(WITH_MODULES) do
    for _, flag in ipairs(module.spec.link) do
        extra_links = extra_links .. " " .. flag
    end
end

for _, nat in ipairs(NATIVE_MODULES) do
    compiler = "cc"
    if nat.cxx == true then
        compiler = "g++"
        NEED_CXX = true
    end
    nat_flags = ""
    if nat.includes != nil then
        for _, inc in ipairs(nat.includes) do
            nat_flags = nat_flags .. " -I" .. ext.shell_quote(resolve_project_path(inc))
        end
    end
    if nat.cflags != nil then
        for _, cf in ipairs(nat.cflags) do
            nat_flags = nat_flags .. " " .. cf
        end
    end
    if nat.cflags_env != nil and nat.cflags_env != "" then
        env_cf = os.getenv(nat.cflags_env)
        if env_cf != nil and env_cf != "" then
            nat_flags = nat_flags .. " " .. env_cf
        end
    end
    for _, source in ipairs(nat.sources) do
        src_abs = resolve_project_path(source)
        if not paths.file_exists(src_abs) then
            fail("native source '" .. source .. "' not found for module '" .. nat.name .. "'")
        end
        obj_counter = obj_counter + 1
        object_name = string.format("nat_%d_%s.o", obj_counter, string.gsub(paths.get_file_name(source), "%.[^.]+$", ""))
        ok = run_cmd(
            compiler .. " -c -O2 -I" .. ext.shell_quote(paths.joinpath(LUAM_ABS, "src")) .. nat_flags ..
            " " .. ext.shell_quote(src_abs) .. " -o " .. object_name
        )
        if not ok then
            fail("failed compiling native source " .. source .. " (module '" .. nat.name .. "')")
        end
        table.insert(OBJECT_FILES, object_name)
    end
    if nat.link != nil then
        for _, lf in ipairs(nat.link) do
            extra_links = extra_links .. " " .. lf
        end
    end
    if nat.ldflags_env != nil and nat.ldflags_env != "" then
        env_lf = os.getenv(nat.ldflags_env)
        if env_lf != nil and env_lf != "" then
            extra_links = extra_links .. " " .. env_lf
        end
    end
end

-- ---- Compile bundle C stub as pure C, then link with cc or g++ ----

print("Compiling binary")
STATIC_OBJ = ENTRY_STEM .. ".static.o"
ok = run_cmd(
    "cc -c -Os -I" .. ext.shell_quote(paths.joinpath(LUAM_ABS, "src")) ..
    " " .. ext.shell_quote(C_FILE) .. " -o " .. ext.shell_quote(STATIC_OBJ)
)
if not ok then
    fail("failed compiling generated C bundle " .. C_FILE)
end

linker = "cc"
if NEED_CXX then
    linker = "g++"
end

obj_list = ext.shell_quote(STATIC_OBJ)
if #OBJECT_FILES > 0 then
    obj_list = obj_list .. " " .. table.concat(OBJECT_FILES, " ")
end

env_static_ldflags = os.getenv("LUAM_STATIC_LDFLAGS")
if env_static_ldflags != nil and env_static_ldflags != "" then
    extra_links = extra_links .. " " .. env_static_ldflags
end

ok = run_cmd(
    linker .. " -Os " .. obj_list .. " " .. ext.shell_quote(LUAM_LIB_ABS) ..
    " -lm -ldl -lreadline -lpthread" .. extra_links ..
    " -Wl,-z,relro,-z,now -Wl,--export-dynamic -o " .. ext.shell_quote(BIN_NAME)
)
if not ok then
    fail("final link failed")
end

lfs.chdir(old_dir)
paths.ensure_dir("bin")

ok = run_cmd("mv " .. ext.shell_quote(paths.joinpath(TMPDIR, BIN_NAME)) .. " " .. ext.shell_quote(paths.joinpath("bin", BIN_NAME)))
if not ok then
    fail("could not move the built binary into ./bin/")
end
run_cmd("rm -rf " .. ext.shell_quote(TMPDIR))

if pkg.symlinks != nil then
    for _, link_name in ipairs(pkg.symlinks) do
        ok_ln = run_cmd("ln -sf " .. ext.shell_quote(BIN_NAME) .. " " .. ext.shell_quote(paths.joinpath("bin", link_name)))
        if not ok_ln then
            fail("could not create symlink bin/" .. link_name)
        end
    end
end

if not VERBOSE then
    io.close(LOG_FILE)
end
os.remove(BUILD_LOG)

print("Build complete. Binary in bin/" .. BIN_NAME)
