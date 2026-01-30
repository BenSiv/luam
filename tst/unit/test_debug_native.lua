const debug = require("debug")

print(">>> Testing debug library... <<<")

-- Test getinfo
const info = debug.getinfo(1)
assert(info.what == "main", "getinfo(1).what should be main")
assert(info.source == "@tst/unit/test_debug_native.lua", "getinfo(1).source mismatch")

-- Test traceback
const tb = debug.traceback("test message")
assert(string.find(tb, "stack traceback:"), "traceback should contain 'stack traceback:'")
assert(string.find(tb, "test message"), "traceback should contain error message")

-- Test getlocal/setlocal
function test_locals(a, b)
    const x = a + b
    const name, val = debug.getlocal(1, 1)
    assert(name == "a", "getlocal(1, 1) should be 'a'")
    assert(val == 10, "getlocal(1, 1) value should be 10")
    
    debug.setlocal(1, 1, 20)
    assert(a == 20, "setlocal should update variable")
    return a + b
end
assert(test_locals(10, 5) == 25, "locals test failed")

-- Test getregistry
const reg = debug.getregistry()
assert(type(reg) == "table", "getregistry should return a table")

-- Test sethook/gethook
function hook(event, line)
    -- hook logic
end
debug.sethook(hook, "l")
const h, mask, count = debug.gethook()
assert(h == hook, "gethook should return the hook function")
assert(mask == "l", "gethook mask should be 'l'")
debug.sethook() -- clear hook

print(">>> debug library tests PASSED! <<<")
