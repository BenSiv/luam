-- Regression test: bare getfenv() must reflect a prior setfenv(1, ...) on
-- the calling function, not just the raw global table. A prior bug in
-- luaB_getfenv (a `lua_isnone(L,1)` shortcut with no stock Lua equivalent)
-- made bare getfenv() always return the raw global table regardless of any
-- setfenv(1, ...) call -- getfenv(1) (explicit level) worked correctly the
-- whole time, which is what made the bug easy to miss.

g = {}
setmetatable(g, {__index = getfenv()})
setfenv(1, g)

assert(getfenv(1) == g, "getfenv(1) should reflect setfenv(1, g)")
assert(getfenv() == g,
       "bare getfenv() should also reflect setfenv(1, g), not the raw global table")

-- setfenv on a function object (unaffected by the bug either way) still works
function target()
  return getfenv() == g
end
setfenv(target, g)
assert(target(), "setfenv(function, g) should still work")

print("PASS getfenv/setfenv agreement check")
