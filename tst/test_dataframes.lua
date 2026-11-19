package.path = "lib/?.lua;" .. package.path
dataframes = require("dataframes")
paths = require("paths")

print("Testing dataframes...")

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

sorted_df = dataframes.sort_by(df, "ge")
assert(sorted_df[1].ame == "Bob", "sort_by failed")

tmpfile = os.tmpname()
paths.write_file(tmpfile, "hello")
assert(paths.read_file(tmpfile) == "hello", "paths.read_file failed")
assert(pcall(function() dataframes.view(df, {columns={"ame", "ge"}}) end), "view failed")
os.remove(tmpfile)

print("dataframes tests passed")
