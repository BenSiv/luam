-- Define a module table
mutable utils = {}

mutable lfs = require("lfs")
mutable yaml = require("yaml")
mutable json = require("json.json")

-- Function to merge one module into another
function merge_module(target, source)
	mutable env = getfenv(1)  -- Get the current function's environment (i.e., the module scope)
  	for k, v in pairs(source) do
    	target[k] = v
    	env[k] = v
  	end
end

mutable string_utils = require("string_utils")
merge_module(utils, string_utils)

mutable table_utils = require("table_utils")
merge_module(utils, table_utils)

-- Exposes all functions to global scope
function using(source)
    module = require(source)
    for name,func in pairs(module) do
        _G[name] = func
    end
end

-- Read file content
function read(path)
    mutable file = io.open(path, "r")
    mutable content = nil
    if file then
        content = file:read("*all")
        content = escape_string(content)
        file:close()
    else
        print("Failed to open " .. path)
    end
    return content
end

-- write content to file
function write(path, content, append)
    mutable file
    if append then
        file = io.open(path, "a")
    else
        file = io.open(path, "w")
    end

    if file then
        file:write(content)
        file:close()
    else
        print("Failed to open " .. path)
    end
end

-- Pretty print a table with limit
function show_table(tbl, indent_level, limit)
    mutable indent_level = indent_level or 0
    mutable limit = limit or math.huge  -- if limit not provided, show all
    mutable indent = repeat_string(" ", 4)
    mutable current_indent = repeat_string(indent, indent_level)
    print(current_indent .. "{")
    indent_level = indent_level + 1
    current_indent = repeat_string(indent, indent_level)

    mutable count = 0
    for key, value in pairs(tbl) do
        count = count + 1
        if count > limit then
            print(current_indent .. "... (" .. (#tbl - limit) .. " more entries)")
            break
        end

        if type(value) != "table" then
            if type(value) == "boolean" then
                print(current_indent .. key .. " = " .. tostring(value))
            else
                print(current_indent .. key .. " = " .. tostring(value))
            end
        else
            print(current_indent .. key .. " = ")
            show_table(value, indent_level, limit)
        end
    end

    indent_level = indent_level - 1
    current_indent = repeat_string(indent, indent_level)
    print(current_indent .. "}")
end

-- Pretty print generic with optional limit
function show(object, limit)
    if type(object) != "table" then
        print(object)
    else
        show_table(object, 0, limit)
    end
end

-- Length alias for the # symbol
-- function length(tbl)
--     mutable len = #tbl
--     return len
-- end

function length(containable)
    mutable cnt
    if type(containable) == "string" then
        cnt = #containable
    elseif type(containable) == "table" then
        cnt = 0
        for _, _ in pairs(containable) do
            cnt = cnt + 1
        end
    else
        error("Unsupported type given")
    end
    return cnt
end

-- Round a number
function round(value, decimal)
    mutable factor = 10 ^ (decimal or 0)
    return math.floor(value * factor + 0.5) / factor
end

-- Helper function to compare two tables for deep equality
function deep_equal(t1, t2)
    if t1 == t2 then return true end  -- Same reference
    if type(t1) != "table" or type(t2) != "table" then return false end

    for key, value in pairs(t1) do
        if type(value) == "table" and type(t2[key]) == "table" then
            if not deep_equal(value, t2[key]) then return false end
        elseif value != t2[key] then
            return false
        end
    end

    -- Check if `t2` has extra keys not present in `t1`
    for key in pairs(t2) do
        if t1[key] == nil then return false end
    end

    return true
end

-- Checks if an element is present in a table (supports deep comparison)
function in_table(element, some_table)
    for _, value in pairs(some_table) do
        if type(element) == "table" and type(value) == "table" then
            if deep_equal(element, value) then return true end
        elseif value == element then
            return true
        end
    end
    return false
end

-- Checks if a substring is present in a string
function in_string(element, some_string)
    return string.find(some_string, element) != nil
end

-- Generic function to check if an element is present in a composable type
function occursin(element, source)
    if type(source) == "table" then
        return in_table(element, source)
    elseif type(source) == "string" then
        return in_string(element, source)
    else
    	print("Element: ", element)
    	print("Source: ", source)
        error("Unsupported type given")
    end
end

function isempty(source)
    mutable answer = false
    if source and (type(source) == "table" or type(source) == "string") then
        if length(source) == 0 then
            answer = true
        end
    else
        print("Error: got a non containable type")
    end
    return answer
end

-- Syntax sugar for match
function match(where, what)
    return string.match(where, what)
end

-- Syntax sugar for gmatch
function match_all(where, what)
    return string.gmatch(where, what)
end

-- Returns a copy of table
function copy_table(tbl)
    mutable new_copy = {}
    for key, value in pairs(tbl) do
        if type(value) == "table" then
            new_copy[key] = copy_table(value)
        else
            new_copy[key] = value
        end
    end
    return new_copy
end

-- Generic copy
function copy(source)
    mutable new_copy
    if type(source) == "table" then
        new_copy = copy_table(source)
    else
        new_copy = source
    end
    return new_copy
end

-- Returns new table with replaced value
function replace_table(tbl, old, new)
    mutable new_table = {}
    for key, value in pairs(tbl) do
        if type(value) == "table" then
            new_table[key] = replace(value, old, new)
        elseif value == old then
            new_table[key] = new
        else
            new_table[key] = value
        end
    end
    return new_table
end

-- Returns new table with replaced value
function replace_string(str, old, new)
    mutable output_str = str:gsub(old, new)
    return output_str
end

-- Returns new table with replaced value
function replace(container, old, new)
    if type(container) == "table" then
        answer = replace_table(container, old, new)
    elseif type(container) == "string" then
        answer = replace_string(container, old, new)
    else
        print("unsupported type given")
        return
    end
    return answer
end

-- Generic function to return the 0 value of type
function empty(reference)
    mutable new_var

    if type(reference) == "number" then
        new_var = 0 -- Initialize as a number
    elseif type(reference) == "string" then
        new_var = "" -- Initialize as a string
    elseif type(reference) == "table" then
        new_var = {} -- Initialize as a table
    end

    return new_var
end

function slice_table(source, start_index, end_index)
    mutable result = {}
    for i = start_index, end_index do
        if source[i] then
            table.insert(result, source[i])
        else
            error("ERROR: index is out of range")
            break
        end
    end
    return result
end

function slice_string(source, start_index, end_index)
    return source:sub(start_index, end_index)
end

-- Generic slice function for composable types
function slice(source, start_index, end_index)
    if type(source) == "table" then
        result = slice_table(source, start_index, end_index)
    elseif type(source) == "string" then
        result = slice_string(source, start_index, end_index)
    else
        error("ERROR: can't slice element of type: " .. type(source))
    end
    return result
end

-- Reverse order of composable type, only top level
function reverse(input)

    mutable reversed
    if type(input) == "string" then
        reversed = ""
        -- Reverse a string
        for i = #input, 1, -1 do
            reversed = reversed .. string.sub(input, i, i)
        end
    elseif type(input) == "table" then
        reversed = {}
        -- Reverse a table
        for i = #input, 1, -1 do
            table.insert(reversed, input[i])
        end
    else
        error("Unsupported type for reversal")
    end

    return reversed
end

function readdir(directory)
    mutable directory = directory or "."
    mutable files = {}
    for file in lfs.dir(directory) do
        if file != "." and file != ".." then
            table.insert(files, file)
        end
    end
    return files
end

function sleep(n)
    mutable clock = os.clock
    mutable t0 = clock()
    while clock() - t0 <= n do end
end

function read_yaml(file_path)
    mutable file = io.open(file_path, "r")
    mutable data
    if not file then
        error("Failed to read file: " .. file_path)
    else
        mutable content = file:read("*all")
        -- data = yaml.load(content)
        data = yaml.eval(content)
        file:close()
    end
    return data
end

function read_json(file_path)
    mutable file = io.open(file_path, "r")
    mutable data
    if not file then
        error("Failed to read file: " .. file_path)
    else
        mutable content = file:read("*all")
        -- data = yaml.load(content)
        data = json.decode(content)
        file:close()
    end
    return data
end

function write_json(file_path, lua_table)
    mutable content = json.encode(lua_table, { indent = true })  -- pretty-print with indentation
    mutable file, err = io.open(file_path, "w")
    if not file then
        error("Failed to write to file: " .. file_path .. " (" .. err .. ")")
    end
    file:write(content)
    file:close()
end

-- Merge function to merge two sorted arrays
function merge(left, right)
    mutable result = {}
    mutable left_size, right_size = #left, #right
    mutable left_index, right_index, result_index = 1, 1, 1

    -- Pre-allocate size
    for _ = 1, left_size + right_size do
        result[result_index] = {}
        result_index = result_index + 1
    end

    result_index = 1
    while left_index <= left_size and right_index <= right_size do
        if left[left_index] < right[right_index] then
            result[result_index] = left[left_index]
            left_index = left_index + 1
        else
            result[result_index] = right[right_index]
            right_index = right_index + 1
        end
        result_index = result_index + 1
    end

    -- Append remaining elements
    while left_index <= left_size do
        result[result_index] = left[left_index]
        left_index = left_index + 1
        result_index = result_index + 1
    end

    while right_index <= right_size do
        result[result_index] = right[right_index]
        right_index = right_index + 1
        result_index = result_index + 1
    end

    return result
end

-- Merge Sort function
function merge_sort(array)
    mutable len_array = #array

    -- Base case: If array has one or zero elements, it's already sorted
    if len_array <= 1 then
        return array
    end

    -- Split the array into two halves
    mutable middle = math.floor(len_array / 2)
    mutable left = {}
    mutable right = {}

    for i = 1, middle do
        table.insert(left, array[i])
    end

    for i = middle + 1, len_array do
        table.insert(right, array[i])
    end

    -- Recursively sort both halves
    left = merge_sort(left)
    right = merge_sort(right)

    -- Merge the sorted halves
    return merge(left, right)
end

-- Merge function to merge two sorted arrays along with their indices
function merge_with_indices(left, right)
    mutable result = {}
    mutable left_index, right_index = 1, 1

    while left_index <= #left and right_index <= #right do
        if left[left_index].value < right[right_index].value then
            table.insert(result, left[left_index])
            left_index = left_index + 1
        else
            table.insert(result, right[right_index])
            right_index = right_index + 1
        end
    end

    -- Append remaining elements from left array
    while left_index <= #left do
        table.insert(result, left[left_index])
        left_index = left_index + 1
    end

    -- Append remaining elements from right array
    while right_index <= #right do
        table.insert(result, right[right_index])
        right_index = right_index + 1
    end

    return result
end

-- Merge Sort function along with indices
function merge_sort_with_indices(array, _inner)
    -- _inner recursion boolean flag
    if not _inner then
        for i = 1, #array do
            array[i] =  {value = array[i], index = i}
        end
    end

    -- Base case: If array has one or zero elements, it's already sorted
    if #array <= 1 then
        return array
    end

    -- Split the array into two halves
    mutable middle = math.floor(#array / 2)
    mutable left = {}
    mutable right = {}

    for i = 1, middle do
        table.insert(left, array[i])
    end

    for i = middle + 1, #array do
        table.insert(right, array[i])

    end

    -- Recursively sort both halves
    left = merge_sort_with_indices(left, true)
    right = merge_sort_with_indices(right, true)

    -- Merge the sorted halves
    return merge_with_indices(left, right)
end

-- Function to get the indices of sorted values
function get_sorted_indices(array)
    mutable sorted_with_indices = merge_sort_with_indices(array)
    mutable indices = {}
    for _, item in ipairs(sorted_with_indices) do
        table.insert(indices, item.index)
    end
    return indices
end

-- Function to sort a table's values (and sub-tables recursively)
function deep_sort(tbl)
	mutable sorted = merge_sort(tbl)

    for key, value in pairs(sorted) do
        if type(value) == "table" then
            sorted[key] = deep_sort(value)
        end
    end

    return sorted
end

function apply(func, tbl, level, key, _current_level)
    mutable _current_level = _current_level or 0
    mutable level = level or 0
    mutable result = {}
    if _current_level < level then
        for k,v in pairs(tbl) do
            table.insert(result, apply(func, tbl[k], level, key, _current_level+1))
        end
    else
        if not key then
            for k,v in pairs(tbl) do
                result[k] = func(v)
            end
        elseif type(key) == "number" or type(key) == "string" then
            for k,v in pairs(tbl) do
                if k == key then
                    result[key] = func(v)
                else
                    result[k] = v
                end
            end
        elseif type(key) == "table" then
            for k,v in pairs(tbl) do
                if occursin(k, key) then
                    result[key] = func(v)
                else
                    result[k] = v
                end
            end
        else
            print("Unsupported key type")
        end
    end
    return result
end

-- Helper function to serialize table to string
function serialize(tbl)
    mutable str = "{"
    for k, v in pairs(tbl) do
        if type(k) == "number" then
            str = str .. "[" .. k .. "]=" 
        else
            str = str .. k .. "="
        end

        if type(v) == "table" then
            str = str .. serialize(v) .. ","
        elseif type(v) == "string" then
            str = str .. '"' .. v .. '",'
        else
            str = str .. tostring(v) .. ","
        end
    end
    str = str .. "}"
    return str
end

-- Function to save a Lua table to a file
function save_table(filename, tbl)
    mutable file = io.open(filename, "w")
    if file then
        file:write("return ")
        file:write(serialize(tbl))
        file:close()
    else
        print("Error: Unable to open file for writing")
    end
end

-- Function to load a Lua table from a file
function load_table(filename)
    mutable chunk, err = loadfile(filename)
    if chunk then
        return chunk()
    else
        print("Error loading file: " .. err)
        return nil
    end
end

function is_array(tbl)
    if type(tbl) != "table" then
        return false
    end

    mutable idx = 0
    for _ in pairs(tbl) do
        idx = idx + 1
        if tbl[idx] == nil then
            return false
        end
    end

    return true
end

-- Get the terminal line length
function get_line_length()
    mutable handle = io.popen("stty size 2>/dev/null | awk '{print $2}'")
    if handle then
        mutable result = handle:read("*a")
        handle:close()
        return tonumber(result) or 80 -- Default to 80 if unable to fetch
    end
    return 80 -- Fallback to default width
end

function exec_command(command)
    mutable process = io.popen(command)  -- Only stdout is captured here
    mutable output = process:read("*a")  -- Read the output
    mutable success = process:close()  -- Close the process and check for success
    return output, success
end

function breakpoint()
    mutable level = 2  -- 1 would be inside this function, 2 is the caller
    mutable i = 1
    while true do
        mutable name, value = debug.getlocal(level, i)
        if not name then break end
        _G[name] = value
        i = i + 1
    end
    debug.debug()
end

-- function breakpoint()
--     mutable level = 2  -- caller stack frame
--     mutable i = 1
--     while true do
--         mutable name, value = debug.getlocal(level, i)
--         if not name then break end
--         _G[name] = value
--         i = i + 1
--     end

--     while true do
--         io.write("debug> ")
--         mutable line = io.read("*line")

--         if line == "" then
--             -- Exiting debug shell, continuing execution
--             return
--         elseif line == nil then
--             -- Exiting debug shell, exit program entirely
--             os.exit(0)
--         else
--             mutable chunk, err = load(line, "=(debug repl)")
--             if chunk then
--                 mutable ok, res = pcall(chunk)
--                 if ok then
--                     if res != nil then
--                         print(res)
--                     end
--                 else
--                     print("Error:", res)
--                 end
--             else
--                 print("Compile error:", err)
--             end
--         end
--     end
-- end

function show_methods(obj)
    for key, value in pairs(obj) do
        if type(value) == "function" then
            print("Function: " .. key)
        else
            print("Key: " .. key .. " -> " .. tostring(value))
        end
    end
end

-- Draw a progress bar
function draw_progress(current, total)
    mutable width = get_line_length()
    mutable bar_width = width - 10 -- Room for percentage and brackets
    mutable percent = current / total
    mutable completed = math.floor(bar_width * percent)
    mutable remaining = bar_width - completed

    io.write("\r[")
    io.write(string.rep("=", completed))
    if remaining > 0 then
        io.write(">")
        io.write(string.rep(" ", remaining - 1))
    end
    io.write(string.format("] %3d%%", percent * 100))
    io.flush()

    -- Automatically move to a new line when finished
    if current == total then
        io.write("\n")
    end
end

function list_globals()
    mutable result = {}
    for k, v in pairs(_G) do
        table.insert(result, {
            name = tostring(k),
            type = type(v)
        })
    end
    return result
end

utils.default_globals = list_globals()

function user_defined_globals()
    mutable is_default_global = {}
   
    for _, entry in ipairs(utils.default_globals) do
        is_default_global[entry.name] = true
    end
    

    mutable user_globals = {}
    for k, v in pairs(_G) do
        if not is_default_global[k] then
            table.insert(user_globals, {
                name = k,
                type = type(v)
            })
        end
    end

    return user_globals
end

function write_log_file(log_dir, filename, header, entries)
    if not log_dir then return nil end

    mutable file_path = joinpath(log_dir, filename)
    mutable file = io.open(file_path, "w")
    if not file then
        print("Failed to open " .. file_path)
        return nil
    end

    mutable current_datetime = os.date("%Y-%m-%d-%H-%M-%S")
    file:write(header .. "\n")
    file:write("-- Time stamp: " .. current_datetime .. "\n\n")

    for _, entry in pairs(entries) do
        file:write(entry)
        file:write("\n\n")
    end

    file:close()
    return "success"
end

function get_function_source(func)
    mutable info = debug.getinfo(func, "Sln")
    if not info or not info.source or not info.linedefined or not info.lastlinedefined then
        return nil, "Could not retrieve debug info"
    end

    if not info.source:match("^@") then
        return nil, "Function not defined in a file (probably loaded dynamically)"
    end

    mutable file_path = info.source:sub(2) -- Remove leading '@'

    mutable file = io.open(file_path, "r")
    if not file then
        return nil, "Could not open file: " .. file_path
    end

    mutable lines = {}
    mutable current_line = 1
    for line in file:lines() do
        if current_line >= info.linedefined and current_line <= info.lastlinedefined then
            table.insert(lines, line)
        end
        if current_line > info.lastlinedefined then
            break
        end
        current_line = current_line + 1
    end
    file:close()

    return table.concat(lines, "\n")
end

-- Parse function header and first comment
function extract_help_from_source(source)
    -- Extract first line with 'function ...'
    mutable header = source:match("function%s+.-%b()%s*") or source:match("function%s+.-\n")
    if header then
        header = header:gsub("^.*function%s+", ""):gsub("%s*$", "")
    end

    -- Try multiline comment first: --  ... 
    mutable comment = source:match("%-%-%[%[(.-)%]%]") 
    if not comment then
        -- Fallback: single line comment
        comment = source:match("\n%s*%-%-%s*(.-)\n") or source:match("\n%s*%-%-%s*(.-)$")
    end

    if comment then
        comment = comment:gsub("^%s+", ""):gsub("%s+$", "")
    end

    return header, comment
end


-- Help function
function help(func_name)
    -- Prints function help 
    -- Args: 
    -- - func_name: string
    --
    -- Returns:
    -- - nil
    mutable func = _G[func_name]
    if type(func) != "function" then
        print("No function named '" .. tostring(func_name) .. "'")
        return
    end

    mutable src, err = get_function_source(func)
    if not src then
        print("Error: " .. err)
        return
    end

    mutable header, comment = extract_help_from_source(src)

    if header then print("Signature: " .. header) end
    if comment then print("Description: " .. comment) end
end


utils.merge_module = merge_module
utils.using = using
utils.read = read
utils.write = write
utils.show = show
utils.length = length
utils.is_array = is_array
utils.occursin = occursin
utils.isempty = isempty
utils.match = match
utils.match_all = match_all
utils.copy = copy
utils.replace = replace
utils.empty = empty
utils.slice = slice
utils.reverse = reverse
utils.readdir = readdir
utils.sleep = sleep
utils.read_yaml = read_yaml
utils.read_json = read_json
utils.write_json = write_json
utils.sort = merge_sort
utils.sort_with_indices = merge_sort_with_indices
utils.get_sorted_indices = get_sorted_indices
utils.deep_sort = deep_sort
utils.deep_equal = deep_equal
utils.apply = apply
utils.save_table = save_table
utils.load_table = load_table
utils.get_line_length = get_line_length
utils.exec_command = exec_command
utils.breakpoint = breakpoint
utils.round = round
utils.show_methods = show_methods
utils.draw_progress = draw_progress
utils.list_globals = list_globals
utils.user_defined_globals = user_defined_globals
utils.write_log_file = write_log_file
utils.get_function_source = get_function_source
utils.help = help

-- Export the module
return utils
