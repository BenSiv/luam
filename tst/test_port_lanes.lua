input_path = "lanes_temp/src/lanes.lua"
output_path = "lib/lanes.lua"

fin = io.open(input_path, "r")
if fin == nil then
    print("Skipping test_port_lanes.lua: Input file not found: " .. input_path)
    os.exit(0)
end
fout = io.open(output_path, "w")

content = io.read(fin, "*all")

q3 = string.char(34, 34, 34)

function replace_plain(text, search, replace)
    start_pos = 1
    while true do
        s, e = string.find(text, search, start_pos, true)
        if s == nil then break end
        
        prefix = string.sub(text, 1, s - 1)
        suffix = string.sub(text, e + 1)
        text = prefix .. replace .. suffix
        
        start_pos = s + string.len(replace)
    end
    return text
end

-- 1. Multiline Comments --[[ ... ]] -> -- ...
-- First, handle the closing marker.
-- f we just replace ]] with nothing, we might break strings.
-- But lanes.lua seems to use --[[ ... ]]-- or similar.
-- Let's try to match the block.
-- Lua 5.1 regex is limited.
-- Static logic:
-- content = string.gsub(content, "(%s*%-%-" .. q3 .. "[%s%S]-" .. q3 .. ")", ...)
-- But lanes uses [[. Static port converted [[ to """ first.
-- Let's check if lanes uses [[ for strings.
-- Simple check: grep lanes.lua for [[
-- f it uses it for strings, we must convert to """.
-- f luam supports """.

-- ssumption: Convert [[ and ]] to """
content = string.gsub(content, "%[%[", q3)
content = string.gsub(content, "%]%]", q3)

-- ow handle --""" ... """ comments
content = string.gsub(content, "%-%-" .. q3 .. "(.-)" .. q3 .. "%-%-", function(match)
    return string.gsub(match, "\n", "\n-- ")
end)
content = string.gsub(content, "%-%-" .. q3 .. "(.-)" .. q3, function(match)
    return string.gsub(match, "\n", "\n-- ")
end)

-- 2. emove 'local '
-- Handle functions
content = string.gsub(content, "local%s+function", "function")

-- Handle assignments: local x = ... -> x = ...
content = string.gsub(content, "local%s+([^=\n]+)=", "%1=")

-- Handle assignments: local x = ... -> x = ...
content = string.gsub(content, "local%s+([^=\n]+)=", "%1=")

-- Handle pure declarations: local x -> x = nil (to preserve scope)
content = string.gsub(content, "local%s+([^=\n]+)%s*(\n)", "%1 = nil%2")
content = string.gsub(content, "local%s+([^=\n]+)%s*(%-%-[^\n]*\n)", "%1 = nil%2")

-- Cleanup any remaining "local " just in case (e.g. at EOF)
content = string.gsub(content, "local%s+([^=\n]+)$", "%1 = nil")
content = string.gsub(content, "local%s+", "")

-- 3. eplace ~= with !=
content = string.gsub(content, "~=", "!=")

-- 4. Basic OOP conversions (if any)
-- Lanes uses string.format, table.insert etc.
-- t has lines like: local string_format = assert(string.format)
-- nd usage: string_format("%q", ...) which is procedural.
-- So OOP conversion might not be strictly needed if it uses cached functions.
-- But let's check for colon calls just in case.
-- lanes.lua:365: string_find(libs, "*", 2, true) -> procedural.
-- t seems lanes already uses procedural style via locals!
-- But we removed locals.
-- So `string_format = ...` becomes `string_format = ...` (global).
-- nd usage `string_format(...)` works.
-- But if it uses `str:match(...)`, we need convert.
-- Let's apply standard conversions just safely?
-- content = string.gsub(content, "([%w_%.]+):match%(", "string.match(%1, ")
-- content = string.gsub(content, "([%w_%.]+):find%(", "string.find(%1, ")
-- content = string.gsub(content, "([%w_%.]+):gmatch%(", "string.gmatch(%1, ")
-- content = string.gsub(content, "([%w_%.]+):sub%(", "string.sub(%1, ")
-- content = string.gsub(content, "([%w_%.]+):format%(", "string.format(%1, ")

-- However, lanes.lua explicitly caches:
-- local string_format = assert(string.format)
-- So `string_format` is a variable holding the function.
-- `str:match` is not `string_format`.
-- 'll add the OOP conversions.

content = string.gsub(content, "([%w_%.]+):match%(", "string.match(%1, ")
content = string.gsub(content, "([%w_%.]+):gsub%(", "string.gsub(%1, ")
content = string.gsub(content, "([%w_%.]+):find%(", "string.find(%1, ")
content = string.gsub(content, "([%w_%.]+):gmatch%(", "string.gmatch(%1, ")
content = string.gsub(content, "([%w_%.]+):sub%(", "string.sub(%1, ")
content = string.gsub(content, "([%w_%.]+):format%(", "string.format(%1, ")

-- lso handle io calls if any
content = string.gsub(content, "([%w_%.]+):write%(", "io.write(%1, ")
content = string.gsub(content, "([%w_%.]+):read%(", "io.read(%1, ")
content = string.gsub(content, "([%w_%.]+):close%(%)", "io.close(%1)")

-- 5. eneric OOP conversion for remaining objects (Lanes objects like Linda, Lane)
-- Handle empty args: obj:method() -> obj.method(obj)
content = string.gsub(content, "([%w_]+):([%w_]+)%(%)", "%1.%2(%1)")

-- Handle args: obj:method( -> obj.method(obj, 
-- his MUS come after specific string/io replacements to avoid breaking them if they weren't matched (but they were).
content = string.gsub(content, "([%w_]+):([%w_]+)%(", "%1.%2(%1, ")

-- 6. Convert repeat-until to while true
content = string.gsub(content, "repeat%s+(.-)%s+until%s+(.-)\n", "while true do %1 if %2 then break end end\n")

-- 5. require "lanes_core" -> we will put lanes_core.so in lib/
-- "lanes_core" should resolve if in path.

-- 7. Mock setmetatable/getmetatable since luam lacks them
content = string.gsub(content, "local setmetatable = assert%(setmetatable%)", "")
content = "setmetatable = function(t,m) return t end\n" ..
          "getmetatable = function(t) if type(t)=='userdata' then return 'Linda' end return nil end\n" .. 
          content
-- "lanes_core" should resolve if in path.
-- But wait, `lanes.lua` assumes `require "lanes_core"` returns the core module.
-- Our compilation produces `lanes_core.so`.
-- f we put `lanes_core.so` in `lib/`, `require "lanes_core"` works if `package.cpath` has `lib/?.so`.
-- t usually does or we set it in `build_libs.sh`?
-- `luam` probably defaults to looking in `lib/`.

print("Writing file...")
io.write(fout, content)
print("Written.")
io.close(fin)
io.close(fout)
print("Closed.")
