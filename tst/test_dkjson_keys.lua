-- dkjson must escape object keys exactly like string values: a key with a
-- quote, backslash or control character used to be emitted raw, producing
-- invalid JSON (daat's `entity field-map <type> title` keys by title).

json = dofile("lib/dkjson/init.lua")

keys = {"plain", "quote \" inside", "back\\slash", "tab\there", "ctrl\1char", "del\127char", "High Five\226\132\162"}
t = {}
for i, key in ipairs(keys) do
    t[key] = i
end

encoded = json.encode(t)
decoded, _, err = json.decode(encoded)
assert(decoded != nil, "encoded object with awkward keys did not round-trip: " .. tostring(err) .. " -- " .. encoded)
for i, key in ipairs(keys) do
    assert(decoded[key] == i, "key lost in round trip: " .. key)
end
assert(string.find(encoded, "\"quote \\\" inside\":", 1, true) != nil, "quote in key not escaped: " .. encoded)
assert(string.find(encoded, "\"tab\\there\":", 1, true) != nil, "tab in key not escaped: " .. encoded)

print("dkjson key escaping tests passed")
