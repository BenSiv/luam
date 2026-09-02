-- lib/static/build.lua
-- Orchestrates a full static build for a downstream Luam project: it
-- doesn't reimplement the bundler (init.lua, in this same directory)
-- -- it wraps it, owning everything AROUND that one step instead:
-- gathering and flattening this project's own source plus Luam's own
-- stdlib/vendored modules, compiling and preload-registering whatever
-- C extension modules the project actually needs, and the final
-- compile+link into one native binary. Replaces the bash build.sh
-- every downstream project used to hand-roll independently for this
-- (daat, brain-ex) -- see README.md's own note on why this exists as
-- a Luam script rather than a shell script.
--
-- Usage:
--   luam lib/static/build.lua --entry main.lua --bin daat --with sqlite3,lfs,bcrypt,hmac,mariadb
--
-- See HELP below for the full option list.

-- Self-bootstrap: this script has to resolve argparse/paths/lfs
-- regardless of whatever LUA_PATH/LUA_CPATH the caller's shell happens
-- to have exported (or hasn't) -- the whole point is being a
-- self-sufficient orchestrator a downstream project's bld/build.sh can
-- invoke directly (see bld/build.sh's own exec line: no LUA_PATH setup
-- of its own), not something that silently depends on the caller
-- already having the right environment configured. A bare `require`
-- here previously relied on that unstated assumption -- confirmed as a
-- real, reproducible failure (not theoretical): the exact same
-- "module 'argparse' not found" error a bare Docker RUN step hits,
-- reproduced locally in a clean environment with LUA_PATH/LUA_CPATH
-- unset.
--
-- arg[0] is this script's own invoked path -- always
-- $LUAM_DIR/lib/static/build.lua, per bld/build.sh's own invocation --
-- so lib/ (one level up from lib/static/) is derived from it directly
-- rather than trusted to already be on the search path.
script_dir = string.match(arg[0], "^(.*/)")
if script_dir == nil then
    script_dir = "./"
end
lib_dir = script_dir .. "../"
package.path = lib_dir .. "?.lua;" .. lib_dir .. "?/init.lua;" .. package.path
package.cpath = lib_dir .. "?.so;" .. lib_dir .. "lfs/?.so;" .. package.cpath

argparse = require("argparse")
paths = require("paths")
lfs = require("lfs")

-- ---- The C-extension registry ----
--
-- Everything a downstream project might want statically compiled in
-- and preload-registered, in one place instead of copy-pasted and
-- independently re-edited per project. Adding a new module Luam
-- itself vendors means adding one entry here, not teaching every
-- downstream build script about it separately.
--
-- Each entry: sources (.c files to compile, paths relative to
-- LUAM_DIR), link (extra linker flags this module needs), luaopen
-- (the C symbol registered into package.preload), extra_include
-- (optional, extra -I directories), available (optional function --
-- if present and it returns false, this module is silently skipped
-- with a warning rather than failing the build; for a genuinely
-- optional system dependency, not vendored source).
MODULES = {
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
        -- A genuinely optional system dependency (not vendored
        -- source), so a machine without libmariadb-dev still gets a
        -- working binary, just without MariaDB support, instead of a
        -- hard build failure.
        available = function()
            return paths.file_exists("/usr/include/mariadb/mysql.h")
        end,
    },
}

-- Vendored subdirectory modules with their own init.lua, flattened
-- into <name>.lua for require("<name>") the same way every downstream
-- project's own build.sh already did by hand. "static" is deliberately
-- excluded -- that's this tool itself, never a runtime dependency of
-- the project being built.
FLATTEN_MODULES = {"dkjson", "ltn12", "mime", "socket", "ssl"}

-- ---- CLI ----

HELP = """
Usage: luam lib/static/build.lua --entry <file> --bin <name> [options]

  --entry <file>    Entry point Lua file, relative to --src (required)
  --bin <name>      Output binary name, written to ./bin/<name> (required)
  --with <modules>  Comma-separated C extension modules to compile in
                    and preload -- see MODULES in this file for the
                    full list (default: none)
  --src <dir>       This project's own source directory (default: src)
  --luamdir <dir>   Path to a built luam checkout (default: the
                    LUAM_DIR environment variable, or ../luam relative
                    to the current directory)
  --always_include <dirs>
                    Comma-separated directories (relative to the
                    flattened build tree -- in practice, almost always
                    a subdirectory of this project's own --src), whose
                    files are force-included in full regardless of
                    static require() reachability -- for a module
                    loaded by a computed require() a static source
                    scan can't see (e.g. a provider facade picking its
                    real implementation by name from a config value at
                    runtime).
  --verbose         Print full build command output instead of just a
                    log tail on failure
"""

expected_args = argparse.def_args("""
    -e --entry arg string true
    -b --bin arg string true
    -w --with arg string false
    -s --src arg string false
    -l --luamdir arg string false
    -a --always_include arg string false
    -v --verbose flag string false
""")
opts = argparse.parse_args(arg, expected_args, HELP)
if opts == nil then
    os.exit(1)
end

VERBOSE = opts["verbose"] == true
SRC_DIR = opts["src"]
if SRC_DIR == nil then
    SRC_DIR = "src"
end
ENTRY = opts["entry"]
BIN_NAME = opts["bin"]

ALWAYS_INCLUDE_DIRS = {}
if opts["always_include"] != nil then
    for dir in string.gmatch(opts["always_include"], "[^,]+") do
        table.insert(ALWAYS_INCLUDE_DIRS, dir)
    end
end

LUAM_DIR = opts["luamdir"]
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

WITH_MODULES = {}
if opts["with"] != nil then
    for name in string.gmatch(opts["with"], "[^,]+") do
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
        full_command = command .. " >> " .. BUILD_LOG .. " 2>&1"
    end
    ok = os.execute(full_command)
    return ok == 0
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

TMPDIR = os.tmpname()
os.remove(TMPDIR)
lfs.mkdir(TMPDIR)

function copy_file(from_path, to_path)
    input = io.open(from_path, "r")
    if input == nil then
        fail("cannot read " .. from_path)
    end
    content = io.read(input, "*all")
    io.close(input)
    output = io.open(to_path, "w")
    io.write(output, content)
    io.close(output)
end

-- Recursively copies every .lua file under from_dir into to_dir,
-- preserving subdirectory structure -- unlike the vendored-module
-- flattening below (dkjson/init.lua -> dkjson.lua is deliberate), a
-- project's own source keeps its own layout, since a nested
-- require("agent_tools.bridge") expects a real agent_tools/bridge.lua
-- at the matching nested path, not everything flattened to one level
-- (confirmed real: this used to only copy from_dir's own top-level
-- files, silently dropping every subdirectory a project happened to
-- have).
function copy_lua_tree(from_dir, to_dir)
    for entry_name in lfs.dir(from_dir) do
        if entry_name != "." and entry_name != ".." then
            from_path = paths.joinpath(from_dir, entry_name)
            attrs = lfs.attributes(from_path)
            if attrs != nil and attrs.mode == "directory" then
                to_subdir = paths.joinpath(to_dir, entry_name)
                if not paths.file_exists(to_subdir) then
                    lfs.mkdir(to_subdir)
                end
                copy_lua_tree(from_path, to_subdir)
            elseif string.match(entry_name, "%.lua$") != nil then
                copy_file(from_path, paths.joinpath(to_dir, entry_name))
            end
        end
    end
end

print("Preparing build")

-- This project's own source, subdirectories and all.
copy_lua_tree(SRC_DIR, TMPDIR)

-- Luam's own flat stdlib.
for entry_name in lfs.dir(paths.joinpath(LUAM_DIR, "lib")) do
    if string.match(entry_name, "%.lua$") != nil then
        copy_file(paths.joinpath(LUAM_DIR, "lib", entry_name), paths.joinpath(TMPDIR, entry_name))
    end
end

-- Vendored subdirectory modules, flattened.
for _, name in ipairs(FLATTEN_MODULES) do
    init_path = paths.joinpath(LUAM_DIR, "lib", name, "init.lua")
    if paths.file_exists(init_path) then
        copy_file(init_path, paths.joinpath(TMPDIR, name .. ".lua"))
    end
end

-- Unlike the hand-rolled build.sh scripts this replaces, nothing above
-- ever copies lib/static/'s own tool files (init.lua, build.lua) into
-- TMPDIR in the first place -- only flat lib/*.lua files and the
-- specific FLATTEN_MODULES subdirectories, neither of which reaches
-- lib/static/ -- so there's nothing defensive left to remove here.
-- (An earlier version of this step unconditionally deleted any
-- init.lua from TMPDIR "just in case," which silently broke daat's
-- own unrelated src/init.lua the first time this was tested for real.)

-- ---- File list ----

-- Recursively lists every .lua file under dir, as paths relative to
-- TMPDIR (e.g. "agent_tools/bridge.lua") -- the bundler resolves
-- require("agent_tools.bridge") against exactly this kind of relative
-- path, the same way it would against real files on disk.
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

-- FILES is what actually gets bundled: ENTRY plus everything reachable
-- from it via a literal require(), not every .lua file that happens to
-- be sitting in TMPDIR (daat's own build once carried 7 of ~16 plain
-- Lua stdlib modules -- bioinfo, graphs, dataframes, and friends --
-- into its binary for zero benefit, never required anywhere). A
-- computed require() (a provider facade picking its implementation by
-- name from a config value at runtime) can't be seen by this kind of
-- static scan -- see --always_include above for the explicit escape
-- hatch that covers it instead of trying to be clever about parsing
-- what a runtime expression might evaluate to.

-- Every literal require("name")/require('name') call's module name in
-- `source` -- deliberately only a literal string argument; a computed
-- one (string concatenation, a variable) is invisible here on purpose,
-- not a parsing gap to close.
function extract_requires(source)
    names = {}
    for quote, name in string.gmatch(source, "require%s*%(%s*([\"'])([%w_./]+)%1%s*%)") do
        table.insert(names, name)
    end
    return names
end

-- "agent_tools.bridge" -> "agent_tools/bridge.lua"; "sandbox" -> "sandbox.lua".
function module_name_to_relpath(name)
    return (string.gsub(name, "%.", "/")) .. ".lua"
end

VISITED = {}
FILES = {}

-- Depth-first from `relpath`. If it resolves to a real .lua file in
-- TMPDIR, add it (before recursing, so ENTRY always lands first in
-- FILES) and walk whatever it requires in turn. If it doesn't resolve
-- to a real file -- a C-extension module like sqlite3/lfs, preloaded a
-- completely different way via --with -- there's nothing to add or
-- recurse into, and that's expected, not an error.
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
    for _, name in ipairs(extract_requires(source)) do
        visit(module_name_to_relpath(name))
    end
end

visit(ENTRY)

-- Force-include every real need a static scan can't see (see
-- --always_include's own help text above) -- a whole directory, not
-- one named file, since the point is every implementation a runtime
-- config value could pick, not just whichever happens to be today's
-- default.
for _, dir in ipairs(ALWAYS_INCLUDE_DIRS) do
    dir_path = paths.joinpath(TMPDIR, dir)
    if paths.file_exists(dir_path) then
        dir_files = {}
        list_lua_tree(dir_path, dir, dir_files)
        for _, relpath in ipairs(dir_files) do
            if VISITED[relpath] != true then
                VISITED[relpath] = true
                table.insert(FILES, relpath)
            end
        end
    end
end

print("Files to bundle: " .. table.concat(FILES, " "))

-- ---- Generate the C source (via init.lua, CC="" so it only writes
-- <entry_stem>.static.c and skips its own compile step -- the final,
-- fuller compile/link happens below instead, once any requested C
-- modules are injected). ----

print("Generating C source")
STATIC_TOOL = paths.joinpath(LUAM_DIR, "lib", "static", "init.lua")
LUAM_BIN = paths.joinpath(LUAM_DIR, "bin", "luam")
old_dir = lfs.currentdir()
lfs.chdir(TMPDIR)

file_args = table.concat(FILES, " ")
ok = run_cmd(
    "CC=\"\" \"" .. LUAM_BIN .. "\" \"" .. STATIC_TOOL .. "\" " ..
    file_args .. " \"" .. LUAM_LIB .. "\" -I \"" .. paths.joinpath(LUAM_DIR, "src") .. "\" " ..
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

-- ---- Inject requested C modules' preload registration ----

if #WITH_MODULES > 0 then
    c_source_file = io.open(C_FILE, "r")
    c_source = io.read(c_source_file, "*all")
    io.close(c_source_file)

    declarations = {}
    registrations = {}
    for _, module in ipairs(WITH_MODULES) do
        table.insert(declarations, "  int " .. module.spec.luaopen .. "(lua_State *L);")
        table.insert(registrations, "  lua_pushcfunction(L, " .. module.spec.luaopen .. ");")
        table.insert(registrations, "  lua_setfield(L, -2, \"" .. module.name .. "\");")
    end

    -- Registration must come after package.preload is already fetched
    -- onto the stack, not grouped with the plain declarations above --
    -- confirmed live in an earlier hand-written build.sh: doing it the
    -- other way panics ("attempt to index a nil value") the first time
    -- the binary runs at all, because it indexes whatever's on the
    -- stack before preload is actually there.
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

    c_source_file = io.open(C_FILE, "w")
    io.write(c_source_file, c_source)
    io.close(c_source_file)
end

-- ---- Compile each requested module's own C sources ----

OBJECT_FILES = {}
for _, module in ipairs(WITH_MODULES) do
    extra_includes = ""
    if module.spec.extra_include != nil then
        for _, dir in ipairs(module.spec.extra_include) do
            -- A registry entry's own extra_include may be a real
            -- absolute system path (mariadb's /usr/include/mariadb)
            -- or a path relative to LUAM_DIR (yaml's lib/yaml, its
            -- own vendored headers) -- only the latter needs joining.
            resolved_dir = dir
            if string.sub(dir, 1, 1) != "/" then
                resolved_dir = paths.joinpath(LUAM_DIR, dir)
            end
            extra_includes = extra_includes .. " -I\"" .. resolved_dir .. "\""
        end
    end
    for _, source in ipairs(module.spec.sources) do
        object_name = string.gsub(paths.get_file_name(source), "%.c$", ".o")
        ok = run_cmd(
            "cc -c -O2 -I\"" .. paths.joinpath(LUAM_DIR, "src") .. "\"" .. extra_includes ..
            " \"" .. paths.joinpath(LUAM_DIR, source) .. "\" -o " .. object_name
        )
        if not ok then
            fail("failed compiling " .. source .. " (module '" .. module.name .. "')")
        end
        table.insert(OBJECT_FILES, object_name)
    end
end

-- ---- Final compile + link ----

print("Compiling binary")
extra_links = ""
for _, module in ipairs(WITH_MODULES) do
    for _, flag in ipairs(module.spec.link) do
        extra_links = extra_links .. " " .. flag
    end
end

ok = run_cmd(
    "cc -Os " .. C_FILE .. " " .. table.concat(OBJECT_FILES, " ") .. " \"" .. LUAM_LIB .. "\" " ..
    "-I \"" .. paths.joinpath(LUAM_DIR, "src") .. "\" " ..
    "-lm -ldl -lreadline -lpthread" .. extra_links .. " " ..
    "-Wl,--export-dynamic -o " .. BIN_NAME
)
if not ok then
    fail("final compile/link failed")
end

lfs.chdir(old_dir)
if not paths.file_exists("bin") then
    lfs.mkdir("bin")
end
-- A real `mv`, not copy_file's own read/write (copy_file is fine for
-- small text sources; it silently drops the executable bit on a
-- compiled binary, confirmed live -- the output was unrunnable until
-- this was a real move instead).
ok = run_cmd("mv \"" .. paths.joinpath(TMPDIR, BIN_NAME) .. "\" \"" .. paths.joinpath("bin", BIN_NAME) .. "\"")
if not ok then
    fail("could not move the built binary into ./bin/")
end

if not VERBOSE then
    io.close(LOG_FILE)
end
os.remove(BUILD_LOG)

print("Build complete. Binary in bin/" .. BIN_NAME)
