-- lib/cmd/check.lua
-- Static syntax, manifest, asset, and cross-file call checker for Luam projects.

script_dir = string.match(arg[0], "^(.*/)")
if script_dir == nil then
    script_dir = "./"
end
lib_dir = script_dir .. "../"
package.path = lib_dir .. "?.lua;" .. lib_dir .. "?/init.lua;" .. package.path
package.cpath = lib_dir .. "?.so;" .. lib_dir .. "?/?.so;" .. package.cpath

const cli = require("cli")
const data = require("data")
const git = require("git")
const lfs = require("lfs")
const paths = require("paths")
const sandbox = require("sandbox")

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

const KNOWN_WITH_MODULES = {
    sqlite3 = true,
    lfs = true,
    bcrypt = true,
    hmac = true,
    crypto = true,
    vec = true,
    proc = true,
    poll = true,
    net = true,
    yaml = true,
    mariadb = true,
}

const HELP = """
Usage: luam check [options] [files/dirs...]

Validates `bld/package.lua`, compiles all `.lua` files in `src/` and `tst/`
with `loadfile(..., "t")` (verifying syntax, strict escapes, `const`, and
literal-`nil` conditional checks), verifies `asset.read(...)` literals and
asset files under `src/`, and warns on bare cross-file function calls.
"""

const FLAG_SPECS = {
    {short = "C", long = "dir", kind = "string", metavar = "<dir>", desc = "Run checks in <dir>"},
    {short = "v", long = "verbose", kind = "boolean", desc = "Print every checked file"},
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

opts, targets, parse_err = cli.parse_flags(arg, FLAG_SPECS)
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
errors = {}

function add_error(msg)
    table.insert(errors, msg)
    io.write(io.stderr, "error: " .. msg .. "\n")
end

collect_lua_files = nil
collect_lua_files = function(dir, out)
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
            collect_lua_files(full, out)
        elseif string.match(name, "%.lua$") != nil then
            table.insert(out, full)
        end
    end
end

function scan_assets_in_source(source, caller_path, add_err_fn)
    found = {}
    len = #source
    i = 1
    base_name = paths.get_file_name(caller_path)
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
                    elseif base_name != "asset.lua" and string.find(source, "^asset%s*%.%s*read%s*%(", i) != nil then
                        add_err_fn("non-literal asset.read(...) in " .. caller_path .. ": pass a string literal so static builds can bundle the asset")
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

function validate_asset_relpath(relpath, caller_path)
    if relpath == "" or string.starts_with(relpath, "/") or string.ends_with(relpath, "/") or
       string.contains(relpath, "\\") or string.contains(relpath, "//") then
        add_error("invalid asset.read(\"" .. relpath .. "\") path in " .. caller_path)
        return false
    end
    for _, part in ipairs(string.split(relpath, "/")) do
        if part == "" or part == "." or part == ".." then
            add_error("invalid asset.read(\"" .. relpath .. "\") path in " .. caller_path)
            return false
        end
    end
    return true
end

function warn_bare_cross_file_calls(src_files)
    definers = {}
    sources = {}
    for _, path in ipairs(src_files) do
        content = paths.read_file(path)
        if content != nil then
            sources[path] = content
            padded = "\n" .. content
            for name in string.gmatch(padded, "\nfunction ([%a_][%w_]*)%(") do
                if definers[name] == nil then
                    definers[name] = {}
                end
                table.insert(definers[name], path)
            end
        end
    end

    def_names = {}
    for name, _ in pairs(definers) do
        table.insert(def_names, name)
    end
    table.sort(def_names)

    for _, name in ipairs(def_names) do
        defining_files = definers[name]
        if #defining_files == 1 then
            definer = defining_files[1]
            base = paths.get_file_name(definer)
            module_name = string.match(base, "(.+)%.")
            if module_name == nil then
                module_name = base
            end
            for _, path in ipairs(src_files) do
                if path != definer and sources[path] != nil then
                    padded_src = "\n" .. sources[path]
                    if string.find(padded_src, "[^%w_.]" .. name .. "%(") != nil then
                        io.write(io.stderr, string.format(
                            "warning: %s defines '%s' as a bare (unexported) function, but %s calls it directly without going through %s's own module table. Consider exporting it properly instead (e.g. function %s.%s(...)).\n",
                            definer, name, path, definer, module_name, name
                        ))
                    end
                end
            end
        end
    end
end

all_files = {}
src_files = {}
src_dir = "src"

if #targets > 0 then
    seen = {}
    for _, target in ipairs(targets) do
        if paths.is_dir(target) then
            found = {}
            collect_lua_files(target, found)
            for _, f in ipairs(found) do
                if seen[f] != true then
                    seen[f] = true
                    table.insert(all_files, f)
                end
            end
        elseif paths.file_exists(target) then
            if seen[target] != true then
                seen[target] = true
                table.insert(all_files, target)
            end
        else
            add_error("target not found: " .. target)
        end
    end
    table.sort(all_files)
    if paths.is_dir(src_dir) then
        src_prefix = src_dir .. "/"
        for _, f in ipairs(all_files) do
            if string.starts_with(f, src_prefix) or string.starts_with(f, "./" .. src_prefix) then
                table.insert(src_files, f)
            end
        end
    end
else
    -- Project mode (no positional targets)
    pkg = nil
    pkg_path = "bld/package.lua"
    if paths.file_exists(pkg_path) then
        if VERBOSE then
            print("Checking " .. pkg_path)
        end
        raw_manifest = paths.read_file(pkg_path)
        if raw_manifest == nil then
            add_error(pkg_path .. ": cannot read file")
        else
            ok_sb, loaded_val = sandbox.run(raw_manifest, "@" .. pkg_path, sandbox.data_env())
            if not ok_sb then
                add_error(pkg_path .. ": " .. tostring(loaded_val))
            elseif type(loaded_val) != "table" then
                add_error(pkg_path .. ": must return a table, got " .. type(loaded_val))
            else
                -- Also verify via data.load + PACKAGE_SCHEMA
                pkg = data.load(pkg_path, {required = true})
                ok_schema, schema_err = data.validate(pkg, PACKAGE_SCHEMA, pkg_path)
                if not ok_schema then
                    add_error(schema_err)
                    pkg = nil
                end
            end
        end
    end

    if pkg != nil then
        if pkg.src != nil and pkg.src != "" then
            src_dir = pkg.src
        end
        if pkg.entry != nil and pkg.entry != "" then
            entry_in_src = paths.joinpath(src_dir, pkg.entry)
            if not paths.file_exists(entry_in_src) and not paths.file_exists(pkg.entry) then
                add_error(pkg_path .. ": entry file '" .. pkg.entry .. "' does not exist in '" .. src_dir .. "'")
            end
        end
        if pkg.with != nil then
            for _, mod_name in ipairs(pkg.with) do
                if KNOWN_WITH_MODULES[mod_name] != true then
                    add_error(pkg_path .. ": unknown module '" .. tostring(mod_name) .. "' in with list")
                end
            end
        end
        if pkg.native != nil then
            for _, nat in ipairs(pkg.native) do
                for _, nsrc in ipairs(nat.sources) do
                    if not paths.file_exists(nsrc) then
                        add_error(pkg_path .. ": native source '" .. nsrc .. "' not found for module '" .. nat.name .. "'")
                    end
                end
            end
        end

        allow_mismatch = os.getenv("LUAM_ALLOW_MISMATCH") == "1"
        if not allow_mismatch and luam_dir != nil and git.is_repo(luam_dir) then
            if pkg.luam != nil and pkg.luam != "" then
                if not git.is_ancestor(pkg.luam, "HEAD", luam_dir) then
                    head_short = git.short_head(luam_dir)
                    add_error("luam checkout at " .. luam_dir .. " (" .. tostring(head_short) ..
                        ") does not contain required commit " .. pkg.luam .. " (from " .. pkg_path .. ")")
                end
            end
            if pkg.luam_pin != nil and pkg.luam_pin != "" then
                pin_sha = git.rev_parse(pkg.luam_pin, luam_dir)
                head_sha = git.rev_parse("HEAD", luam_dir)
                if pin_sha == nil or head_sha != pin_sha then
                    add_error("luam checkout at " .. luam_dir .. " does not match exact pin " ..
                        pkg.luam_pin .. " (set LUAM_ALLOW_MISMATCH=1 to override)")
                end
            end
        end
    end

    seen = {}
    if paths.is_dir(src_dir) then
        collect_lua_files(src_dir, src_files)
        table.sort(src_files)
        for _, f in ipairs(src_files) do
            if seen[f] != true then
                seen[f] = true
                table.insert(all_files, f)
            end
        end
    end
    if paths.is_dir("tst") then
        tst_files = {}
        collect_lua_files("tst", tst_files)
        table.sort(tst_files)
        for _, f in ipairs(tst_files) do
            if seen[f] != true then
                seen[f] = true
                table.insert(all_files, f)
            end
        end
    end
    if pkg != nil and pkg.entry != nil and pkg.entry != "" and paths.file_exists(pkg.entry) and seen[pkg.entry] != true then
        seen[pkg.entry] = true
        table.insert(all_files, pkg.entry)
    end
    table.sort(all_files)
end

-- Compile every discovered .lua file with loadfile(..., "t").
for _, file_path in ipairs(all_files) do
    if VERBOSE then
        print("Checking " .. file_path)
    end
    chunk, err = loadfile(file_path, "t")
    if chunk == nil then
        add_error(tostring(err))
    end
end

-- Verify asset.read(...) calls and referenced asset files in src/ files.
for _, src_path in ipairs(src_files) do
    source = paths.read_file(src_path)
    if source != nil then
        referenced = scan_assets_in_source(source, src_path, add_error)
        for _, relpath in ipairs(referenced) do
            if validate_asset_relpath(relpath, src_path) then
                asset_full = paths.joinpath(src_dir, relpath)
                if not paths.file_exists(asset_full) then
                    add_error("asset.read(\"" .. relpath .. "\") referenced in " .. src_path .. ", but '" .. asset_full .. "' does not exist")
                end
            end
        end
    end
end

-- Bare cross-file function call warnings across src/ files.
if #src_files > 1 then
    warn_bare_cross_file_calls(src_files)
end

if #errors > 0 then
    io.write(io.stderr, string.format("Check failed: %d error(s) across %d file(s)\n", #errors, #all_files))
    os.exit(1)
end

print(string.format("Checked %d file(s) ... OK", #all_files))
os.exit(0)
