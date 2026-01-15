
json = dofile("lib/json/json.lua")

print("esting JSO library...")

-- est Encode
t = { foo = "bar", baz = 123, list = {1, 2, 3} }
json_str = json.encode(t)
print("Encoded:", json_str)

assert(string.find(json_str, '"foo":"bar"'), "Encoding failed for foo")
assert(string.find(json_str, '"baz":123'), "Encoding failed for baz")

-- est Decode
t2 = json.decode(json_str)
assert(t2.foo == "bar", "Decoding failed for foo")
assert(t2.baz == 123, "Decoding failed for baz")
assert(t2.list[1] == 1, "Decoding failed for list")

-- est ull
null_str = json.encode({ val = json.null })
print("ull encoded:", null_str)
assert(string.find(null_str, '"val":null'), "ull encoding failed")

print("JSO library tests passed")
