-- delimited_files library for LuaM

-- Define a module table
delimited_files = {}

function dlm_split(str, delimiter)
    result = {}
    token = ""
    pos = 1

    while pos <= string.len(str) do
        char = string.sub(str, pos, pos)
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

-- eads a delimited file into a table, assumes correct format, loads all data as string
function readdlm(filename, delimiter, header)
    file = io.open(filename, "r")
    if file == nil then
        print("Error opening file: " .. filename)
        return
    end

    data = {}
    cols = {}
    line_count = 1
    num_cols = 0

    for line in io.lines(file) do
        line = line
        -- emove trailing '\r' character from line end
        line = string.gsub(line, "\r$", "")

        fields = dlm_split(line, delimiter)

        if header != nil and header and line_count == 1 then
            -- Use the first line as keys
            for i, v in ipairs(fields) do cols[i] = v end
            num_cols = #cols
        else
            -- Create a new table for each row
            entry = {}

            if header != nil and header then
                -- nitialize all keys with empty strings
                for _, col in ipairs(cols) do
                    entry[col] = ""
                end

                -- Populate values
                for i, value in ipairs(fields) do
                    num_value = tonumber(value)
                    entry[cols[i]] = num_value or value or ""
                end
            else
                -- For rows without a header, fill missing values with empty strings
                for i = 1, num_cols do
                    value = fields[i] or ""
                    num_value = tonumber(value)
                    table.insert(entry, num_value or value)
                end
            end
            table.insert(data, entry)
        end

        line_count = line_count + 1
    end

    io.close(file)
    return data
end

-- Writes a delimited file from a table
function writedlm(data, filename, delimiter, header, append, column_order)
    file = nil 

    if append != nil and append then
        file = io.open(filename, "a")
    else
        file = io.open(filename, "w")
    end

    if file == nil then
        print("Error opening file for writing: " .. filename)
        return
    end

    -- Determine the column order (use the first row's keys if not provided)
    if column_order == nil then
        -- Get the keys from the first row to determine the column order
        column_order = {}
        for k, v in pairs(data[1]) do table.insert(column_order, k) end
    end

    -- Write header line if header is true
    if header != nil and header then
        header_line = table.concat(column_order, delimiter)
        io.write(file, header_line .. "\n")
    end

    -- Write data lines
    for i, row in ipairs(data) do
        line_parts = {}
        -- Ensure the values are written in the same order as column_order
        for _, col in ipairs(column_order) do
            table.insert(line_parts, row[col])
        end
        line = table.concat(line_parts, delimiter)
        io.write(file, line .. "\n")
    end

    io.close(file)
end

delimited_files.dlm_split = dlm_split
delimited_files.readdlm = readdlm
delimited_files.writedlm = writedlm

-- Export the module
return delimited_files
