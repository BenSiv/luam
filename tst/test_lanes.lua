lanes = require("lanes").configure({strip_functions=false})
function task()
    print("n lane")
    return "ok"
end
l = lanes.gen("*", task)
print("Lane created")
res = l()
print("esult:", res[1])
