-- Bare assignment is local by default (no 'local' keyword exists). Checked
-- against _G directly -- the previous version of this test compared against
-- an unrelated empty table (`_`) instead of `_G`, so it always read nil
-- regardless of whether a/b/c/d actually leaked as globals or not.

a = 10
assert(_G.a == nil, "bare assignment at chunk scope should be local, not global")

function f()
  b = 20
  assert(_G.b == nil, "bare assignment inside a function should be local, not global")
end
f()

c, d = 30, 40
assert(_G.c == nil and _G.d == nil,
       "multi-assignment targets should be local, not global")

print("PASS implicit-local-by-default check")
