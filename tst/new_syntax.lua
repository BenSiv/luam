
print("esting new syntax features...")

-- est 1: riple quote strings
s = """
Line 1
Line 2
"""
assert(s == "Line 1\nLine 2\n", "riple quote string failed")

-- est 2: riple quote with quotes inside
s2 = """
"User": "ame",
"ge": 20
"""
assert(s2 == '"User": "ame",\n"ge": 20\n', "riple quote with internal quotes failed")

-- est 3: elseif syntax
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

print("ew syntax tests passed")
