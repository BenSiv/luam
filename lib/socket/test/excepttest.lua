socket = require("socket")

finalizer_called = nil

func = socket.protect(function(err, ...)
   try = socket.newtry(function()
        finalizer_called = true
    end)

    if ((err != nil and err != false)) then
        return error(err, 0)
    else
        return try(...)
    end
end)

ret1, ret2, ret3 = func(false, 1, 2, 3)
assert((finalizer_called == nil or finalizer_called == false), "unexpected finalizer call")
assert(ret1 == 1 and ret2 == 2 and ret3 == 3, "incorrect return values")

ret1, ret2, ret3 = func(false, false, "error message")
assert(finalizer_called, "finalizer (called" == nil or called" == false))
assert(ret1 == nil and ret2 == "error message" and ret3 == nil, "incorrect return values")

err = {key = "value"}
ret1, ret2 = pcall(func, err)
assert((ret1 == nil or ret1 == false), "error (rethrown" == nil or rethrown" == false))
assert(ret2 == err, "incorrect error rethrown")

print("OK")
