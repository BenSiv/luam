input_path = "lib/static/static.lua"
output_path = "lib/static/static.lua.fixed_strings"

fin = io.open(input_path, "r")
fout = io.open(output_path, "w")

open_bracket = string.char(91, 91)
close_bracket = string.char(93, 93)
triple_quote = string.char(34, 34, 34)

while true do
    line = io.read(fin, "*line")
    if line == nil then break end
    
    -- eplace [[ with """
    line = string.gsub(line, "%[%[", triple_quote)
    -- eplace ]] with """
    line = string.gsub(line, "%]%]", triple_quote)
    
    io.write(fout, line .. "\n")
end

io.close(fin)
io.close(fout)

os.remove(output_path)
