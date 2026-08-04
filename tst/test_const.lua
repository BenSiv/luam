-- const keyword: compile-time immutable binding, zero runtime cost.

const P = 3.14159
assert(P == 3.14159, "const value should be readable like a normal local")

status, err = loadstring("const Q = 1\nQ = 2")
assert(status == nil, "reassigning a const should be a compile-time error")
assert(string.find(err, "const") != nil,
       "const reassignment error should mention 'const', got: " .. tostring(err))

print("PASS const keyword check")
