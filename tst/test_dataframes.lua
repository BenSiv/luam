
package.path = "lib/?.lua;" .. package.path
dataframes = require("dataframes")

print("Testing dataframes...")

df = {
    {Name = "Alice", Age = 30},
    {Name = "Bob", Age = 25}
}

assert(dataframes.is_dataframe(df), "is_dataframe failed for valid df")
assert(not dataframes.is_dataframe({1, 2}), "is_dataframe failed for invalid df")

cols = dataframes.get_columns(df)
assert(#cols >= 2, "get_columns failed")

print("dataframes tests passed")
