print("Testing hex escapes...")

passed = true

-- Test basic hex escape
s = "\x41"
if s == "A" then
    print("\x41 == A: PASS")
else
    print("\x41 != A (got " .. s .. "): FAIL")
    passed = false
end

s = "\x4C\x75\x61" -- Lua
if s == "Lua" then
    print("\x4C\x75\x61 == Lua: PASS")
else
    print("\x4C\x75\x61 != Lua (got " .. s .. "): FAIL")
    passed = false
end

-- Test bounds (assuming 8-bit clean)
s = "\xFF"
if string.byte(s) == 255 then
    print("\xFF == 255: PASS")
else
    print("\xFF != 255: FAIL")
    passed = false
end

if passed then
    print("VERIFICATION SUCCESS")
else
    os.exit(1)
end
