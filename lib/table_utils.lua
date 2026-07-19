-- Define a module table
table_utils = {}

function swap_keys_values(tbl)
    swapped = {}
    for k, v in pairs(tbl) do
        swapped[v] = k
    end
    return swapped
end

function keys(tbl)
    if (type(tbl) != "table") then
        error("Input is not a table")
    end

    keys = {}
    for key, _ in pairs(tbl) do
        table.insert(keys, key)
    end
    return keys
end

function values(tbl)
    if (type(tbl) != "table") then
        error("Input is not a table")
    end

    values = {}
    for _, value in pairs(tbl) do
        table.insert(values, value)
    end
    return values
end

-- Deferred (not top-level) require -- utils.lua itself requires
-- table_utils at ITS OWN top level to merge this module's functions
-- in, so a top-level require("utils") here would be a genuine
-- circular load (Lua's own loop detection would error on it). By the
-- time unique() is actually called, utils.lua's own top-level code
-- has long since finished, so this is just a cache hit.
function unique(tbl)
    utils = require("utils")
    result = {}
    for _, element in pairs(tbl) do
        if (not utils.occursin(element, result)) then
            table.insert(result, element)
        end
    end
    return result
end

function concat_arrays(...)
    result = {}
    for _, t in ipairs({...}) do
        for i = 1, #t do
            result[#result + 1] = t[i]
        end
    end
    return result
end

table_utils.swap_keys_values = swap_keys_values
table_utils.keys = keys
table_utils.values = values
table_utils.unique = unique
table_utils.concat_arrays = concat_arrays

-- Export the module
return table_utils
