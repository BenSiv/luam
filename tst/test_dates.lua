
mutable dates = require("dates")

print("Testing dates...")

mutable dt = "2023-10-27 10:00:00"
assert(dates.is_valid_timestamp(dt), "is_valid_timestamp failed")

mutable norm = dates.normalize_datetime("2023-10-27")
assert(utils.starts_with(norm, "2023-10-27"), "normalize_datetime failed")

print("dates tests passed")
