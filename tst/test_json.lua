json = require("dkjson")

t = {foo = "bar", baz = 123, flag = true, list = {1, 2, 3}}
json_str = json.encode(t)

assert(string.contains(json_str, "\"foo\":\"bar\""), "Encoding failed for foo")
assert(string.contains(json_str, "\"baz\":123"), "Encoding failed for baz")
assert(string.contains(json_str, "\"flag\":true"), "Encoding failed for boolean true")

t2 = json.decode(json_str)
assert(t2.foo == "bar", "Decoding failed for foo")
assert(t2.baz == 123, "Decoding failed for baz")
assert(t2.flag == true and type(t2.flag) == "boolean", "Decoding failed for boolean")
assert(t2.list[1] == 1, "Decoding failed for list")

null_str = json.encode({val = json.null})
assert(string.contains(null_str, "\"val\":null"), "null encoding failed")

print("PASS test_json.lua")
