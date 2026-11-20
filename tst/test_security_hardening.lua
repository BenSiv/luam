const t = require("test")
const sandbox = require("sandbox")
const cgi = require("cgi")
const crypto = require("crypto")

-- 1. struct / string.unpack bounds & integer overflow checks
t.run("struct bounds and integer width checks", function()
    t.throws(function() string.unpack("<s", "") end, "data string too short", "empty s unpack rejected")
    t.throws(function() string.unpack("<s", "abc") end, "data string too short", "3-byte s header rejected")
    t.throws(function() string.unpack("<s", "\x05\x00\x00\x00hi") end, "data string too short", "truncated s payload rejected")
    t.throws(function() string.unpack("!4i4", "x") end, "data string too short", "alignment padding past end rejected")
    t.throws(function() string.unpack("i0", "abcd") end, "out of range", "zero-byte integer width rejected")
    t.throws(function() string.unpack("i99999999999999999999", "abcd") end, "integral size overflow", "overflowing width rejected")
    t.throws(function() string.unpack("bc0", "\xffabc") end, "data string too short", "negative c0 dynamic length rejected")
    t.throws(function() string.unpack("<i", "abcd", 0) end, "initial position out of string", "pos 0 rejected")
    t.throws(function() string.unpack("<i", "abcd", -3) end, "initial position out of string", "negative pos rejected")
end)

-- 2. load / loadstring mode ("t", "b", "bt") and env binding
t.run("load mode and env enforcement", function()
    sample_fn = function() return 42 end
    bin_chunk = string.dump(sample_fn)

    fn_t, err_t = load(bin_chunk, "=bin", "t")
    t.eq(fn_t, nil, "load mode 't' rejects binary chunk")
    t.check(string.contains(tostring(err_t), "attempt to load a binary chunk"), "binary chunk rejection message")

    ls_t, ls_err = loadstring(bin_chunk, "=bin", "t")
    t.eq(ls_t, nil, "loadstring mode 't' rejects binary chunk")
    t.check(string.contains(tostring(ls_err), "attempt to load a binary chunk"), "loadstring binary rejection message")

    fn_b_txt, err_b_txt = load("return 42", "=txt", "b")
    t.eq(fn_b_txt, nil, "load mode 'b' rejects text chunk")
    t.check(string.contains(tostring(err_b_txt), "attempt to load a text chunk"), "text chunk rejection message")

    fn_b_ok, _ = load(bin_chunk, "=bin", "b")
    t.check(type(fn_b_ok) == "function" and fn_b_ok() == 42, "load mode 'b' accepts valid binary chunk")

    t.throws(function() load("return 1", "=x", "x") end, "invalid mode", "invalid mode character rejected")
    t.throws(function() load("return 1", "=x", "") end, "invalid mode", "empty mode rejected")

    custom_env = {magic = 99}
    fn_env, _ = load("return magic + 1", "=env", "t", custom_env)
    t.eq(fn_env(), 100, "load 4th argument binds chunk environment")
end)

-- 3. sandbox hardening: bytecode rejection, string metatable isolation, stdlib filtering, string.rep cap
t.run("sandbox security boundaries", function()
    bin_chunk = string.dump(function() return "escaped" end)
    sb_fn, sb_err = sandbox.load(bin_chunk, "untrusted_bin", sandbox.data_env())
    t.eq(sb_fn, nil, "sandbox.load rejects binary bytecode chunks")
    t.check(string.contains(tostring(sb_err), "binary chunks"), "sandbox binary error message")

    ok_run_bin, run_bin_err = sandbox.run(bin_chunk, "untrusted_bin", sandbox.data_env())
    t.eq(ok_run_bin, false, "sandbox.run rejects binary bytecode chunks")
    t.check(string.contains(tostring(run_bin_err), "binary chunks"), "sandbox.run binary error message")

    t.eq(getmetatable(""), nil, "strings have no shared global metatable")

    ok_idx, idx_err = sandbox.run("""
        return ("abc").dump
    """, "str_mt_check", sandbox.data_env())
    t.eq(ok_idx, false, "indexing a string inside sandbox fails cleanly instead of reaching host string table")
    t.check(string.contains(tostring(idx_err), "index"), "string index error message")

    ok_env, has_dangerous = sandbox.run("""
        return (string.dump != nil) or (string.pack != nil) or (string.unpack != nil)
    """, "stdlib_filter_check", sandbox.data_env())
    t.eq(ok_env, true, "stdlib check ran")
    t.eq(has_dangerous, false, "string.dump, string.pack, and string.unpack omitted from sandbox env")

    ok_rep_small, small_str = sandbox.run("""
        return string.rep("ab", 5)
    """, "rep_small", sandbox.data_env())
    t.eq(ok_rep_small, true, "small string.rep allowed")
    t.eq(small_str, "ababababab", "small string.rep output matches")

    ok_rep_big, rep_big_err = sandbox.run("""
        return string.rep("a", 10 * 1024 * 1024)
    """, "rep_big", sandbox.data_env())
    t.eq(ok_rep_big, false, "oversized string.rep blocked in sandbox")
    t.check(string.contains(tostring(rep_big_err), "maximum byte limit"), "string.rep limit error message")
end)

-- 4. Parser GC anchoring (CVE-2025-49844 regression) and large-arity vararg calls (CVE-2014-5461 regression)
t.run("parser GC anchoring and large fixed-param varargs", function()
    pieces = {"x = ", "40 + 2\n", "return x"}
    idx = 0
    function gc_stress_reader()
        collectgarbage("collect")
        idx = idx + 1
        return pieces[idx]
    end
    dyn_name = string.rep("chunk_", 20) .. tostring(12345)
    loaded_gc, gc_err = load(gc_stress_reader, dyn_name, "t")
    collectgarbage("collect")
    t.check(loaded_gc != nil, "parser survives full GC during chunkname/reader lexing: " .. tostring(gc_err))
    t.eq(loaded_gc(), 42, "GC-stressed parsed chunk returns expected value")

    params = {}
    for i = 1, 80 do
        table.insert(params, "p" .. tostring(i))
    end
    vararg_src = "return function(" .. table.concat(params, ", ") .. ", ...)\n" ..
                 "    return p1, p80, select(\"#\", ...)\n" ..
                 "end"
    make_vararg = assert(load(vararg_src, "=vararg80", "t"))
    vf = make_vararg()
    a1, a80, nextra = vf("first")
    t.eq(a1, "first", "vararg 80-param first arg")
    t.eq(a80, nil, "vararg 80-param padded nil arg")
    t.eq(nextra, 0, "vararg 80-param zero extra args")

    -- Strict boolean error at instruction 0 must report valid line info (no lineinfo[-1] underflow)
    first_if = function(v) if v then return 1 end return 0 end
    first_not = function(v) return not v end
    t.throws(function() first_if(123) end, "boolean value", "OP_TEST at pc 0 safe error")
    t.throws(function() first_not(123) end, "boolean value", "OP_NOT at pc 0 safe error")
end)

-- 5. crypto.timing_safe_equal & CGI CRLF / cookie injection guards
t.run("crypto timing_safe_equal and CGI header guards", function()
    mac1 = crypto.hmac_sha256("secret-key", "payload")
    mac2 = crypto.hmac_sha256("secret-key", "payload")
    mac3 = crypto.hmac_sha256("secret-key", "tampered")
    t.eq(crypto.timing_safe_equal(mac1, mac2), true, "identical MACs compare equal")
    t.eq(crypto.timing_safe_equal(mac1, mac3), false, "different MACs compare unequal")
    t.eq(crypto.timing_safe_equal("short", "longer"), false, "different lengths compare unequal")

    t.throws(function()
        cgi.set_cookie_header("session", "abc\r\nX-Injected: 1", 60, true)
    end, "invalid character in cookie", "CRLF in cookie value rejected")
    t.throws(function()
        cgi.set_cookie_header("session", "abc; Domain=evil.example", 60, true)
    end, "invalid character in cookie", "semicolon in cookie value rejected")
    t.throws(function()
        cgi.set_cookie_header("bad=name", "abc", 60, true)
    end, "invalid cookie name", "equals in cookie name rejected")
    t.throws(function()
        cgi.respond({status = "200 OK\r\nX-Split: 1", body = "hi"})
    end, "invalid CR/LF/NUL", "CRLF in CGI status rejected")
    t.throws(function()
        cgi.respond({headers = {["X-Test"] = "val\nInjected: 1"}, body = "hi"})
    end, "invalid CR/LF/NUL", "LF in CGI header value rejected")
end)

t.finish("test_security_hardening")
