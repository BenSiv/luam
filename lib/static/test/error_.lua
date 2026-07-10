-- require("foo")
-- print(pcall(require, "error"))
-- syntax error

function trace3()
  -- e = {}
  -- setmetatable(e, {__tostring = function() return "runtime error" end})
  error_val = e
  if error_val == nil then
    error_val = "runtime error"
  end
  error(error_val)
end

function trace2()
  trace3()
end

function trace1()
  trace2()
end

trace1()
