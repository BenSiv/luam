-- module() and newproxy() were removed from the standard library.

assert(module == nil, "module() should be removed from the standard library")
assert(newproxy == nil, "newproxy() should be removed from the standard library")

print("PASS module/newproxy removal check")
