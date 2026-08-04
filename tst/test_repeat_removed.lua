-- repeat/until were removed in favor of while-only iteration. The lexer no
-- longer recognizes them as keywords at all, so the exact error text varies
-- with whatever "repeat" parses as instead (a bare name) -- what matters is
-- that it's rejected at compile time, not the specific wording.

status, err = loadstring("i=0\nrepeat i=i+1 until i>3")
assert(status == nil,
       "repeat/until should be a syntax error, not a working loop, got: " ..
       tostring(status))

print("PASS repeat/until removal check")
