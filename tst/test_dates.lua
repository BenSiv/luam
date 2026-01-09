
package.path = "lib/?.lua;" .. package.path
dates = require("dates")
utils = require("utils")

print("Testing dates...")

dt = "2023-10-27 10:00:00"
assert(dates.is_valid_timestamp(dt), "is_valid_timestamp failed")

norm = dates.normalize_datetime("2023-10-27")
assert(utils.starts_with(norm, "2023-10-27"), "normalize_datetime failed")

print("dates tests passed")
