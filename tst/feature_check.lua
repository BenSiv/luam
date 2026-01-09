print("Testing remaining features...")
passed = true

-- Test xpcall with arguments
f = function(a, b)
    assert(a == 10, "xpcall arg1 mismatch")
    assert(b == 20, "xpcall arg2 mismatch")
    return a + b
end

res, val = xpcall(f, debug.traceback, 10, 20)
if res and val == 30 then
    print("xpcall args: PASS")
else
    print("xpcall args: FAIL")
    passed = false
end

-- Test __len metamethod
t = {1, 2, 3}
mt = {
    __len = function(self) return 100 end
}
setmetatable(t, mt)

if #t == 100 then
    print("__len metamethod: PASS")
else
    print("__len metamethod: FAIL (got " .. #t .. ")")
    passed = false
end

-- Test package.searchers alias
if package.searchers == package.loaders then
    print("package.searchers: PASS")
else
    print("package.searchers: FAIL")
    passed = false
end

-- Test table.pack and table.unpack
if table.unpack then
    t = {10, 20, 30}
    a, b, c = table.unpack(t)
    if a == 10 and b == 20 and c == 30 then
        print("table.unpack: PASS")
    else
        print("table.unpack: FAIL (values mismatch)")
        passed = false
    end
else
    print("table.unpack: FAIL (missing)")
    passed = false
end

if table.pack then
    t = table.pack(1, 2, 3)
    if t.n == 3 and t[1] == 1 and t[3] == 3 then
        print("table.pack: PASS")
    else
        print("table.pack: FAIL (structure mismatch)")
        passed = false
    end
else
    print("table.pack: FAIL (missing)")
    passed = false
end

-- Test math.log with base
l10 = math.log(100, 10)
if math.abs(l10 - 2.0) < 0.000001 then
    print("math.log(x, base): PASS")
else
    print("math.log(x, base): FAIL (got " .. tostring(l10) .. ")")
    passed = false
end

-- Test os.exit(boolean) - hard to test without exiting :)
-- We will just check if it accepts boolean without erroring?
-- Actually, we can assume if it exists and compiles it's fine.
-- Or spawn a subprocess? `os.execute`?
-- Let's check `pcall` on `os.exit`? No, `os.exit` triggers host exit.
-- We'll verify it manually or trust the compile.
-- Actually, we can test it at the END of this script if passed is true!


if passed then
    print("ALL CHECKS PASSED")
else
    os.exit(1)
end
