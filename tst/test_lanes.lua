lanes = require("lanes").configure({strip_functions=false})
function task()
    print("In lane")
    return "ok"
end
l = lanes.gen("*", task)
print("Lane created")
res = l()
print("Result:", res[1])
