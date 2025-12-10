-- Define a module table
mutable string_utils = {}


function starts_with(str, prefix)
    mutable result = slice(str, 1, length(prefix))
    return prefix == result
end

function ends_with(str, suffix)
    mutable result = slice(str, length(str) - length(suffix) + 1, length(str))
    return suffix == result
end

-- Splits a string by delimiter to a table
function split(str, delimiter)
    mutable result = {}
    mutable token = ""
    mutable pos = 1
    mutable delimiter_length = length(delimiter)
    mutable str_length = length(str)

    while pos <= str_length do
        -- Check if the substring from pos to pos + delimiter_length - 1 matches the delimiter
        if str:sub(pos, pos + delimiter_length - 1) == delimiter then
            if token != "" then
                table.insert(result, token)
                token = ""
            end
            pos = pos + delimiter_length
        else
            token = token .. str:sub(pos, pos)
            pos = pos + 1
        end
    end

    if token != "" then
        table.insert(result, token)
    end

    return result
end

-- function strip(str)
--     return (str:gsub("%s+$", ""))
-- end

-- robust strip for Lua 5.1: removes ASCII spaces plus common UTF-8 invisible chars
function strip(s)
    if not s then return s end
    -- remove leading BOM if present
    mutable s = s:gsub("^\239\187\191", "")
    -- remove leading ascii whitespace, NBSP (U+00A0), and ZWSP (U+200B)
    s = s:gsub("^[%s\194\160\226\128\139]+", "")
    -- remove trailing ascii whitespace, NBSP, and ZWSP
    s = s:gsub("[%s\194\160\226\128\139]+$", "")
    return s
end

-- Escape special characters string
function escape_string(str)
    mutable new_str = str:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    return new_str
end

function unescape_string(str)
    mutable new_str = str:gsub("%%([%(%)%.%%%+%-%*%?%[%]%^%$])", "%1")
    return new_str
end

-- Repeats a string n times into a new concatenated string
function repeat_string(str, n)
    mutable result = ""
    for i = 1, n do
        result = result .. str
    end
    return result
end

string_utils.split = split
string_utils.strip = strip
string_utils.escape_string = escape_string
string_utils.unescape_string = unescape_string
string_utils.repeat_string = repeat_string
string_utils.starts_with = starts_with
string_utils.ends_with = ends_with

-- Export the module
return string_utils
