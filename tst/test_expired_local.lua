-- A name implicitly declared in a nested block must not silently resolve as
-- a global after that block ends.

status, err = loadstring("if true then\n  scoped = 1\nend\nprint(scoped)")
assert(status == nil, "expired local read should fail to compile")
assert(string.find(err, "no longer in scope") != nil,
       "expired local error should explain the scope failure")

status, err = loadstring("if true then\n  scoped = {}\nend\nscoped.field = 1")
assert(status == nil, "expired local used as an indexed base should fail")
assert(string.find(err, "no longer in scope") != nil,
       "indexed expired local error should explain the scope failure")

status, err = loadstring("if true then\n  scoped = 1\nend\nscoped = 2\nreturn scoped")
assert(status != nil, "a fresh bare assignment should remain valid")
assert(status() == 2, "fresh assignment should create a new local")

print("PASS expired local checks")
