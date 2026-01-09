print("Testing unified load...")

passed = true

-- Test load with string (formerly loadstring)
f, err = load("return 'loaded from string'")
if f then
    if f() == 'loaded from string' then
        print("load(string): PASS")
    else
        print("load(string): FAIL (wrong return)")
        passed = false
    end
else
    print("load(string): FAIL (error: " .. tostring(err) .. ")")
    passed = false
end

-- Test load with function
code_part = "return 'loaded from function'"
i = 0
func_reader = function()
    i = i + 1
    if i == 1 then return code_part else return nil end
end

f, err = load(func_reader, "myfuncs")
if f then
    if f() == 'loaded from function' then
        print("load(function): PASS")
    else
        print("load(function): FAIL (wrong return)")
        passed = false
    end
else
    print("load(function): FAIL (error: " .. tostring(err) .. ")")
    passed = false
end

if passed then
    print("VERIFICATION SUCCESS")
else
    os.exit(1)
end
