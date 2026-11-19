-- Minimal unit-test assertion runner paired with `lib/laws.lua`.

const test = {}

PASSED = 0
FAILED = 0

deep_eq = nil

deep_eq = function(a, b)
    if a == b then
        return true
    end
    if type(a) != "table" or type(b) != "table" then
        return false
    end
    for k, v in pairs(a) do
        if not deep_eq(v, b[k]) then
            return false
        end
    end
    for k, _ in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

format_val = nil

format_val = function(v)
    kind = type(v)
    if kind == "string" then
        return string.format("%q", v)
    end
    if kind != "table" then
        return tostring(v)
    end
    parts = {}
    for k, item in pairs(v) do
        table.insert(parts, tostring(k) .. "=" .. format_val(item))
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

function record_pass()
    PASSED = PASSED + 1
    return true
end

function record_fail(msg)
    FAILED = FAILED + 1
    label = msg
    if label == nil or label == "" then
        label = "assertion failed"
    end
    io.write(io.stderr, "FAIL: " .. label .. "\n")
    return false
end

function test.check(cond, msg)
    if cond == true then
        return record_pass()
    end
    return record_fail(msg)
end

function test.eq(actual, expected, msg)
    if deep_eq(actual, expected) then
        return record_pass()
    end
    prefix = ""
    if msg != nil and msg != "" then
        prefix = msg .. ": "
    end
    return record_fail(prefix .. "expected " .. format_val(expected) .. ", got " .. format_val(actual))
end

function test.neq(actual, unexpected, msg)
    if not deep_eq(actual, unexpected) then
        return record_pass()
    end
    prefix = ""
    if msg != nil and msg != "" then
        prefix = msg .. ": "
    end
    return record_fail(prefix .. "expected value != " .. format_val(unexpected))
end

function test.throws(fn, substr, msg)
    ok, err = pcall(fn)
    if ok then
        prefix = ""
        if msg != nil and msg != "" then
            prefix = msg .. ": "
        end
        return record_fail(prefix .. "expected function to raise an error, but it succeeded")
    end
    if substr != nil and substr != "" and not string.contains(tostring(err), substr) then
        prefix = ""
        if msg != nil and msg != "" then
            prefix = msg .. ": "
        end
        return record_fail(prefix .. "expected error containing " .. string.format("%q", substr) .. ", got " .. string.format("%q", tostring(err)))
    end
    return record_pass()
end

function test.run(name, fn)
    ok, err = pcall(fn)
    if not ok then
        record_fail(tostring(name) .. " raised unexpected error: " .. tostring(err))
    end
end

function test.counts()
    return PASSED, FAILED
end

function test.reset()
    PASSED = 0
    FAILED = 0
end

function test.finish(suite_name)
    prefix = ""
    if suite_name != nil and suite_name != "" then
        prefix = suite_name .. ": "
    end
    if FAILED > 0 then
        io.write(io.stderr, string.format("%s%d passed, %d FAILED\n", prefix, PASSED, FAILED))
        os.exit(1)
    end
    print(string.format("%s%d passed", prefix, PASSED))
    os.exit(0)
end

return test
