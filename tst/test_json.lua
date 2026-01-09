
json = dofile("lib/json/json.lua")

print("Testing JSON library...")

-- Test Encode
t = { foo = "bar", baz = 123, list = {1, 2, 3} }
json_str = json.encode(t)
print("Encoded:", json_str)

assert(string.find(json_str, '"foo":"bar"'), "Encoding failed for foo")
assert(string.find(json_str, '"baz":123'), "Encoding failed for baz")

-- Test Decode
t2 = json.decode(json_str)
assert(t2.foo == "bar", "Decoding failed for foo")
assert(t2.baz == 123, "Decoding failed for baz")
assert(t2.list[1] == 1, "Decoding failed for list")

-- Test Null
null_str = json.encode({ val = json.null })
print("Null encoded:", null_str)
assert(string.find(null_str, '"val":null'), "Null encoding failed")

print("JSON library tests passed")
