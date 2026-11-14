-- Static/dev asset loader for non-Lua text and binary files (JS, CSS,
-- HTML shells, prompts) kept alongside Lua modules under src/.
--
-- Two execution modes behind one call (`asset.read("ui/widget.js")`):
--   1. Static binary (built by lib/static/build.lua): build.lua scans
--      reachable modules for literal `asset.read("...")` calls, reads
--      each file from --src at build time, and compiles them into an
--      embedded `_bundled_assets` module inside the binary's .rodata.
--      Runtime lookup is an in-memory table read with zero disk I/O and
--      zero loose files to deploy alongside the binary.
--   2. Interpreter mode (`luam` running unit tests or a source entry
--      point directly): `_bundled_assets` is absent, so `asset.read`
--      resolves the relative path against each `?.lua` root on
--      `package.path` (e.g. `./src/?.lua` -> `./src/<relpath>`) and
--      caches the raw bytes in memory.
--
-- Arguments to `asset.read` must be literal relative paths ("ui/foo.js")
-- so static builds can discover and verify every asset at compile time,
-- matching `require("...")`'s own static-reachability rule in build.lua.

asset = {}

has_bundled, bundled_table = pcall(require, "_bundled_assets")
IS_BUNDLED = (has_bundled == true and type(bundled_table) == "table")
DISK_CACHE = {}

function validate_relpath(relpath)
    if type(relpath) != "string" or relpath == "" then
        error("asset.read: path must be a non-empty string")
    end
    if string.starts_with(relpath, "/") or string.ends_with(relpath, "/") or
       string.contains(relpath, "\\") or string.contains(relpath, "//") then
        error("asset.read: invalid relative path \"" .. relpath .. "\"")
    end
    for _, part in ipairs(string.split(relpath, "/")) do
        if part == "" or part == "." or part == ".." then
            error("asset.read: invalid relative path \"" .. relpath .. "\"")
        end
    end
end

function search_roots()
    roots = {}
    seen = {}
    for _, entry in ipairs(string.split(package.path, ";")) do
        prefix, matched = string.strip_suffix(entry, "?.lua")
        if matched and seen[prefix] != true then
            seen[prefix] = true
            table.insert(roots, prefix)
        end
    end
    return roots
end

function asset.is_bundled()
    return IS_BUNDLED
end

function asset.clear_cache()
    DISK_CACHE = {}
end

function asset.read(relpath)
    validate_relpath(relpath)
    if IS_BUNDLED then
        content = bundled_table[relpath]
        if content == nil then
            error("asset.read: \"" .. relpath .. "\" not found in static bundle")
        end
        return content
    end

    cached = DISK_CACHE[relpath]
    if cached != nil then
        return cached
    end

    for _, root in ipairs(search_roots()) do
        file = io.open(root .. relpath, "rb")
        if file != nil then
            content = io.read(file, "*all")
            io.close(file)
            if content == nil then
                content = ""
            end
            DISK_CACHE[relpath] = content
            return content
        end
    end

    error("asset.read: \"" .. relpath .. "\" not found along package.path")
end

return asset
