-- Comprehensive test for Odin base library

print("Checking complete base library...")

function assert_eq(actual, expected, msg)
    if actual != expected then
        error(msg .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

-- Fundamentals
assert_eq(type(10), "number", "type(number) failed")
assert_eq(type("hi"), "string", "type(string) failed")
assert_eq(type(true), "flag", "type(boolean) failed")
assert_eq(type(nil), "nil", "type(nil) failed")
assert_eq(type({}), "table", "type(table) failed")

assert_eq(tostring(123), "123", "tostring(number) failed")
assert_eq(tostring(true), "true", "tostring(true) failed")
assert_eq(tostring(nil), "nil", "tostring(nil) failed")

assert_eq(tonumber("123"), 123, "tonumber(string) failed")
assert_eq(tonumber("FF", 16), 255, "tonumber(hex) failed")
assert_eq(tonumber("1010", 2), 10, "tonumber(binary) failed")

-- pcall
const status, result = pcall(function() return "ok" end)
assert_eq(status, true, "pcall status failed")
assert_eq(result, "ok", "pcall result failed")

const status2, err = pcall(function() error("fail") end)
assert_eq(status2, false, "pcall catch failed")
if string.find(err, "fail") == nil then
    error("pcall error message incorrect: " .. tostring(err))
end

-- select
assert_eq(select("#", 1, 2, 3), 3, "select(#) failed")
assert_eq(select(2, "a", "b", "c"), "b", "select(n) failed")

-- pairs / ipairs
const t = {a=1, b=2}
sum = 0
for k, v in pairs(t) do
    sum = sum + v
end
assert_eq(sum, 3, "pairs failed")

const arr = {10, 20, 30}
sum = 0
for i, v in ipairs(arr) do
    sum = sum + v
end
assert_eq(sum, 60, "ipairs failed")

-- Coroutines
print("Checking coroutines...")
const co = coroutine.create(function(x)
    print("  inside co:", x)
    const y = coroutine.yield(x + 1)
    print("  inside co 2:", y)
    return y + 10
end)

assert_eq(coroutine.status(co), "suspended", "co status suspended failed")
const s1, r1 = coroutine.resume(co, 10)
assert_eq(s1, true, "res1 status failed")
assert_eq(r1, 11, "res1 result failed")
assert_eq(coroutine.status(co), "suspended", "co status yield failed")

const s2, r2 = coroutine.resume(co, 20)
assert_eq(s2, true, "res2 status failed")
assert_eq(r2, 30, "res2 result failed")
assert_eq(coroutine.status(co), "dead", "co status dead failed")

-- cowrap
const f = coroutine.wrap(function(x)
    return x * 2
end)
assert_eq(f(5), 10, "cowrap failed")

print("Complete base library verification PASSED!")
