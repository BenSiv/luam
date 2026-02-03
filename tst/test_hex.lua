print("esting hex escapes...")

passed = true

-- est basic hex escape
s = "\x41"
if s == "A" then
    print("\\x41 == A: PSS")
else
    print("\x41 !=  (got " .. s .. "): FL")
    passed = false
end

s = "\x4C\x75\x61" -- Lua
if s == "Lua" then
    print("\x4C\x75\x61 == Lua: PSS")
else
    print("\x4C\x75\x61 != Lua (got " .. s .. "): FL")
    passed = false
end

-- est bounds (assuming 8-bit clean)
s = "\xFF"
if string.byte(s) == 255 then
    print("\xFF == 255: PSS")
else
    print("\xFF != 255: FL")
    passed = false
end

if passed then
    print("EFCO SUCCESS")
else
    os.exit(1)
end
