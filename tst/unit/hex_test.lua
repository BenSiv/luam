print("Testing hex escapes...")

function assert_eq(a, b, msg)
    if a != b then
        error(msg .. ": " .. tostring(a) .. " != " .. tostring(b))
    else
        print(msg .. ": PASS")
    end
end

-- Test basic hex escape
s = "\x41"
assert_eq(s, "A", "\\x41 == A")

s = "\x4C\x75\x61" -- Lua
assert_eq(s, "Lua", "\\x4C\\x75\\x61 == Lua")

-- Test bounds
s = "\xFF"
assert_eq(string.byte(s), 255, "\\xFF == 255")

print("HEX TEST SUCCESS")
