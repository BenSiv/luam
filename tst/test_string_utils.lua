package.path = "lib/?.lua;" .. package.path
string_utils = require("string_utils")

assert(string_utils.template("<p>{{}} of {{}}</p>", 3, 10) == "<p>3 of 10</p>")
assert(string_utils.template("width: 100%; {{}}", "ok") == "width: 100%; ok")
assert(string_utils.template("no placeholders here, 50% done") == "no placeholders here, 50% done")
assert(string_utils.template_named("<p>{{name}} is {{age}}</p>", {name = "Ana", age = 30}) == "<p>Ana is 30</p>")
assert(string_utils.template_named("{{a}}-{{b}}-{{a}}", {a = "x", b = "y"}) == "x-y-x")

print("test_string_utils: PASS")
