-- Phase 1 core & library regression suite:
--   1. type(true) == "boolean" + laws.format(true) == "true"
--   2. os.execute & io.close(popen) -> (ok_bool, why, code)
--   3. bioinfo FASTA read/query/write round-trip
--   4. bcrypt hash/verify & hmac.sha256
--   5. prettyprint ANSI formatting

laws = require("laws")
bioinfo = require("bioinfo")
bcrypt = require("bcrypt")
hmac = require("hmac")
prettyprint = require("prettyprint")

-- 1. Boolean typename & laws.format
assert(type(true) == "boolean" and type(false) == "boolean", "expected type(bool) == 'boolean'")
assert(laws.format(true) == "true" and laws.format(false) == "false", "laws.format(bool) failed")

-- 2. os.execute & io.close(popen) return (ok_bool, why, code)
shell_avail = os.execute()
assert(shell_avail == true, "os.execute() with no args must return boolean true")

ok0, why0, code0 = os.execute("exit 0")
assert(ok0 == true and why0 == "exit" and code0 == 0, "os.execute('exit 0') mismatch")

ok7, why7, code7 = os.execute("exit 7")
assert(ok7 == false and why7 == "exit" and code7 == 7, "os.execute('exit 7') mismatch")

ok_sig, why_sig, code_sig = os.execute("kill -9 $$")
assert(ok_sig == false and why_sig == "signal" and code_sig == 9,
       "os.execute signal mismatch: " .. tostring(why_sig) .. "/" .. tostring(code_sig))

p_ok = io.popen("printf 'hello'; exit 0", "r")
out_ok = io.read(p_ok, "*a")
pok, pwhy, pcode = io.close(p_ok)
assert(out_ok == "hello" and pok == true and pwhy == "exit" and pcode == 0, "io.close(popen 0) mismatch")

p_fail = io.popen("printf 'err'; exit 13", "r")
out_fail = io.read(p_fail, "*a")
fok, fwhy, fcode = io.close(p_fail)
assert(out_fail == "err" and fok == false and fwhy == "exit" and fcode == 13, "io.close(popen 13) mismatch")

-- 3. bioinfo FASTA read/query/write
seqs = bioinfo.read_fasta("tst/test_seq.fasta")
assert(seqs != nil, "read_fasta returned nil")
tmp_fasta = os.tmpname()
bioinfo.write_fasta(tmp_fasta, {
    {name = "seqA", seq = string.rep("ACGT", 20)},
    {name = "seqB", seq = "TTAA"},
})
rt = bioinfo.read_fasta(tmp_fasta)
assert(rt.seqA == string.rep("ACGT", 20) and rt.seqB == "TTAA", "write_fasta/read_fasta round-trip failed")
assert(bioinfo.query_fasta(tmp_fasta, "seqB") == "TTAA", "query_fasta failed")
assert(bioinfo.query_fasta(tmp_fasta, "missing") == nil, "query_fasta missing should return nil")
os.remove(tmp_fasta)

-- 4. bcrypt & hmac
pw_hash = bcrypt.hash("correct-horse-battery-staple", 4)
assert(type(pw_hash) == "string" and string.starts_with(pw_hash, "$2b$04$"), "bcrypt.hash format mismatch")
assert(bcrypt.verify("correct-horse-battery-staple", pw_hash) == true, "bcrypt.verify valid password failed")
assert(bcrypt.verify("wrong-password", pw_hash) == false, "bcrypt.verify wrong password must return false")

digest = hmac.sha256("key", "The quick brown fox jumps over the lazy dog")
assert(digest == "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8",
       "hmac.sha256 RFC test vector mismatch: " .. tostring(digest))

-- 5. prettyprint
assert(type(prettyprint) == "table", "prettyprint module table missing")

print("PASS test_phase1.lua")
