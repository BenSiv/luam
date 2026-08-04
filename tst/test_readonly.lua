-- Ported from stock Lua 5.1's test/readonly.lua, which demonstrates trapping
-- writes to "global" variables via a metatable-guarded environment table.
-- Under Luam this only half-applies, for two independent reasons:
--
--   1. setfenv(1, g) + getfenv() must agree on the calling chunk's
--      environment (regression-tested separately in test_getfenv_setfenv.lua
--      -- a prior bug made bare getfenv() ignore setfenv(1, ...) entirely).
--   2. Bare assignment (y = 1) is *always* an implicit local under Luam, by
--      design -- it never reaches the environment table's __newindex at
--      all, readonly-guarded or not. So the classic "trap accidental global
--      writes" pattern this file used to demonstrate no longer applies to
--      bare names. It still works for writes made *through* the environment
--      table explicitly (getfenv().field = ...).
--
-- This test locks in that actual, current behavior instead of pretending
-- the old trap still fires on bare assignment.

if getfenv == nil then
    print("Skipping test_readonly.lua: getfenv not supported")
else

f = function(t, i) error("cannot redefine global variable `" .. i .. "'", 2) end
g = {}
t = getfenv()
setmetatable(g, {__index = t, __newindex = f})
setfenv(1, g)

assert(getfenv() == g, "getfenv() should reflect setfenv(1, g)")

rawset(g, "x", 3)
assert(rawget(g, "x") == 3, "rawset should bypass __newindex as always")

-- The actual point of this test: bare assignment never reaches __newindex.
y = 1
assert(y == 1, "bare assignment should still succeed, as a local")
assert(rawget(g, "y") == nil,
       "bare assignment must NOT reach the environment table -- it's an " ..
       "implicit local, not a write through getfenv()")

-- Explicit writes through the environment table itself DO hit the trap.
status, err = pcall(function() getfenv().z = 1 end)
assert(status == false, "explicit getfenv().z = ... should hit the __newindex trap")
assert(string.find(err, "cannot redefine") != nil,
       "trap error should mention 'cannot redefine', got: " .. tostring(err))

print("PASS readonly-environment check (documents current implicit-local behavior)")

end
