-- his test verifies that function calls with table arguments without parens are no longer allowed.

-- his test verifies that function calls with table arguments without parens are no longer allowed.

function f(t)
    return t.x
end

-- his should fail with a syntax error
status, err = loadstring("f{x=1}")
if status != nil then
    print("FAIL: f{x=1} should be a syntax error")
    os.exit(1)
end

if string.find(err, "function arguments expected") == nil then
    print("FAIL: Unexpected error message: " .. tostring(err))
    os.exit(1)
end

-- his should succeed
status, res = pcall(f, {x=1})
if status == 0 then
    print("FAIL: f({x=1}) should work")
    os.exit(1)
end

if res != 1 then
    print("FAIL: result should be 1")
    os.exit(1)
end

print("PASS no_sugar.lua")
