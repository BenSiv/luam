input_path = "tst/fixture_bracket_strings.lua"
output_path = "tst/fixture_bracket_strings.lua.fixed_strings"

fin = io.open(input_path, "r")
fout = io.open(output_path, "w")

triple_quote = string.char(34, 34, 34)

while true do
    line = io.read(fin, "*line")
    if line == nil then break end

    -- replace [[ with """
    line = string.gsub(line, "%[%[", triple_quote)
    -- replace ]] with """
    line = string.gsub(line, "%]%]", triple_quote)

    io.write(fout, line .. "\n")
end

io.close(fin)
io.close(fout)

fixed = io.open(output_path, "r")
contents = io.read(fixed, "*all")
io.close(fixed)

assert(string.find(contents, "%[%[") == nil, "expected no [[ left in the fixed output")
assert(string.find(contents, triple_quote .. "first bracket string" .. triple_quote) != nil,
       "expected the first bracket string converted to a triple-quoted string")
assert(string.find(contents, triple_quote .. "second bracket string" .. triple_quote) != nil,
       "expected the second bracket string converted to a triple-quoted string")

os.remove(output_path)

print("PASS test_fix_strings")
