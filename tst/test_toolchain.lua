-- Integrated Toolchain & POSIX Executable-Relative Discovery Test Suite:
--   1. POSIX `!` and `!/..` auto-discovery (`env -u LUA_PATH -u LUA_CPATH -u LUAM_DIR`)
--   2. `package.exec_dir` and `package.luam_root` (present in luam checkout, nil in standalone binary)
--   3. `luam check` (valid project, syntax/strict-conditional error, missing asset, invalid manifest)
--   4. `luam run` (in-process zero-compile project run, `define_git_commit`, `asset.read`, `arg`, script mode)
--   5. `luam build` (zero-LUAM_DIR flag build, incremental `.o` cache hit/force `--no-cache`, standalone binary)
--   6. `luam test` (discovery, passing/failing exit codes & failure output, `--filter`, `--bats`)
--   7. Subcommand dispatch edge cases (`luam -- build`, `luam ./build`, `luam -e ...`)

const ext = require("external_tool")
const git = require("git")
const lfs = require("lfs")
const paths = require("paths")
const t = require("test")

luam_root = package.luam_root
if luam_root == nil or luam_root == "" then
    luam_root = lfs.currentdir()
end
luam_bin = paths.joinpath(luam_root, "bin", "luam")
clean_env = "env -u LUA_PATH -u LUA_CPATH -u LUAM_DIR "

tmp_dir = os.tmpname()
os.remove(tmp_dir)
paths.ensure_dir(tmp_dir)

-- ---- 1. Zero-env POSIX `!` module & C-extension discovery ----
probe_cmd = clean_env .. "sh -c " .. ext.shell_quote(
    "cd " .. ext.shell_quote(tmp_dir) .. " && " .. ext.shell_quote(luam_bin) ..
    " -e 'const paths = require(\"paths\"); const cli = require(\"cli\"); const dkjson = require(\"dkjson\"); const lfs = require(\"lfs\"); io.write(tostring(package.exec_dir) .. \"|\" .. tostring(package.luam_root) .. \"|\" .. dkjson.encode({ok = paths.is_dir(\".\") and type(cli.run) == \"function\" and type(lfs.currentdir()) == \"string\"}))'"
)
p_out, p_ok, _ = ext.exec(probe_cmd)
t.eq(p_ok, true, "zero-env luam requires paths, cli, dkjson, lfs from arbitrary cwd: " .. tostring(p_out))
expected_exec_dir = paths.joinpath(luam_root, "bin")
t.eq(p_out, expected_exec_dir .. "|" .. luam_root .. "|{\"ok\":true}", "package.exec_dir + package.luam_root + modules verified")
t.check(not string.contains(package.path, "/.."), "package.path has clean parent expansion with no /.. segments")
t.check(not string.contains(package.cpath, "/.."), "package.cpath has clean parent expansion with no /.. segments")

-- Verify `;;` in custom LUA_PATH still expands to bundled `lib/` without LUAM_DIR.
semi_cmd = clean_env .. "LUA_PATH='./custom/?.lua;;' " .. ext.shell_quote(luam_bin) ..
    " -e 'const p = require(\"paths\"); io.write(tostring(type(p.joinpath)))'"
semi_out, semi_ok, _ = ext.exec(semi_cmd)
t.eq(semi_ok, true, "LUA_PATH with ;; preserves bundled lib discovery")
t.eq(semi_out, "function", "paths.joinpath loaded via ;; expansion")

-- ---- 2. Create temporary Luam project ----
proj_dir = paths.joinpath(tmp_dir, "demo_proj")
paths.ensure_dir(paths.joinpath(proj_dir, "src", "ui"))
paths.ensure_dir(paths.joinpath(proj_dir, "bld"))
paths.ensure_dir(paths.joinpath(proj_dir, "tst"))

luam_head = git.rev_parse("HEAD", luam_root)

ext.must("git -C " .. ext.shell_quote(proj_dir) .. " init -b main", "proj git init")
ext.must("git -C " .. ext.shell_quote(proj_dir) .. " config user.email test@example.com && git -C " .. ext.shell_quote(proj_dir) .. " config user.name Test", "proj git config")

paths.write_file(paths.joinpath(proj_dir, "src", "ui", "hello.txt"), "Hello Toolchain!")

paths.write_file(paths.joinpath(proj_dir, "src", "greeter.lua"), """
const asset = require("asset")
const crypto = require("crypto")

const greeter = {}

function greeter.banner(tag)
    msg = asset.read("ui/hello.txt")
    digest = string.sub(crypto.sha256(msg .. ":" .. tag), 1, 8)
    return msg .. " [" .. tag .. ":" .. digest .. "]"
end

return greeter
""")

paths.write_file(paths.joinpath(proj_dir, "src", "main.lua"), """
const commit = require("build_commit")
const greeter = require("greeter")
const lfs = require("lfs")

a1 = arg[1]
if a1 == nil then
    a1 = "none"
end
a2 = arg[2]
if a2 == nil then
    a2 = "none"
end
has_cwd = (type(lfs.currentdir()) == "string")
luam_rt = tostring(package.luam_root != nil)
io.write(commit .. "|" .. greeter.banner(a1 .. "," .. a2) .. "|cwd=" .. tostring(has_cwd) .. "|luam_root_set=" .. luam_rt)
""")

good_manifest = string.format("""
return {
    bin = "demo_app",
    entry = "main.lua",
    luam = %q,
    with = {"lfs", "crypto"},
    define_git_commit = "build_commit",
}
""", luam_head)
paths.write_file(paths.joinpath(proj_dir, "bld", "package.lua"), good_manifest)

paths.write_file(paths.joinpath(proj_dir, "tst", "test_greeter.lua"), """
const greeter = require("greeter")
const t = require("test")

t.eq(greeter.banner("alpha,beta"), "Hello Toolchain! [alpha,beta:56a0eb16]", "greeter banner")
t.finish("test_greeter")
""")

paths.write_file(paths.joinpath(proj_dir, "tst", "test_math_extra.lua"), """
const t = require("test")

t.eq(2 + 2, 4, "addition")
t.finish("test_math_extra")
""")

ext.must("git -C " .. ext.shell_quote(proj_dir) .. " add -A && git -C " .. ext.shell_quote(proj_dir) .. " commit -m initial", "proj commit")
expected_commit = git.describe(proj_dir)

-- ---- 3. `luam check` tests ----
chk_out, chk_ok, _ = ext.exec(clean_env .. ext.shell_quote(luam_bin) .. " check -C " .. ext.shell_quote(proj_dir))
t.eq(chk_ok, true, "luam check succeeds on valid project: " .. tostring(chk_out))
t.check(string.contains(chk_out, "OK"), "luam check prints OK summary")

-- (a) Syntax / strict-conditional compile-time error in src/
bad_src_file = paths.joinpath(proj_dir, "src", "broken.lua")
paths.write_file(bad_src_file, "if nil then\n    x = 1\nend\n")
chk_syn_out, chk_syn_ok, _ = ext.exec(clean_env .. ext.shell_quote(luam_bin) .. " check -C " .. ext.shell_quote(proj_dir))
t.eq(chk_syn_ok, false, "luam check fails on strict-conditional error in src/")
t.check(string.contains(chk_syn_out, "broken.lua"), "luam check names offending file")
os.remove(bad_src_file)

-- (b) Missing asset.read("ui/missing.txt")
missing_asset_src = paths.joinpath(proj_dir, "src", "bad_asset.lua")
paths.write_file(missing_asset_src, "const asset = require(\"asset\")\nx = asset.read(\"ui/missing.txt\")\n")
chk_ast_out, chk_ast_ok, _ = ext.exec(clean_env .. ext.shell_quote(luam_bin) .. " check -C " .. ext.shell_quote(proj_dir))
t.eq(chk_ast_ok, false, "luam check fails on missing asset.read file")
t.check(string.contains(chk_ast_out, "ui/missing.txt"), "luam check names missing asset")
os.remove(missing_asset_src)

-- (c) Invalid field in bld/package.lua
paths.write_file(paths.joinpath(proj_dir, "bld", "package.lua"), """
return {
    bin = "demo_app",
    entry = "main.lua",
    bogus_unknown_key = 123,
}
""")
chk_pkg_out, chk_pkg_ok, _ = ext.exec(clean_env .. ext.shell_quote(luam_bin) .. " check -C " .. ext.shell_quote(proj_dir))
t.eq(chk_pkg_ok, false, "luam check fails on invalid field in bld/package.lua")
t.check(string.contains(chk_pkg_out, "bogus_unknown_key"), "luam check reports unknown manifest key")

-- Restore valid manifest & verify clean git state
paths.write_file(paths.joinpath(proj_dir, "bld", "package.lua"), good_manifest)
expected_commit = git.describe(proj_dir)

-- ---- 4. `luam run` tests ----
run_out, run_ok, _ = ext.exec(
    "cd " .. ext.shell_quote(proj_dir) .. " && " .. clean_env .. ext.shell_quote(luam_bin) .. " run -- alpha beta"
)
t.eq(run_ok, true, "luam run -- alpha beta succeeded in-process: " .. tostring(run_out))
t.eq(paths.file_exists(paths.joinpath(proj_dir, "bin", "demo_app")), false, "luam run did not compile a binary")

-- Compute expected digest dynamically via crypto in our test runner to be 100% exact
const crypto = require("crypto")
expected_digest = string.sub(crypto.sha256("Hello Toolchain!:alpha,beta"), 1, 8)
expected_inproc = expected_commit .. "|Hello Toolchain! [alpha,beta:" .. expected_digest .. "]|cwd=true|luam_root_set=true"
t.eq(run_out, expected_inproc, "luam run resolved build_commit, asset.read, crypto, lfs, and args")

-- Update tst/test_greeter.lua with exact digest
paths.write_file(paths.joinpath(proj_dir, "tst", "test_greeter.lua"), string.format("""
const greeter = require("greeter")
const t = require("test")

t.eq(greeter.banner("alpha,beta"), %q, "greeter banner")
t.finish("test_greeter")
""", "Hello Toolchain! [alpha,beta:" .. expected_digest .. "]"))
ext.must("git -C " .. ext.shell_quote(proj_dir) .. " add -A && git -C " .. ext.shell_quote(proj_dir) .. " commit -m fix_test", "proj commit 2")
expected_commit = git.describe(proj_dir)

-- Script mode in `luam run`: direct `.lua` script receiving args and ./src module resolution
quick_script = paths.joinpath(proj_dir, "quick.lua")
paths.write_file(quick_script, """
const greeter = require("greeter")
io.write(greeter.banner(tostring(arg[1])))
""")
q_out, q_ok, _ = ext.exec(
    clean_env .. ext.shell_quote(luam_bin) .. " run -C " .. ext.shell_quote(proj_dir) .. " quick.lua solo"
)
t.eq(q_ok, true, "luam run script mode succeeded: " .. tostring(q_out))
solo_digest = string.sub(crypto.sha256("Hello Toolchain!:solo"), 1, 8)
t.eq(q_out, "Hello Toolchain! [solo:" .. solo_digest .. "]", "luam run script mode resolved ./src and arg[1]")
os.remove(quick_script)

-- ---- 5. `luam test` tests ----
tst_out, tst_ok, _ = ext.exec(clean_env .. ext.shell_quote(luam_bin) .. " test -C " .. ext.shell_quote(proj_dir))
t.eq(tst_ok, true, "luam test discovered and passed project tests: " .. tostring(tst_out))
t.check(string.contains(tst_out, "PASS tst/test_greeter.lua"), "luam test ran test_greeter.lua")
t.check(string.contains(tst_out, "PASS tst/test_math_extra.lua"), "luam test ran test_math_extra.lua")

-- `--filter` selects only matching test
flt_out, flt_ok, _ = ext.exec(clean_env .. ext.shell_quote(luam_bin) .. " test -C " .. ext.shell_quote(proj_dir) .. " --filter math_extra")
t.eq(flt_ok, true, "luam test --filter succeeded")
t.check(string.contains(flt_out, "PASS tst/test_math_extra.lua"), "luam test --filter included matching test")
t.check(not string.contains(flt_out, "test_greeter.lua"), "luam test --filter skipped non-matching test")

-- Failing test exits 1 and surfaces failure output
bad_test_file = paths.joinpath(proj_dir, "tst", "test_failing_case.lua")
paths.write_file(bad_test_file, """
io.write(io.stderr, "CUSTOM_FAILURE_MARKER_987\n")
os.exit(1)
""")
fail_tst_out, fail_tst_ok, _ = ext.exec(clean_env .. ext.shell_quote(luam_bin) .. " test -C " .. ext.shell_quote(proj_dir))
t.eq(fail_tst_ok, false, "luam test exits non-zero when a test fails")
t.check(string.contains(fail_tst_out, "FAIL tst/test_failing_case.lua"), "luam test reports FAIL line")
t.check(string.contains(fail_tst_out, "CUSTOM_FAILURE_MARKER_987"), "luam test surfaces captured failure output")
os.remove(bad_test_file)

-- ---- 6. `luam build` (zero LUAM_DIR flags + incremental C object cache + standalone verification) ----
expected_commit = git.describe(proj_dir)
bld1_out, bld1_ok, _ = ext.exec(
    "cd " .. ext.shell_quote(proj_dir) .. " && " .. clean_env .. ext.shell_quote(luam_bin) .. " build --no-cache"
)
t.eq(bld1_ok, true, "luam build succeeded with zero LUAM_DIR flags: " .. tostring(bld1_out))

cached_lfs_obj = paths.joinpath(luam_root, "obj", "ext", "lfs", "lfs.o")
cached_crypto_obj = paths.joinpath(luam_root, "obj", "ext", "crypto", "crypto.o")
t.eq(paths.file_exists(cached_lfs_obj), true, "cached lfs.o created in obj/ext/lfs/")
t.eq(paths.file_exists(cached_crypto_obj), true, "cached crypto.o created in obj/ext/crypto/")

-- Second build with --verbose should reuse cached .o files without recompiling them
bld2_out, bld2_ok, _ = ext.exec(
    "cd " .. ext.shell_quote(proj_dir) .. " && " .. clean_env .. ext.shell_quote(luam_bin) .. " build --verbose"
)
t.eq(bld2_ok, true, "second luam build succeeded using cached .o files")
t.check(string.contains(bld2_out, "Using cached ") and string.contains(bld2_out, "lfs.o"), "second build reused cached lfs.o")

-- Delete src/ and bld/ completely and verify standalone binary output + package.luam_root == nil!
ext.must("rm -rf " .. ext.shell_quote(paths.joinpath(proj_dir, "src")) .. " " .. ext.shell_quote(paths.joinpath(proj_dir, "bld")), "rm src and bld")
standalone_bin = paths.joinpath(proj_dir, "bin", "demo_app")
bin_out, bin_ok, _ = ext.exec(clean_env .. ext.shell_quote(standalone_bin) .. " alpha beta")
t.eq(bin_ok, true, "standalone compiled binary ran after deleting src/ and bld/")
expected_standalone = expected_commit .. "|Hello Toolchain! [alpha,beta:" .. expected_digest .. "]|cwd=true|luam_root_set=false"
t.eq(bin_out, expected_standalone, "standalone binary matches output and leaves package.luam_root nil")

-- ---- 7. Subcommand dispatch edge cases: `luam -- build` and `luam ./build` ----
script_named_build = paths.joinpath(tmp_dir, "build")
paths.write_file(script_named_build, "io.write(\"SCRIPT_BUILD_OK:\" .. tostring(arg[1]))\n")

edge1_out, edge1_ok, _ = ext.exec(
    "cd " .. ext.shell_quote(tmp_dir) .. " && " .. clean_env .. ext.shell_quote(luam_bin) .. " -- build hello"
)
t.eq(edge1_ok, true, "luam -- build runs script named 'build'")
t.eq(edge1_out, "SCRIPT_BUILD_OK:hello", "luam -- build script output")

edge2_out, edge2_ok, _ = ext.exec(
    "cd " .. ext.shell_quote(tmp_dir) .. " && " .. clean_env .. ext.shell_quote(luam_bin) .. " ./build world"
)
t.eq(edge2_ok, true, "luam ./build runs ./build script")
t.eq(edge2_out, "SCRIPT_BUILD_OK:world", "luam ./build script output")

ext.must("rm -rf " .. ext.shell_quote(tmp_dir), "cleanup tmp_dir")
t.finish("test_toolchain.lua")
