-- Phase 2 test suite:
--   external_tool, paths, data (+ laws), cli, crypto, vec, markdown, git,
--   test.lua, and declarative bld/package.lua (with C++ native module,
--   define_git_commit, luam ancestor check, crypto/vec preloads, and symlinks).

const cli = require("cli")
const crypto = require("crypto")
const data = require("data")
const ext = require("external_tool")
const git = require("git")
const laws = require("laws")
const lfs = require("lfs")
const markdown = require("markdown")
const paths = require("paths")
const t = require("test")
const vec = require("vec")

-- 1. test.lua self-check
t.check(true, "basic true")
t.eq({a = 1, b = {2, 3}}, {b = {2, 3}, a = 1}, "deep table eq")
t.neq({a = 1}, {a = 2}, "deep table neq")
t.throws(function() error("boom_xyz") end, "boom_xyz", "throws substring")
p_cnt, f_cnt = t.counts()
assert(p_cnt == 4 and f_cnt == 0, "test.lua counts mismatch")

-- 2. external_tool
out_ok, is_ok, code_ok = ext.exec("printf 'alpha'; printf 'beta' >&2; exit 0")
t.eq(out_ok, "alphabeta", "ext.exec combined stdout+stderr")
t.eq(is_ok, true, "ext.exec exit 0 ok")
t.eq(code_ok, 0, "ext.exec exit 0 code")

out_empty, empty_ok, empty_code = ext.exec("true")
t.eq(out_empty, "", "ext.exec silent command returns empty string")
t.eq(empty_ok, true, "ext.exec true ok")
t.eq(empty_code, 0, "ext.exec true code")

out_fail, fail_ok, fail_code = ext.exec("printf 'bad'; exit 19")
t.eq(out_fail, "bad", "ext.exec failure output")
t.eq(fail_ok, false, "ext.exec failure ok=false")
t.eq(fail_code, 19, "ext.exec failure code=19")

t.eq(ext.ok("true"), true, "ext.ok true")
t.eq(ext.ok("false"), false, "ext.ok false")
t.eq(ext.must("printf 'ok_must'", "echo"), "ok_must", "ext.must success")
t.throws(function() ext.must("printf 'err_detail'; exit 3", "step_x") end, "step_x failed", "ext.must failure")
t.eq(ext.available("sh"), true, "sh available")
t.eq(ext.available("definitely_missing_binary_99999"), false, "missing binary unavailable")

-- 3. paths
tmp_dir = os.tmpname()
os.remove(tmp_dir)
nested_dir = paths.joinpath(tmp_dir, "a", "b", "c")
ok_ens, err_ens = paths.ensure_dir(nested_dir)
t.eq(ok_ens, true, "paths.ensure_dir: " .. tostring(err_ens))
t.eq(paths.is_dir(nested_dir), true, "paths.is_dir")

atom_file = paths.joinpath(nested_dir, "state.txt")
t.eq(paths.write_atomic(atom_file, "v1"), true, "write_atomic v1")
t.eq(paths.read_file(atom_file), "v1", "read_file v1")
t.eq(paths.write_atomic(atom_file, "v2-updated"), true, "write_atomic v2")
t.eq(paths.read_file(atom_file), "v2-updated", "read_file v2")

broken_link = paths.joinpath(tmp_dir, "dangling")
ext.must("ln -s /nonexistent_target_xyz " .. ext.shell_quote(broken_link), "ln -s")
t.eq(paths.file_exists(broken_link), false, "file_exists false on broken symlink")
t.eq(paths.exists(broken_link), true, "exists true on broken symlink")

home_env = os.getenv("HOME")
if home_env != nil and home_env != "" then
    t.eq(paths.expand_home("~/foo"), home_env .. "/foo", "expand_home ~/foo")
    t.eq(paths.expand_home("~"), home_env, "expand_home ~")
end

-- 4. data (+ laws property check)
tbl_a = {}
tbl_a.zeta = 10
tbl_a.alpha = {"x", "y"}
tbl_b = {}
tbl_b.alpha = {"x", "y"}
tbl_b.zeta = 10
t.eq(data.serialize(tbl_a), data.serialize(tbl_b), "data.serialize key-order determinism")

data_path = paths.joinpath(tmp_dir, "spec.lua")
sample_spec = {
    name = "demo",
    count = 3,
    enabled = true,
    items = {"one", "two"},
    ["weird key"] = "q\"uote\nline2",
}
data.save(data_path, sample_spec, "-- auto-generated")
loaded_spec = data.load(data_path)
t.eq(loaded_spec, sample_spec, "data.save/load round-trip")
t.eq(data.load(paths.joinpath(tmp_dir, "missing.lua")), nil, "data.load nil on missing file")
t.throws(function() data.load(paths.joinpath(tmp_dir, "missing.lua"), {required = true}) end, "file not found", "data.load required")

expanded = data.expand_vars({path = "${root}/bin", list = {"${name}"}}, {root = "/opt", name = "luam"}, "spec")
t.eq(expanded, {path = "/opt/bin", list = {"luam"}}, "data.expand_vars")
t.throws(function() data.expand_vars("${nope}", {}, "env.lua") end, "unknown variable", "data.expand_vars missing")

schema = {
    fields = {
        name = "string",
        port = "number",
        tls = "boolean",
        mode = {one_of = {"home", "container"}},
        tags = {list_of = "string"},
        env = {map_of = "string"},
    },
    required = {"name", "mode"},
}
ok_v, err_v = data.validate({
    name = "app",
    port = 8080,
    tls = true,
    mode = "container",
    tags = {"a", "b"},
    env = {FOO = "bar"},
}, schema, "spec")
t.eq(ok_v, true, "data.validate valid: " .. tostring(err_v))

ok_unk, err_unk = data.validate({name = "app", mode = "home", bogus = 1}, schema, "spec")
t.eq(ok_unk, false, "data.validate rejects unknown field")
t.check(string.contains(err_unk, "unknown field 'bogus'"), "unknown field message")

ok_req, err_req = data.validate({name = "app"}, schema, "spec")
t.eq(ok_req, false, "data.validate rejects missing required")
t.check(string.contains(err_req, "missing required field 'mode'"), "missing required message")

-- Property law: arbitrary data tables round-trip through serialize -> loads
gen_leaf = laws.frequency({
    {1, laws.boolean()},
    {1, laws.int(-1000, 1000)},
    {1, laws.text({min_len = 0, max_len = 16})},
})
gen_record = laws.record({
    flag = laws.boolean(),
    num = laws.int(-500, 500),
    label = laws.text({min_len = 0, max_len = 12}),
    items = laws.list(gen_leaf, {min_len = 0, max_len = 5}),
})
laws.forall("data.serialize -> data.loads round-trip", gen_record, function(rec)
    parsed, lerr = data.loads("return " .. data.serialize(rec))
    return lerr == nil and data.serialize(parsed) == data.serialize(rec)
end, {trials = 60, seed = 42})

-- 5. cli
flag_defs = {
    {short = "n", long = "name", kind = "string", required = true, desc = "Project name"},
    {short = "c", long = "count", kind = "number", default = 1, desc = "Repeat count"},
    {short = "v", long = "verbose", kind = "boolean", desc = "Verbose mode"},
    {short = "t", long = "tag", kind = "list", desc = "Tag"},
}
f_opts, f_pos, f_err = cli.parse_flags({"--name=demo", "-c", "4", "-v", "-t", "x", "--tag", "y", "--", "-literal"}, flag_defs)
t.eq(f_err, nil, "cli.parse_flags valid")
t.eq(f_opts.name, "demo", "cli --name=demo")
t.eq(f_opts.count, 4, "cli -c 4 number")
t.eq(f_opts.verbose, true, "cli -v boolean")
t.eq(f_opts.tag, {"x", "y"}, "cli repeatable list")
t.eq(f_pos, {"-literal"}, "cli -- end of flags")

_, _, req_err = cli.parse_flags({"-v"}, flag_defs)
t.check(req_err != nil and string.contains(req_err, "--name"), "cli missing required option")

h_opts, _, h_err = cli.parse_flags({"-h"}, flag_defs)
t.eq(h_err, nil, "cli -h bypasses required check")
t.eq(h_opts.help, true, "cli -h sets help=true")

dispatched = nil
app = {
    name = "demo",
    version = "demo 1.2.3",
    no_exit = true,
    silent = true,
    help = "Usage: demo <cmd>",
    commands = {
        remote = {
            help = "Usage: demo remote add <name>",
            commands = {
                add = {
                    help = "Add a remote",
                    flags = {{short = "f", long = "force", kind = "boolean"}},
                    run = function(opts, pos)
                        dispatched = {force = opts.force, pos = pos}
                        return 0, "ok"
                    end,
                },
            },
        },
    },
}
v_code, v_msg = cli.run(app, {"--version"})
t.eq(v_code, 0, "cli --version exit 0")
t.eq(v_msg, "demo 1.2.3", "cli --version output")

r_code, _ = cli.run(app, {"remote", "add", "-f", "origin"})
t.eq(r_code, 0, "cli nested subcommand exit 0")
t.eq(dispatched, {force = true, pos = {"origin"}}, "cli nested subcommand args")

u_code, u_msg = cli.run(app, {"bogus"})
t.eq(u_code, 1, "cli unknown command exit 1")
t.check(string.contains(u_msg, "Unknown command 'bogus'"), "cli unknown command message")

-- 6. crypto
t.eq(crypto.sha256(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256 empty")
t.eq(crypto.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256 abc")
t.eq(crypto.hmac_sha256("key", "The quick brown fox jumps over the lazy dog"),
     "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8", "crypto.hmac_sha256")

big_blob = string.rep("0123456789abcdef", 1500) -- 24 KB (> 8 KB streaming buffer)
blob_file = paths.joinpath(tmp_dir, "blob.bin")
paths.write_file(blob_file, big_blob)
t.eq(crypto.sha256_file(blob_file), crypto.sha256(big_blob), "crypto.sha256_file streaming match")
nil_hash, hash_err = crypto.sha256_file(paths.joinpath(tmp_dir, "no_such_file"))
t.eq(nil_hash, nil, "sha256_file missing returns nil")
t.check(type(hash_err) == "string", "sha256_file missing returns error string")

rb1 = crypto.random_bytes(32)
rb2 = crypto.random_bytes(32)
t.check(#rb1 == 32 and rb1 != rb2, "crypto.random_bytes")
rh1 = crypto.random_hex(16)
t.check(#rh1 == 32 and string.match(rh1, "^%x+$") != nil, "crypto.random_hex")

-- 7. vec
packed_34 = vec.pack({3.0, 4.0})
t.eq(#packed_34, 8, "vec.pack 2 floats = 8 bytes")
expected_le = string.pack("<ff", 0.6, 0.8)
t.eq(packed_34, expected_le, "vec.pack matches string.pack('<ff') byte-for-byte")
unpacked_34 = vec.unpack(packed_34)
t.check(math.abs(unpacked_34[1] - 0.6) < 1e-6 and math.abs(unpacked_34[2] - 0.8) < 1e-6, "vec.unpack")

packed_ortho = vec.pack({-4.0, 3.0})
t.check(math.abs(vec.dot_packed(packed_34, packed_ortho)) < 1e-6, "vec.dot_packed orthogonal ~ 0")
t.check(math.abs(vec.dot_packed(packed_34, packed_34) - 1.0) < 1e-6, "vec.dot_packed unit self ~ 1")

raw_a = vec.pack_raw({2.0, 0.0, 0.0})
raw_b = vec.pack_raw({5.0, 0.0, 0.0})
t.check(math.abs(vec.cosine_packed(raw_a, raw_b) - 1.0) < 1e-6, "vec.cosine_packed parallel = 1")
t.check(math.abs(vec.cosine({2.0, 0.0}, {0.0, 3.0})) < 1e-6, "vec.cosine orthogonal = 0")
t.eq(vec.pack({0.0, 0.0}), nil, "vec.pack zero vector -> nil")
t.eq(vec.unpack("abc"), nil, "vec.unpack non-multiple-of-4 -> nil")
t.eq(vec.hex_literal("\x00\xff\x1a"), "X'00ff1a'", "vec.hex_literal")
u_trunc = vec.unit({3.0, 4.0, 99.0}, 2)
t.check(#u_trunc == 2 and math.abs(u_trunc[1] - 0.6) < 1e-6, "vec.unit dims truncation")

-- 8. markdown
rendered_one = markdown.render("Hello **world** <script>alert(1)</script>")
t.check(string.contains(rendered_one, "world"), "markdown.render text")
t.check(not string.contains(rendered_one, "<script>"), "markdown.render strips raw HTML/script")

batch_out = markdown.render_many({
    "First **item**",
    "Contains LUAMMD5E9C2A1B8F sentinel inline",
    "| A | B |\n|---|---|\n| 1 | 2 |",
})
t.eq(#batch_out, 3, "markdown.render_many count")
t.check(string.contains(batch_out[2], "LUAMMD5E9C2A1B8F"), "markdown.render_many sentinel collision avoidance")

-- 9. git
repo_dir = paths.joinpath(tmp_dir, "git_repo")
paths.ensure_dir(repo_dir)
t.eq(git.is_repo(repo_dir), false, "git.is_repo false before init")
ext.must("git -C " .. ext.shell_quote(repo_dir) .. " init -b main", "git init")
ext.must("git -C " .. ext.shell_quote(repo_dir) .. " config user.email test@example.com", "git email")
ext.must("git -C " .. ext.shell_quote(repo_dir) .. " config user.name Test", "git name")
paths.write_file(paths.joinpath(repo_dir, "a.txt"), "one\n")
ext.must("git -C " .. ext.shell_quote(repo_dir) .. " add a.txt && git -C " .. ext.shell_quote(repo_dir) .. " commit -m first", "commit 1")
sha1 = git.rev_parse("HEAD", repo_dir)
t.check(sha1 != nil and #sha1 == 40, "git.rev_parse 40-hex SHA")
t.eq(git.is_clean(repo_dir), true, "git.is_clean on clean tree")
t.eq(git.current_branch(repo_dir), "main", "git.current_branch main")

paths.write_file(paths.joinpath(repo_dir, "a.txt"), "two\n")
t.eq(git.is_clean(repo_dir), false, "git.is_clean false on modified tracked file")
ext.must("git -C " .. ext.shell_quote(repo_dir) .. " commit -am second", "commit 2")
sha2 = git.rev_parse("HEAD", repo_dir)
t.eq(git.is_ancestor(sha1, sha2, repo_dir), true, "git.is_ancestor sha1 -> sha2")
t.eq(git.is_ancestor(sha2, sha1, repo_dir), false, "git.is_ancestor sha2 -> sha1 false")

clone_dir = paths.joinpath(tmp_dir, "git_clone")
ok_cl, _ = git.clone(repo_dir, clone_dir)
t.eq(ok_cl, true, "git.clone local repo")
t.eq(git.rev_parse("HEAD", clone_dir), sha2, "git.clone HEAD matches")

-- 10. Declarative bld/package.lua + C++ native extension + define_git_commit + symlinks
luam_root = lfs.currentdir()
luam_head = git.rev_parse("HEAD", luam_root)
pkg_proj = paths.joinpath(tmp_dir, "pkg_app")
paths.ensure_dir(paths.joinpath(pkg_proj, "src"))
paths.ensure_dir(paths.joinpath(pkg_proj, "bld"))
ext.must("git -C " .. ext.shell_quote(pkg_proj) .. " init -b main", "pkg git init")
ext.must("git -C " .. ext.shell_quote(pkg_proj) .. " config user.email test@example.com && git -C " .. ext.shell_quote(pkg_proj) .. " config user.name Test", "pkg git cfg")

paths.write_file(paths.joinpath(pkg_proj, "src", "native_add.cpp"), """
#include <vector>
extern "C" {
#include "lua.h"
#include "lauxlib.h"
}

static int l_sum3(lua_State *L) {
    std::vector<int> xs = {luaL_checkint(L, 1), luaL_checkint(L, 2), luaL_checkint(L, 3)};
    int total = 0;
    for (int v : xs) total += v;
    lua_pushinteger(L, total);
    return 1;
}

extern "C" int luaopen_native_add(lua_State *L) {
    static const luaL_Reg fns[] = {{"sum3", l_sum3}, {NULL, NULL}};
    lua_newtable(L);
    luaL_register(L, NULL, fns);
    return 1;
}
""")

paths.write_file(paths.joinpath(pkg_proj, "src", "main.lua"), """
const commit = require("build_commit")
const crypto = require("crypto")
const vec = require("vec")
const native = require("ext.native_add")

p = vec.pack({3.0, 4.0})
d = math.floor(vec.dot_packed(p, p) * 100 + 0.5)
h = string.sub(crypto.sha256("abc"), 1, 8)
s = native.sum3(10, 20, 12)
io.write(string.format("%s|%d|%s|%d", commit, d, h, s))
""")

paths.write_file(paths.joinpath(pkg_proj, "bld", "package.lua"), string.format("""
return {
    bin = "pkg_app",
    entry = "main.lua",
    luam = %q,
    with = {"crypto", "vec"},
    define_git_commit = "build_commit",
    symlinks = {"pkg_alias"},
    native = {
        {
            name = "ext.native_add",
            luaopen = "luaopen_native_add",
            sources = {"src/native_add.cpp"},
            cxx = true,
        },
    },
}
""", luam_head))

ext.must("git -C " .. ext.shell_quote(pkg_proj) .. " add -A && git -C " .. ext.shell_quote(pkg_proj) .. " commit -m v0", "pkg commit")
expected_commit = git.describe(pkg_proj)

build_cmd = "cd " .. ext.shell_quote(pkg_proj) .. " && LUAM_DIR=" .. ext.shell_quote(luam_root) ..
    " " .. ext.shell_quote(paths.joinpath(luam_root, "bin", "luam")) ..
    " " .. ext.shell_quote(paths.joinpath(luam_root, "lib", "static", "build.lua"))
_, b_ok, _ = ext.exec(build_cmd)
t.eq(b_ok, true, "declarative bld/package.lua build succeeded")
t.eq(paths.file_exists(paths.joinpath(pkg_proj, "src", "build_commit.lua")), false, "define_git_commit must not dirty src/")

-- Delete src/ and bld/ completely and invoke via the generated symlink!
ext.must("rm -rf " .. ext.shell_quote(paths.joinpath(pkg_proj, "src")) .. " " .. ext.shell_quote(paths.joinpath(pkg_proj, "bld")), "rm src/bld")
bin_out, bin_ok, _ = ext.exec(ext.shell_quote(paths.joinpath(pkg_proj, "bin", "pkg_alias")))
t.eq(bin_ok, true, "compiled pkg_alias binary ran standalone")
t.eq(bin_out, expected_commit .. "|100|ba7816bf|42", "pkg_alias output verified commit + vec + crypto + C++ native")

-- Verify unreachable luam commit fails static/build.lua cleanly
bad_proj = paths.joinpath(tmp_dir, "bad_luam_floor")
paths.ensure_dir(paths.joinpath(bad_proj, "src"))
paths.ensure_dir(paths.joinpath(bad_proj, "bld"))
paths.write_file(paths.joinpath(bad_proj, "src", "main.lua"), "print(1)\n")
paths.write_file(paths.joinpath(bad_proj, "bld", "package.lua"), """
return {
    bin = "bad_floor",
    entry = "main.lua",
    luam = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
}
""")
bad_out, bad_ok, _ = ext.exec("cd " .. ext.shell_quote(bad_proj) .. " && LUAM_DIR=" .. ext.shell_quote(luam_root) ..
    " " .. ext.shell_quote(paths.joinpath(luam_root, "bin", "luam")) ..
    " " .. ext.shell_quote(paths.joinpath(luam_root, "lib", "static", "build.lua")))
t.eq(bad_ok, false, "unreachable luam floor commit must fail build")
t.check(string.contains(bad_out, "does not contain required commit"), "clear luam floor failure message")

ext.must("rm -rf " .. ext.shell_quote(tmp_dir), "cleanup tmp_dir")
t.finish("test_phase2.lua")
