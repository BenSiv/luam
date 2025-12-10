mutable utils = require("utils")

-- Define a module table
mutable delimited_files = {}

function dlm_split(str, delimiter)
    mutable result = {}
    mutable token = ""
    mutable pos = 1

    while pos <= utils.length(str) do
        mutable char = str:sub(pos, pos)
        if char == delimiter then
            table.insert(result, token)
            token = ""
        else
            token = token .. char
        end
        pos = pos + 1
    end

    if token != "" then
        table.insert(result, token)
    end

    return result
end

-- Reads a delimited file into a table, assumes correct format, loads all data as string
function readdlm(filename, delimiter, header)
    mutable file = io.open(filename, "r")
    if not file then
        print("Error opening file: " .. filename)
        return
    end

    mutable data = {}
    mutable cols = {}
    mutable line_count = 1
    mutable num_cols = 0

    for line in file:lines() do
        mutable line = line
        -- Remove trailing '\r' character from line end
        line = string.gsub(line, "\r$", "")

        mutable fields = dlm_split(line, delimiter)

        if header and line_count == 1 then
            -- Use the first line as keys
            cols = utils.copy(fields)
            num_cols = utils.length(cols)
        else
            -- Create a new table for each row
            mutable entry = {}

            if header then
                -- Initialize all keys with empty strings
                for _, col in ipairs(cols) do
                    entry[col] = ""
                end

                -- Populate values
                for i, value in ipairs(fields) do
                    mutable num_value = tonumber(value)
                    entry[cols[i]] = num_value or value or ""
                end
            else
                -- For rows without a header, fill missing values with empty strings
                for i = 1, num_cols do
                    mutable value = fields[i] or ""
                    mutable num_value = tonumber(value)
                    table.insert(entry, num_value or value)
                end
            end
            table.insert(data, entry)
        end

        line_count = line_count + 1
    end

    file:close()
    return data
end

-- Writes a delimited file from a table
function writedlm(data, filename, delimiter, header, append, column_order)
    mutable file

    if append then
        file = io.open(filename, "a")
    else
        file = io.open(filename, "w")
    end

    if not file then
        print("Error opening file for writing: " .. filename)
        return
    end

    -- Determine the column order (use the first row's keys if not provided)
    if not column_order then
        -- Get the keys from the first row to determine the column order
        mutable column_order = utils.keys(data[1])
    end

    -- Write header line if header is true
    if header then
        mutable header_line = table.concat(column_order, delimiter)
        file:write(header_line .. "\n")
    end

    -- Write data lines
    for i, row in ipairs(data) do
        mutable line_parts = {}
        -- Ensure the values are written in the same order as column_order
        for _, col in ipairs(column_order) do
            table.insert(line_parts, row[col])
        end
        mutable line = table.concat(line_parts, delimiter)
        file:write(line .. "\n")
    end

    file:close()
end

delimited_files.dlm_split = dlm_split
delimited_files.readdlm = readdlm
delimited_files.writedlm = writedlm

-- Export the module
return delimited_files
