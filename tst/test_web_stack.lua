html = require("html")
render = require("render")
cgi = require("cgi")
external_tool = require("external_tool")

-- Test html escaping
assert(html.escape("<script>alert('x & y \"')</script>") == "&lt;script&gt;alert(&#39;x &amp; y &quot;&#39;)&lt;/script&gt;")
assert(html.html_escape("test & fun") == "test &amp; fun")
assert(html.json_for_script('{"text":"</script>"}') == '{"text":"\\u003c/script>"}')
assert(html.js_string_literal('hello "world"\n<break>') == 'hello \\"world\\"\\n\\u003cbreak>')

-- Test render
tpl = "Hello {{ name }}, you have {{{ unescaped_html }}} and rating {{ stats.score }}."
ctx = {
    name = "Ben <Coder>",
    unescaped_html = "<strong>bold</strong>",
    stats = { score = 100 }
}
out = render.render(tpl, ctx)
assert(out == "Hello Ben &lt;Coder&gt;, you have <strong>bold</strong> and rating 100.")

-- Test cgi helpers
assert(cgi.url_decode("hello+world%21") == "hello world!")
params = cgi.parse_query("user=Ben+Sivan&role=architect")
assert(params["user"] == "Ben Sivan")
assert(params["role"] == "architect")

-- Test external_tool
assert(external_tool.shell_quote("it's cool") == "'it'\\''s cool'")
res, err = external_tool.with_temp_file("hello world", "w", function(tmp)
    h = io.open(tmp, "r")
    txt = io.read(h, "*all")
    io.close(h)
    return txt, nil
end)
assert(res == "hello world")

print("PASS test_web_stack.lua")
