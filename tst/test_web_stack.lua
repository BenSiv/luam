html = require("html")
render = require("render")
cgi = require("cgi")
multipart = require("multipart")
external_tool = require("external_tool")

-- Test html escaping
assert(html.escape("<script>alert('x & y \"')</script>") == "&lt;script&gt;alert(&#39;x &amp; y &quot;&#39;)&lt;/script&gt;")
assert(html.html_escape("test & fun") == "test &amp; fun")
assert(html.json_for_script("{\"text\":\"</script>\"}") == "{\"text\":\"\\u003c/script>\"}")
assert(html.js_string_literal("hello \"world\"\n<break>") == "hello \\\"world\\\"\\n\\u003cbreak>")
assert(html.js_string_literal("path\\to\r\nline2\rline3") == "path\\\\to\\nline2\\nline3")

-- Test render
tpl = "Hello {{ name }}, you have {{{ unescaped_html }}} and rating {{ stats.score }}."
ctx = {
    name = "Ben <Coder>",
    unescaped_html = "<strong>bold</strong>",
    stats = { score = 100 }
}
out = render.render(tpl, ctx)
assert(out == "Hello Ben &lt;Coder&gt;, you have <strong>bold</strong> and rating 100.")
assert(render.render("<a title=\"{{ t }}\">", {t = "Bob & \"friends\""}) == "<a title=\"Bob &amp; &quot;friends&quot;\">")
assert(render.render("{{ a }}-{{ b }}", {a = "x", b = "y"}) == "x-y")
ok_missing, _ = pcall(render.render, "{{ missing }}", {})
assert(ok_missing == false)

-- Test cgi helpers
assert(cgi.url_decode("hello+world%21") == "hello world!")
params = cgi.parse_query("user=Ben+Sivan&role=architect")
assert(params["user"] == "Ben Sivan")
assert(params["role"] == "architect")

cookies = cgi.parse_cookies("session=abc.123; csrf=tok456")
assert(cookies["session"] == "abc.123")
assert(cookies["csrf"] == "tok456")
assert(cgi.set_cookie_header("session", "abc", 3600, true) == "Set-Cookie: session=abc; Path=/; SameSite=Lax; Max-Age=3600; HttpOnly")
assert(cgi.clear_cookie_header("session") == "Set-Cookie: session=; Path=/; Max-Age=0")

-- Test multipart
ct = "multipart/form-data; boundary=\"----FormBoundary7MA4YWxkTrZu0gW\""
assert(multipart.boundary_from_content_type(ct) == "----FormBoundary7MA4YWxkTrZu0gW")
mp_body = table.concat({
    "------FormBoundary7MA4YWxkTrZu0gW",
    "Content-Disposition: form-data; name=\"site_name\"",
    "",
    "Celleste LIMS",
    "------FormBoundary7MA4YWxkTrZu0gW",
    "Content-Disposition: form-data; name=\"logo\"; filename=\"logo.png\"",
    "Content-Type: image/png",
    "",
    "\x89PNG\r\n",
    "------FormBoundary7MA4YWxkTrZu0gW--",
}, "\r\n")
parsed_mp = multipart.parse(ct, mp_body)
assert(parsed_mp.site_name == "Celleste LIMS")
assert(type(parsed_mp.logo) == "table")
assert(parsed_mp.logo.filename == "logo.png")
assert(parsed_mp.logo.content_type == "image/png")
assert(parsed_mp.logo.data == "\x89PNG\r\n")

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
