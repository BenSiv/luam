asset = require("asset")
lfs = require("lfs")
paths = require("paths")

function expect_error(fn, substr)
    ok, err = pcall(fn)
    assert(ok == false, "expected error containing '" .. substr .. "', but call succeeded")
    assert(string.contains(tostring(err), substr),
        "expected error containing '" .. substr .. "', got: " .. tostring(err))
end

-- 1. Path validation rejects traversal, absolute paths, and malformed names.
expect_error(function() asset.read("") end, "non-empty")
expect_error(function() asset.read("/etc/passwd") end, "invalid relative path")
expect_error(function() asset.read("../secret.txt") end, "invalid relative path")
expect_error(function() asset.read("ui/../secret.txt") end, "invalid relative path")
expect_error(function() asset.read("ui//widget.js") end, "invalid relative path")
expect_error(function() asset.read("ui\\widget.js") end, "invalid relative path")
expect_error(function() asset.read("ui/") end, "invalid relative path")

-- 2. Interpreter mode resolves relative to package.path `?.lua` entries
--    and preserves raw bytes (backslashes, quotes, %, CRLF, NUL).
assert(asset.is_bundled() == false)

tmp_root = os.tmpname()
os.remove(tmp_root)
lfs.mkdir(tmp_root)
lfs.mkdir(paths.joinpath(tmp_root, "src"))
lfs.mkdir(paths.joinpath(tmp_root, "src", "ui"))

tricky_js = "var re = /(^|\\s)@([\\w-]+)$/;\nvar mod = 10 % 3;\nvar triple = \"\"\"raw\"\"\";\r\n\x00end"
f = io.open(paths.joinpath(tmp_root, "src", "ui", "widget.js"), "wb")
io.write(f, tricky_js)
io.close(f)

f_css = io.open(paths.joinpath(tmp_root, "src", "ui", "widget.css"), "wb")
io.write(f_css, "#box { width: 100%; border-radius: 50%; }\n")
io.close(f_css)

saved_path = package.path
package.path = paths.joinpath(tmp_root, "src", "?.lua") .. ";" .. package.path
asset.clear_cache()

assert(asset.read("ui/widget.js") == tricky_js)
assert(asset.read("ui/widget.css") == "#box { width: 100%; border-radius: 50%; }\n")
expect_error(function() asset.read("ui/does_not_exist.js") end, "not found")

package.path = saved_path
asset.clear_cache()

-- 3. Static build mode embeds assets into the compiled binary's .rodata,
--    ignores mentions inside comments/strings, and runs after src/ is deleted.
entry_code = """
asset = require("asset")
-- Doc comment mention should be ignored: asset.read("ui/comment_only.js")
mention = "asset.read(\\\"ui/string_only.js\\\")"
triple_mention = \"\"\"
asset.read("ui/triple_string_only.js")
\"\"\"
assert(asset.is_bundled() == true)
js = asset.read("ui/widget.js")
css = asset.read("ui/widget.css")
io.write(io.stdout, tostring(#js) .. ":" .. tostring(#css))
if string.find(js, "\\\\s", 1, true) == nil or string.byte(js, #js - 3) != 0 then
    os.exit(2)
end
"""
f_main = io.open(paths.joinpath(tmp_root, "src", "main.lua"), "wb")
io.write(f_main, entry_code)
io.close(f_main)

luam_root = lfs.currentdir()
build_cmd = "cd \"" .. tmp_root .. "\" && \"" .. paths.joinpath(luam_root, "bin", "luam") .. "\" \"" ..
    paths.joinpath(luam_root, "lib", "static", "build.lua") .. "\" --entry main.lua --bin asset_app --luamdir \"" .. luam_root .. "\" > /dev/null"
assert(os.execute(build_cmd) == 0, "static build with valid assets failed")

-- Remove src/ completely to prove zero runtime filesystem dependency.
os.remove(paths.joinpath(tmp_root, "src", "ui", "widget.js"))
os.remove(paths.joinpath(tmp_root, "src", "ui", "widget.css"))
os.remove(paths.joinpath(tmp_root, "src", "main.lua"))
lfs.rmdir(paths.joinpath(tmp_root, "src", "ui"))
lfs.rmdir(paths.joinpath(tmp_root, "src"))

out_file = paths.joinpath(tmp_root, "out.txt")
run_bin_cmd = "\"" .. paths.joinpath(tmp_root, "bin", "asset_app") .. "\" > \"" .. out_file .. "\""
assert(os.execute(run_bin_cmd) == 0, "compiled asset binary failed when src/ was removed")

out_handle = io.open(out_file, "rb")
out_text = io.read(out_handle, "*all")
io.close(out_handle)
expected_summary = tostring(#tricky_js) .. ":" .. tostring(#"#box { width: 100%; border-radius: 50%; }\n")
assert(out_text == expected_summary, "unexpected binary output: " .. tostring(out_text))

-- 4. Referencing a missing asset fails the static build at compile time.
lfs.mkdir(paths.joinpath(tmp_root, "bad_src"))
f_bad = io.open(paths.joinpath(tmp_root, "bad_src", "main.lua"), "wb")
io.write(f_bad, "asset = require(\"asset\")\nx = asset.read(\"ui/missing.js\")\n")
io.close(f_bad)

bad_build_cmd = "cd \"" .. tmp_root .. "\" && \"" .. paths.joinpath(luam_root, "bin", "luam") .. "\" \"" ..
    paths.joinpath(luam_root, "lib", "static", "build.lua") .. "\" --src bad_src --entry main.lua --bin bad_app --luamdir \"" .. luam_root .. "\" > /dev/null 2>&1"
assert(os.execute(bad_build_cmd) != 0, "static build should fail when an asset.read target does not exist")

-- 5. Non-literal asset.read(var) fails the static build at compile time
--    instead of hiding an unbundled asset until runtime.
lfs.mkdir(paths.joinpath(tmp_root, "dyn_src"))
f_dyn = io.open(paths.joinpath(tmp_root, "dyn_src", "main.lua"), "wb")
io.write(f_dyn, "asset = require(\"asset\")\np = \"ui/widget.js\"\nx = asset.read(p)\n")
io.close(f_dyn)

dyn_build_cmd = "cd \"" .. tmp_root .. "\" && \"" .. paths.joinpath(luam_root, "bin", "luam") .. "\" \"" ..
    paths.joinpath(luam_root, "lib", "static", "build.lua") .. "\" --src dyn_src --entry main.lua --bin dyn_app --luamdir \"" .. luam_root .. "\" > /dev/null 2>&1"
assert(os.execute(dyn_build_cmd) != 0, "static build should fail on non-literal asset.read(var)")

os.execute("rm -rf \"" .. tmp_root .. "\"")
print("PASS test_asset.lua")
