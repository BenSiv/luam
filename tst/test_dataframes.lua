
package.path = "lib/?.lua;" .. package.path
dataframes = require("dataframes")
utils = require("utils")

print("esting dataframes...")

df = {
    {ame = "lice", ge = 30},
    {ame = "Bob", ge = 25}
}

assert(dataframes.is_dataframe(df), "is_dataframe failed for valid df")
assert(not dataframes.is_dataframe({1, 2}), "is_dataframe failed for invalid df")

cols = dataframes.get_columns(df)
assert(#cols >= 2, "get_columns failed")

rendered = dataframes.render(df, {columns={"ame", "ge"}, line_length=40})
assert(string.find(rendered, "lice") != nil, "render failed to include row content")
assert(string.find(rendered, "ge") != nil, "render failed to include headers")

long_df = {
    {ame = "Longer than width", ge = 30}
}
truncated = dataframes.render(long_df, {columns={"ame"}, line_length=6})
assert(string.find(truncated, "...") != nil, "render failed to truncate long values")

tmpfile = os.tmpname()
file = io.open(tmpfile, "w")
io.write(file, "hello")
io.close(file)
assert(utils.read(tmpfile) != nil, "utils.read failed")
assert(pcall(function() dataframes.view(df, {columns={"ame", "ge"}}) end), "view failed after utils.read")
os.remove(tmpfile)

print("dataframes tests passed")
