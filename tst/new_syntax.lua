
print("Testing new syntax features...")

-- Test 1: Triple quote strings
s = """
Line 1
Line 2
"""
assert(s == "Line 1\nLine 2\n", "Triple quote string failed")

-- Test 2: Triple quote with quotes inside
s2 = """
"User": "Name",
"Age": 20
"""
assert(s2 == '"User": "Name",\n"Age": 20\n', "Triple quote with internal quotes failed")

-- Test 3: elseif syntax
a = 10
res = ""
if a < 5 then
    res = "low"
elseif a < 15 then
    res = "medium"
else
    res = "high"
end
assert(res == "medium", "elseif failed")

print("New syntax tests passed")
