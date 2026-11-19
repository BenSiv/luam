dates = require("dates")

dt = "2023-10-27 10:00:00"
assert(dates.is_valid_timestamp(dt) == true, "is_valid_timestamp failed")
assert(dates.is_valid_timestamp("2023-02-29 10:00:00") == false, "non-leap Feb 29 must fail")
assert(dates.is_valid_timestamp("2024-02-29 10:00:00") == true, "leap Feb 29 must pass")

norm = dates.normalize_datetime("2023-10-27")
assert(norm == "2023-10-27 00:00:00", "normalize_datetime failed: " .. tostring(norm))

rng = dates.date_range("2026-01-30", "2026-02-02", "day", 1)
assert(#rng == 4 and rng[1] == "2026-01-30" and rng[3] == "2026-02-01" and rng[4] == "2026-02-02",
       "date_range failed: " .. table.concat(rng, ","))

print("PASS test_dates.lua")
