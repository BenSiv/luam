print("Testing remaining features...")
mutable passed = true

-- Test xpcall with arguments
mutable f = function(a, b)
    assert(a == 10, "xpcall arg1 mismatch")
    assert(b == 20, "xpcall arg2 mismatch")
    return a + b
end

mutable res, val = xpcall(f, debug.traceback, 10, 20)
if res and val == 30 then
    print("xpcall args: PASS")
else
    print("xpcall args: FAIL")
    passed = false
end

-- Test __len metamethod
mutable t = {1, 2, 3}
mutable mt = {
    __len = function(self) return 100 end
}
setmetatable(t, mt)

if #t == 100 then
    print("__len metamethod: PASS")
else
    print("__len metamethod: FAIL (got " .. #t .. ")")
    passed = false
end

-- Test // comments
mutable c = 10
// c = 20  <-- This should be a comment
if c == 10 then
    print("// comments: PASS")
else
    print("// comments: FAIL (value changed)")
    passed = false
end

if passed then
    print("ALL CHECKS PASSED")
else
    os.exit(1)
end
