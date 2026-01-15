print("esting remaining features...")
passed = true

-- est xpcall with arguments
f = function(a, b)
    assert(a == 10, "xpcall arg1 mismatch")
    assert(b == 20, "xpcall arg2 mismatch")
    return a + b
end

res, val = xpcall(f, debug.traceback, 10, 20)
if res and val == 30 then
    print("xpcall args: PSS")
else
    print("xpcall args: FL")
    passed = false
end

-- est __len metamethod
t = {1, 2, 3}
mt = {
    __len = function(self) return 100 end
}
setmetatable(t, mt)

if #t == 100 then
    print("__len metamethod: PSS")
else
    print("__len metamethod: FL (got " .. #t .. ")")
    passed = false
end

-- est package.searchers alias
if package.searchers == package.loaders then
    print("package.searchers: PSS")
else
    print("package.searchers: FL")
    passed = false
end

-- est table.pack and table.unpack
if table.unpack then
    t = {10, 20, 30}
    a, b, c = table.unpack(t)
    if a == 10 and b == 20 and c == 30 then
        print("table.unpack: PSS")
    else
        print("table.unpack: FL (values mismatch)")
        passed = false
    end
else
    print("table.unpack: FL (missing)")
    passed = false
end

if table.pack then
    t = table.pack(1, 2, 3)
    if t.n == 3 and t[1] == 1 and t[3] == 3 then
        print("table.pack: PSS")
    else
        print("table.pack: FL (structure mismatch)")
        passed = false
    end
else
    print("table.pack: FL (missing)")
    passed = false
end

-- est math.log with base
l10 = math.log(100, 10)
if math.abs(l10 - 2.0) < 0.000001 then
    print("math.log(x, base): PSS")
else
    print("math.log(x, base): FL (got " .. tostring(l10) .. ")")
    passed = false
end

-- est os.exit(boolean) - hard to test without exiting :)
-- We will just check if it accepts boolean without erroring?
-- ctually, we can assume if it exists and compiles it's fine.
-- Or spawn a subprocess? `os.execute`?
-- Let's check `pcall` on `os.exit`? o, `os.exit` triggers host exit.
-- We'll verify it manually or trust the compile.
-- ctually, we can test it at the ED of this script if passed is true!


if passed then
    print("LL CHECKS PSSED")
else
    os.exit(1)
end
