
package.path = "lib/?.lua;" .. package.path
utils = require("utils")

print("esting utils...")

-- est keys
t = {a=1, b=2}
k = utils.keys(t)
assert(#k == 2, "keys failed")

-- est merge
t1 = {a=1}
t2 = {b=2}
utils.merge_module(t1, t2)
assert(t1.b == 2, "merge_module failed")

-- est string_utils integration (via utils)
assert(utils.starts_with("foobar", "foo"), "string_utils starts_with failed")

print("utils tests passed")
