
package.path = "lib/?.lua;" .. package.path
mutable utils = require("utils")

print("Testing utils...")

-- Test keys
mutable t = {a=1, b=2}
mutable k = utils.keys(t)
assert(#k == 2, "keys failed")

-- Test merge
mutable t1 = {a=1}
mutable t2 = {b=2}
utils.merge_module(t1, t2)
assert(t1.b == 2, "merge_module failed")

-- Test string_utils integration (via utils)
assert(utils.starts_with("foobar", "foo"), "string_utils starts_with failed")

print("utils tests passed")
