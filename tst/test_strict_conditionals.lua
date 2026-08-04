-- Conditionals (if/while) and `not` require an actual boolean -- no
-- truthy/falsy coercion. A literal nil is rejected at compile time; any
-- other non-boolean is rejected at runtime, since the compiler can't always
-- prove a variable's type in advance.

status, err = loadstring("if nil then end")
assert(status == nil, "if nil then ... should be a compile-time error")
assert(string.find(err, "conditional value") != nil,
       "error should mention 'conditional value', got: " .. tostring(err))

status, err = pcall(function() y = 0; if y then end end)
assert(status == false, "if <number> then ... should raise a runtime error")
assert(string.find(err, "boolean") != nil,
       "error should mention 'boolean', got: " .. tostring(err))

status, err = loadstring("x = not nil")
assert(status == nil, "not nil should be a compile-time error")
assert(string.find(err, "boolean") != nil,
       "error should mention 'boolean', got: " .. tostring(err))

status, err = pcall(function() z = 5; if not z then end end)
assert(status == false, "not <number> should raise a runtime error")
assert(string.find(err, "boolean") != nil,
       "error should mention 'boolean', got: " .. tostring(err))

print("PASS strict conditional / strict not checks")
