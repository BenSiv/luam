-- Define a module table
string_utils = {}


function starts_with(str, prefix)
    result = string.sub(str, 1, #prefix)
    return prefix == result
end

function ends_with(str, suffix)
    result = string.sub(str, #str - #suffix + 1, #str)
    return suffix == result
end

-- Splits a string by delimiter to a table
function split(str, delimiter)
    result = {}
    token = ""
    pos = 1
    delimiter_length = #delimiter
    str_length = #str

    while (pos <= str_length) do
        -- Check if the substring from pos to pos + delimiter_length - 1 matches the delimiter
        if (string.sub(str, pos, pos + delimiter_length - 1) == delimiter) then
            if (token != "") then
                table.insert(result, token)
                token = ""
            end
            pos = pos + delimiter_length
        else
            token = token .. string.sub(str, pos, pos)
            pos = pos + 1
        end
    end

    if (token != "") then
        table.insert(result, token)
    end

    return result
end

-- function strip(str)
--     return (str.gsub(str, "%s+$", ""))
-- end

-- robust strip for Lua 5.1: removes SC spaces plus common UF-8 invisible chars
function strip(s)
    if (s == nil) then return s end
    -- remove leading BOM if present
    s = string.gsub(s, "^\239\187\191", "")
    -- remove leading ascii whitespace, BSP (U+000), and ZWSP (U+200B)
    s = string.gsub(s, "^[%s\194\160\226\128\139]+", "")
    -- remove trailing ascii whitespace, BSP, and ZWSP
    s = string.gsub(s, "[%s\194\160\226\128\139]+$", "")
    return s
end

-- Escape special characters string
function escape_string(str)
    new_str = string.gsub(str, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    return new_str
end

function unescape_string(str)
    new_str = string.gsub(str, "%%([%(%)%.%%%+%-%*%?%[%]%^%$])", "%1")
    return new_str
end

-- epeats a string n times into a new concatenated string
function repeat_string(str, n)
    result = ""
    for i = 1, n do
        result = result .. str
    end
    return result
end

-- Positional "{{}}" template substitution -- a safer alternative to
-- string.format's %s/%d/etc for format strings that embed large blocks
-- of CSS, JS, or HTML. "%" appears constantly and legitimately in all
-- three (CSS percentages, JS modulo, URL-encoding), which forces "%%"
-- escaping every single literal "%" in the *template* text itself --
-- easy to miss even once, and a real, repeated source of "invalid
-- option '%x' to 'format'" bugs in exactly this combination (a Lua-based
-- web app templating out its own page markup). "{{" and "}}" together
-- essentially never occur unescaped in CSS/JS/HTML, so a template
-- written with this needs no escaping of its own literal content at
-- all -- only the placeholders themselves are special.
--
-- template("<p>{{}} of {{}}</p>", 3, 10) -> "<p>3 of 10</p>"
function template(s, ...)
    args = {...}
    i = 0
    return (string.gsub(s, "{{}}", function()
        i = i + 1
        return tostring(args[i])
    end))
end

-- Named-placeholder variant -- {{key}} reads `values[key]`, better
-- than positional template() once a string has more than a couple of
-- substitutions (matching them up by position gets error-prone; a name
-- at each site is self-documenting and order-independent). `%w+` here
-- is an ordinary Lua pattern inside gsub's own *pattern* argument (a
-- fixed literal this function controls, not arbitrary content a
-- caller's own template text could ever trigger) -- unrelated to the
-- %-collision problem template()/this function both exist to avoid in
-- the *substituted* content.
--
-- template_named("<p>{{name}} is {{age}}</p>", {name="Ana", age=30})
--   -> "<p>Ana is 30</p>"
function template_named(s, values)
    return (string.gsub(s, "{{(%w+)}}", function(key)
        return tostring(values[key])
    end))
end

string_utils.split = split
string_utils.strip = strip
string_utils.escape_string = escape_string
string_utils.unescape_string = unescape_string
string_utils.repeat_string = repeat_string
string_utils.starts_with = starts_with
string_utils.ends_with = ends_with
string_utils.template = template
string_utils.template_named = template_named

-- Export the module
return string_utils
