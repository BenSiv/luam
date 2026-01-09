
package.path = "lib/?.lua;" .. package.path
mutable async = require("async")

print("Testing async...")

-- Mock worker function
function worker(x) return x * 2 end

-- Mock lanes logic by checking if it gracefully falls back or errors if lanes missing
-- Usually lanes is a C module.
mutable res, concurrent = async.map_concurrent({1, 2, 3}, worker)

assert(concurrent == false, "Should fallback to sequential if lanes missing")
assert(res[1] == 2 and res[2] == 4 and res[3] == 6, "map_concurrent logic failed")

print("async tests passed")
