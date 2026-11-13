print("Testing strings, strict escapes, and plain-text string.* helpers...")

function assert_compile_error(src, label)
    fn, err = load(src, "=(" .. label .. ")")
    assert(fn == nil, "expected compile error for " .. label .. ", but compiled cleanly: " .. src)
    assert(type(err) == "string" and #err > 0, "expected error message for " .. label)
end

function assert_table_eq(actual, expected, label)
    assert(#actual == #expected, label .. ": length mismatch: got " .. #actual .. ", expected " .. #expected)
    for i = 1, #expected do
        assert(actual[i] == expected[i],
            label .. ": item " .. i .. " mismatch: got " .. string.format("%q", tostring(actual[i])) ..
            ", expected " .. string.format("%q", tostring(expected[i])))
    end
end

-- ============================================================================
-- 1. Single-line "..." valid escapes
-- ============================================================================

assert(string.byte("\a") == 7)
assert(string.byte("\b") == 8)
assert(string.byte("\f") == 12)
assert(string.byte("\n") == 10)
assert(string.byte("\r") == 13)
assert(string.byte("\t") == 9)
assert(string.byte("\v") == 11)
assert("\\" == string.char(92))
assert("\"" == string.char(34))
assert("\'" == "'")
assert("'" == string.char(39))

-- \0 NUL escape (valid when not followed by 0-9)
nul = "a\0b\0"
assert(#nul == 4)
b1, b2, b3, b4 = string.byte(nul, 1, 4)
assert(b1 == 97 and b2 == 0 and b3 == 98 and b4 == 0)
assert(#"\0a" == 2 and string.byte("\0a", 1) == 0 and string.byte("\0a", 2) == 97)

-- \xXX exact 2-digit hex escapes
assert("\x00" == "\0")
assert(string.byte("\x1B") == 27)
assert(string.byte("\x1b") == 27)
assert(string.byte("\xFF") == 255)
assert(#"\x007" == 2 and string.byte("\x007", 1) == 0 and string.byte("\x007", 2) == 55)
assert(#"\x00f" == 2 and string.byte("\x00f", 1) == 0 and string.byte("\x00f", 2) == 102)

-- \u{...} UTF-8 escapes across 1, 2, 3, and 4 byte boundaries
assert("\u{0}" == "\x00")
assert("\u{41}" == "A")
assert("\u{7F}" == "\x7F")
assert("\u{80}" == "\xC2\x80")
assert("\u{00A0}" == "\xC2\xA0")
assert("\u{7FF}" == "\xDF\xBF")
assert("\u{800}" == "\xE0\xA0\x80")
assert("\u{2122}" == "\xE2\x84\xA2")
assert("\u{FEFF}" == "\xEF\xBB\xBF")
assert("\u{FFFF}" == "\xEF\xBF\xBF")
assert("\u{10000}" == "\xF0\x90\x80\x80")
assert("\u{1F600}" == "\xF0\x9F\x98\x80")
assert("\u{10FFFF}" == "\xF4\x8F\xBF\xBF")

-- \<newline> and \z whitespace skip
escaped_nl = "line1\
line2"
assert(escaped_nl == "line1\nline2")

skipped_ws = "hello \z
    	  
   world"
assert(skipped_ws == "hello world")

-- Verify line number tracking across \z with multiple newlines
fn_line, err_line = load("a = \"x\\z\n\n\ny\"\n@", "=(linetest)")
assert(fn_line == nil)
assert(string.contains(err_line, ":5:"), "expected error on line 5, got: " .. tostring(err_line))

-- ============================================================================
-- 2. Multiline """...""" literals (100% literal line 1 + shared \ escapes)
-- ============================================================================

assert("""""" == "")
assert("""hello""" == "hello")

raw_block = """
first line
    second line    
"""
assert(raw_block == "\nfirst line\n    second line    \n")

-- Inner 1 and 2 quotes unescaped; 3 quotes and trailing quote escaped
assert("""say "hi" and "" ok""" == "say \"hi\" and \"\" ok")
assert("""say "hi\"""" == "say \"hi\"")
assert("""say \"hi\"""" == "say \"hi\"")
assert("""a \"\"\" b""" == "a \"\"\" b")
assert("""""\"""" == "\"\"\"")

-- Shared escapes inside """..."""
triple_esc = """\x1B[\u{2122}]\0\t\\"""
assert(triple_esc == "\x1B[\u{2122}]\0\t\\")

triple_z = """\z
first line
second line"""
assert(triple_z == "first line\nsecond line")

-- CRLF normalization of raw newlines inside """..."""
crlf_fn = assert(load("return \"\"\"\r\na\r\nb\r\n\"\"\""))
assert(crlf_fn() == "\na\nb\n")

-- ============================================================================
-- 3. Compile-time rejections (single quotes & invalid escapes)
-- ============================================================================

assert_compile_error("s = 'hello'", "single-quoted string")
assert_compile_error("s = ''", "empty single-quoted string")
assert_compile_error("s = 'a'", "single-quoted char")

assert_compile_error("s = \"unterminated\n\"", "raw LF in single-line string")
assert_compile_error("s = \"unterminated\r\"", "raw CR in single-line string")
assert_compile_error("s = \"eof", "unfinished single-line string")
assert_compile_error("s = \"eof\\", "unfinished escape at EOF")
assert_compile_error("s = \"\"\"eof", "unfinished triple-quoted string")
assert_compile_error("s = \"\"\"say \"hi\"\"\"\"", "4 unescaped closing quotes")

-- Unknown escapes rejected in both "..." and """..."""
for _, bad in ipairs({"\\d", "\\s", "\\w", "\\/", "\\q", "\\?", "\\e"}) do
    assert_compile_error("s = \"" .. bad .. "\"", "unknown escape " .. bad .. " in quotes")
    assert_compile_error("s = \"\"\"" .. bad .. "\"\"\"", "unknown escape " .. bad .. " in triple quotes")
end

-- Legacy decimal escapes rejected (including \0 followed by digit)
for _, dec in ipairs({"\\1", "\\9", "\\27", "\\00", "\\07", "\\027", "\\127", "\\255"}) do
    assert_compile_error("s = \"" .. dec .. "\"", "decimal escape " .. dec .. " in quotes")
    assert_compile_error("s = \"\"\"" .. dec .. "\"\"\"", "decimal escape " .. dec .. " in triple quotes")
end

-- Malformed \x and \u{...} escapes rejected
for _, bad_hex in ipairs({"\\x", "\\x4", "\\xGG", "\\x1G", "\\u", "\\u0041", "\\u{}", "\\u{G}", "\\u{1234", "\\u{110000}", "\\u{1234567}"}) do
    assert_compile_error("s = \"" .. bad_hex .. "\"", "malformed hex/unicode escape " .. bad_hex)
end

-- ============================================================================
-- 4. string.format("%q", s) binary round-trip
-- ============================================================================

all_bytes = {}
for b = 0, 255 do
    table.insert(all_bytes, string.char(b))
end
table.insert(all_bytes, "\0" .. "0")
table.insert(all_bytes, "\0" .. "7")
table.insert(all_bytes, "\0" .. "f")
table.insert(all_bytes, "\r\n\"\\")
binary_blob = table.concat(all_bytes)
quoted = string.format("%q", binary_blob)
rt_fn = assert(load("return " .. quoted))
assert(rt_fn() == binary_blob, "%q round-trip failed")

-- ============================================================================
-- 5. Plain-text string.* helpers
-- ============================================================================

-- Predicates
assert(string.contains("hello %d+ world", "%d+") == true)
assert(string.contains("hello", "") == true)
assert(string.contains("hello", "xyz") == false)
assert(string.contains("a\0b", "\0b") == true)
assert(type(string.contains("a", "b")) == "flag")

assert(string.starts_with("file.lua", "file") == true)
assert(string.starts_with("file.lua", "") == true)
assert(string.starts_with("file.lua", "^file") == false)
assert(string.starts_with("hi", "high") == false)

assert(string.ends_with("file.lua", ".lua") == true)
assert(string.ends_with("file.lua", "") == true)
assert(string.ends_with("file.lua", ".lua$") == false)
assert(string.ends_with("hi", "ahi") == false)

-- index_of & count
assert(string.index_of("a.b.c", ".") == 2)
assert(string.index_of("a.b.c", ".", 3) == 4)
assert(string.index_of("a.b.c", ".", -2) == 4)
assert(string.index_of("a.b.c", ".", 5) == nil)
assert(string.index_of("a.b.c", ".", 10) == nil)
assert(string.index_of("abc", "", 4) == 4)
assert(string.index_of("abc", "", 5) == nil)
assert(string.index_of("a\0b\0c", "\0c") == 4)

assert(string.count("aaaa", "aa") == 2)
assert(string.count("100% + 50% = 150%", "%") == 3)
assert(string.count("hello", "z") == 0)
assert(pcall(string.count, "abc", "") == false)

-- replace
r1, c1 = string.replace("a.b.c", ".", "%1\\n")
assert(r1 == "a%1\\nb%1\\nc" and c1 == 2)
r2, c2 = string.replace("aaaa", "aa", "b", 1)
assert(r2 == "baa" and c2 == 1)
r3, c3 = string.replace("aaaa", "aa", "b", 0)
assert(r3 == "aaaa" and c3 == 0)
assert(pcall(string.replace, "abc", "", "x") == false)

-- trim / ltrim / rtrim
assert(string.trim(" \t\r\n hello world \n\t ") == "hello world")
assert(string.ltrim("  hello  ") == "hello  ")
assert(string.rtrim("  hello  ") == "  hello")
assert(string.trim("///path/to/dir///", "/") == "path/to/dir")
assert(string.rtrim("///path/to/dir///", "/") == "///path/to/dir")
assert(string.ltrim("///path/to/dir///", "/") == "path/to/dir///")
assert(string.trim("   ") == "")

-- strip_prefix / strip_suffix
sp1, ok1 = string.strip_prefix("https://example.com", "https://")
assert(sp1 == "example.com" and ok1 == true)
sp2, ok2 = string.strip_prefix("http://example.com", "https://")
assert(sp2 == "http://example.com" and ok2 == false)

ss1, ok3 = string.strip_suffix("archive.tar.gz", ".gz")
assert(ss1 == "archive.tar" and ok3 == true)
ss2, ok4 = string.strip_suffix("archive.tar", ".gz")
assert(ss2 == "archive.tar" and ok4 == false)

-- dedent
help = string.dedent("""
    Usage: tool <command>

    Commands:
      run     Execute job
""")
assert(help == "Usage: tool <command>\n\nCommands:\n  run     Execute job")

indented_close = string.dedent("""
        alpha
          beta
        gamma
    """)
assert(indented_close == "alpha\n  beta\ngamma")
assert(string.dedent("    single line") == "single line")
assert(string.dedent("   \n   \n  ") == "")
assert(string.dedent("") == "")
assert(string.dedent("\r\n  a\r\n    b\r\n") == "a\r\n  b")

-- split / lines / words
assert_table_eq(string.split("a::b:c", ":"), {"a", "", "b", "c"}, "split colon")
assert_table_eq(string.split(":a:", ":"), {"", "a", ""}, "split edge colons")
assert_table_eq(string.split("", ":"), {""}, "split empty")
assert_table_eq(string.split("a--b--c", "--", 1), {"a", "b--c"}, "split max=1")
assert_table_eq(string.split("a--b--c", "--", 0), {"a--b--c"}, "split max=0")
assert(pcall(string.split, "abc", "") == false)

assert_table_eq(string.lines(""), {}, "lines empty")
assert_table_eq(string.lines("one"), {"one"}, "lines single")
assert_table_eq(string.lines("one\ntwo\n"), {"one", "two"}, "lines trailing LF")
assert_table_eq(string.lines("one\r\ntwo\r\n"), {"one", "two"}, "lines trailing CRLF")
assert_table_eq(string.lines("one\n\ntwo"), {"one", "", "two"}, "lines blank middle")
assert_table_eq(string.lines("one\n\n"), {"one", ""}, "lines double trailing LF")
assert_table_eq(string.lines("\n"), {""}, "lines single LF")

assert_table_eq(string.words(""), {}, "words empty")
assert_table_eq(string.words("  \t\r\n "), {}, "words whitespace only")
assert_table_eq(string.words("  alpha\tbeta\r\ngamma  "), {"alpha", "beta", "gamma"}, "words mixed ws")

-- template (positional and named)
assert(string.template("<p>{{}} of {{}} (100%)</p>", 3, 10) == "<p>3 of 10 (100%)</p>")
assert(string.template("{{}} / {{}} / {{}}", true, false) == "true / false / nil")
mt_obj = setmetatable({}, {__tostring = function() return "custom%1\\n" end})
assert(string.template("obj={{{}}}", mt_obj) == "obj={custom%1\\n}")

assert(string.template(
    "<div style=\"width: 100%\">{{name}} ({{ age }}) flag={{flag}} keep={{unknown}}</div>",
    {name = "Ana %s", age = 30, flag = false}
) == "<div style=\"width: 100%\">Ana %s (30) flag=false keep={{unknown}}</div>")
assert(string.template("{{{name}}}", {name = "ok"}) == "{ok}")
assert(string.template("unclosed {{ here", {here = 1}) == "unclosed {{ here")

print("PASS test_strings_and_escapes")
