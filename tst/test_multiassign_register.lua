-- Regression test for the register-collision bug documented at
-- lparser.c:1072-1081 (assignment()): when a multi-assignment mixes an
-- already-active local/upvalue with a brand-new implicit-local target,
-- and the RHS is a multi-return call, the new local's reserved register
-- used to collide with the call's own result register -- clobbering the
-- first result before the earlier LHS variable could read it.

existing = 10

-- Force 'existing' to be captured as an upvalue by a nested closure, so
-- it's the "existing_upvar" half of the pattern rather than a plain local.
function capture()
  return existing
end

function f()
  return 1, 2
end

-- existing_upvar, new_local = f()
existing, new_local = f()

assert(existing == 1,
       "existing upvar should be 1 after multi-assign, got " ..
       tostring(existing))
assert(new_local == 2,
       "new implicit local should be 2 after multi-assign, got " ..
       tostring(new_local))
assert(capture() == 1,
       "closure should observe the updated upvalue, got " .. tostring(capture()))

print("PASS multiassign register collision check")
