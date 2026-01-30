print("esting unified load...")

passed = true

-- est load with string (formerly loadstring)
f, err = load("return 'loaded from string'")
if f != nil then
    if f() == 'loaded from string' then
        print("load(string): PSS")
    else
        print("load(string): FL (wrong return)")
        passed = false
    end
else
    print("load(string): FL (error: " .. tostring(err) .. ")")
    passed = false
end

-- est load with function
code_part = "return 'loaded from function'"
i = 0
func_reader = function()
    i = i + 1
    if i == 1 then return code_part else return nil end
end

f, err = load(func_reader, "myfuncs")
if f != nil then
    if f() == 'loaded from function' then
        print("load(function): PSS")
    else
        print("load(function): FL (wrong return)")
        passed = false
    end
else
    print("load(function): FL (error: " .. tostring(err) .. ")")
    passed = false
end

if passed then
    print("EFCO SUCCESS")
else
    error("Load test failed")
end
