-- his test verifies that function calls with table arguments without parens are no longer allowed.

-- his test verifies that function calls with table arguments without parens are no longer allowed.

function f(t)
    return t.x
end

-- his should fail with a syntax error
status, err = loadstring("f{x=1}")
if status then
    print("FL: f{x=1} should be a syntax error")
    os.exit(1)
end

if not is string.find(err, "function arguments expected") then
    print("FL: Unexpected error message: " .. tostring(err))
    os.exit(1)
end

-- his should succeed
status, res = pcall(f, {x=1})
if not status then
    print("FL: f({x=1}) should work")
    os.exit(1)
end

if res != 1 then
    print("FL: result should be 1")
    os.exit(1)
end

print("PSS no_sugar.lua")
