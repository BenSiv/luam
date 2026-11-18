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
leaked_tmp = nil
res, err = external_tool.with_temp_file("hello world", "w", function(tmp)
    leaked_tmp = tmp
    h = io.open(tmp, "r")
    txt = io.read(h, "*all")
    io.close(h)
    return txt, nil
end)
assert(res == "hello world")
assert(io.open(leaked_tmp, "r") == nil, "temp file must be removed on normal return")

raised_tmp = nil
ok_tmp_err, tmp_err = pcall(external_tool.with_temp_file, "secret config", "w", function(tmp)
    raised_tmp = tmp
    error("callback crashed")
end)
assert(ok_tmp_err == false and string.find(tostring(tmp_err), "callback crashed", 1, true) != nil)
assert(raised_tmp != nil and io.open(raised_tmp, "r") == nil,
    "temp file must be removed even when callback raises")

-- Test sandbox stdlib isolation & instruction-budget enforcement
sandbox = require("sandbox")
orig_gsub = string.gsub
ok_sb, sb_val = sandbox.run("""
    string.gsub = function() return "POISONED" end
    table.concat = function() return "POISONED" end
    math.floor = function() return -999 end
    return string.gsub("abc", "b", "x")
""", "poison_test", sandbox.data_env())
assert(ok_sb == true and sb_val == "POISONED", "sandbox env may mutate its own local copy")
assert(string.gsub == orig_gsub and string.gsub("O'Brien", "'", "''") == "O''Brien",
    "sandboxed stdlib mutation must NOT poison host string.gsub")
ok_sb2, sb_val2 = sandbox.run("return string.gsub(\"abc\", \"b\", \"y\")", "clean_env_test", sandbox.data_env())
assert(ok_sb2 == true and sb_val2 == "ayc", "subsequent sandbox_env must receive fresh unpoisoned stdlib: " .. tostring(sb_val2))

loop_env = sandbox.data_env()
loop_env.__max_instructions = 2000
ok_loop, loop_err = sandbox.run("""
    while true do
        pcall(function()
            while true do end
        end)
    end
""", "infinite_loop_test", loop_env)
assert(ok_loop == false and string.find(tostring(loop_err), "instruction limit", 1, true) != nil,
    "sandbox.run must abort infinite loops even when wrapped in pcall, got: " .. tostring(loop_err))

-- Test gnuplot temp-file cleanup
gnuplot = require("gnuplot")
gp_plot = gnuplot.create({
    type = "svg", width = 320, height = 200,
    data = {{{{1, 2}, {3, 4}}, with = "lines", title = "s1"}},
})
series_tmp_file = gp_plot.cfg.data[1][1]
assert(type(series_tmp_file) == "string" and io.open(series_tmp_file, "r") != nil,
    "expected series temp file to exist after gnuplot.create")
gp_out = os.tmpname()
_, _, gp_script = gnuplot.savefig(gp_plot, gp_out)
os.remove(gp_out)
assert(io.open(series_tmp_file, "r") == nil, "gnuplot.savefig must clean up series temp data files")
assert(io.open(gp_script, "r") == nil, "gnuplot.savefig must clean up temporary gnuplot script")

print("PASS test_web_stack.lua")
