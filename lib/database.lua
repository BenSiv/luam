utils = require("utils")
delimited_files = require("delimited_files")
dataframes = require("dataframes")
sqlite = require("sqlite3")
_G.sqlite3 = nil

-- Define a module table
database = {}

unpack = unpack
if (unpack == nil) then
    unpack = table.unpack
end

-- Escapes single quotes for safe SQLite string usage
function escape_sqlite(value)
    return string.gsub(tostring(value), "'", "''")
end

function local_query(db_path, query, ...)
    local_args = {...}
    if #local_args > 0 then
        for i, val in ipairs(local_args) do
            if type(val) == "string" then
                local_args[i] = escape_sqlite(val)
            end
        end
        query = string.format(query, unpack(local_args))
    end
    query = query
    db = sqlite.open(db_path)
    if (db == nil) then
        error("Error opening database: " .. tostring(db_path))
    end
    sqlite.exec(db, "PRAGMA busy_timeout = 5000;")
    -- WAL mode is a persistent property of the database file itself, not
    -- this connection -- re-issuing it on every open (this module opens a
    -- fresh connection per call, see local_update below) is redundant
    -- after the first time but harmless, and guarantees it's actually set
    -- rather than depending on some other code path having done it first.
    -- Lets readers and a writer proceed concurrently instead of blocking
    -- each other, which matters once more than one client (e.g. several
    -- browser tabs against the same store) is hitting the database at once.
    sqlite.exec(db, "PRAGMA journal_mode = WAL;")

    stmt, err = sqlite.prepare(db, query)
    if (stmt == nil) then
        err_msg = tostring(err)
        if (type(err) == "number") then
            -- Try to get more info
            db_err = sqlite.errmsg(db)
            if (db_err != nil) then
                err_msg = err_msg .. " (" .. db_err .. ")"
            end
        end
        sqlite.close(db)
        error("Invalid query on " .. tostring(db_path) .. ": " .. err_msg .. "\nQuery: " .. query)
    end

    result_rows = {}
    column_names = {}

    -- Try to get column names from statement metadata if available
    if (sqlite.stmt != nil and sqlite.stmt.get_names != nil) then
        column_names = sqlite.stmt.get_names(stmt)
        if (column_names == nil) then
            column_names = {}
        end
    end

    -- Use nrows (map with names) if available, otherwise rows (indexed values)
    iterator_choice = nil
    
    if (sqlite.stmt != nil and sqlite.stmt.nrows != nil) then
        iterator_choice = sqlite.stmt.nrows
    elseif (sqlite.stmt != nil and sqlite.stmt.rows != nil) then
        iterator_choice = sqlite.stmt.rows
    elseif (stmt.rows != nil) then
        iterator_choice = function(s) return s.rows(s) end
    end

    if (iterator_choice != nil) then
        for row in iterator_choice(stmt) do
            table.insert(result_rows, row)
            if (#column_names == 0) then
                for k, _ in pairs(row) do
                     table.insert(column_names, k)
                end
            end
        end
    end

    sqlite.close(db)

    if (#result_rows == 0) then
        -- print("Query executed successfully, but no rows were returned.")
        return nil, column_names
    end

    -- ensure all columns are present (fill nils)
    for _, row in ipairs(result_rows) do
        for _, col_name in ipairs(column_names) do
            if (row[col_name] == nil) then
                row[col_name] = ""
            end
        end
    end

    return result_rows, column_names
end

function local_update(db_path, statement, ...)
    local_args = {...}
    if #local_args > 0 then
        for i, val in ipairs(local_args) do
            if type(val) == "string" then
                local_args[i] = escape_sqlite(val)
            end
        end
        statement = string.format(statement, unpack(local_args))
    end
    statement = statement
    db = sqlite.open(db_path)

    if (db == nil) then
        error("Error opening database: " .. tostring(db_path))
    end
    sqlite.exec(db, "PRAGMA busy_timeout = 5000;")
    sqlite.exec(db, "PRAGMA journal_mode = WAL;")

    result = sqlite.exec(db, statement)
    if (result != sqlite.OK) then
        error("Error executing statement: " .. tostring(sqlite.errmsg(db)))
    end

    sqlite.close(db)
    return true
end

function get_sql_values(row, col_names)
    value = nil 
    sql_values = {}
    for _, col in pairs(col_names) do
        value = row[col]
        if (value != nil and value != "") then
            table.insert(sql_values, string.format("'%s'", value))
        else
            table.insert(sql_values, "NULL")
        end
    end
    return sql_values
end

function import_delimited(db_path, file_path, table_name, delimiter)    
    db = sqlite.open(db_path)
    if (db == nil) then
        error("Error opening database")
    end

    content = delimited_files.readdlm(file_path, delimiter, true)
    if (content == nil) then
        error("Error reading delimited file")
    end
    
    col_names = utils.keys(content[1]) -- problematic if first row does not have all the columns
    col_row = table.concat(col_names, "', '")
    insert_statement = string.format("INSERT INTO %s ('%s') VALUES ", table_name, col_row)

    value_rows = {}
    for _, row in pairs(content) do
        sql_values = get_sql_values(row, col_names)
        row_values = string.format("(%s)", table.concat(sql_values, ", "))
        table.insert(value_rows, row_values)
    end
    insert_statement = insert_statement .. table.concat(value_rows, ", ") .. ";"

    result = sqlite.exec(db, insert_statement)
    if (result != sqlite.OK) then
        error("Error: " .. tostring(sqlite.errmsg(db)))
    end

    sqlite.close(db)
    return true
end

function export_delimited(db_path, query, file_path, delimiter, header)
    results, col_names = local_query(db_path, query)

    if (results == nil) then
        print("Failed query")
        return nil
    end
    
    if (utils.length(results) == 0) then
        print("No data found")
        return nil
    end

    delimited_files.writedlm(results, file_path, delimiter, header, false, col_names)
    return true
end

function load_df_rows(db_path, table_name, dataframe)
    -- Validate dataframe
    if (not dataframes.is_dataframe(dataframe)) then
        error("The provided table is not a valid dataframe.")
    end

    columns = dataframes.get_columns(dataframe)
    col_names = "'" .. table.concat(columns, "', '") .. "'"

    -- Open DB
    db = sqlite.open(db_path)
    if (db == nil) then
        error("Error opening database")
    end

    -- Insert row by row
    for row_index, row in ipairs(dataframe) do
        sql_values = {}
        for _, col_name in ipairs(columns) do
            value = row[col_name]
            if (value != nil and value != "") then
                table.insert(sql_values, string.format("'%s'", escape_sqlite(value)))
            else
                table.insert(sql_values, "NULL")
            end
        end

        insert_sql = string.format(
            "INSERT INTO %s (%s) VALUES (%s);",
            table_name,
            col_names,
            table.concat(sql_values, ", ")
        )

        result = sqlite.exec(db, insert_sql)
        if (result != sqlite.OK) then
            print(string.format(
                "Row %d insert failed: %s\nSQL: %s",
                row_index, tostring(sqlite.errmsg(db)), insert_sql
            ))
            -- continue to next row instead of stopping
        end
    end

    sqlite.close(db)
    return true
end

function load_df(db_path, table_name, dataframe)
    -- Check if the provided dataframe is valid
    if (not dataframes.is_dataframe(dataframe)) then
        error("The provided table is not a valid dataframe.")
    end

    -- Get the columns from the dataframe
    columns = dataframes.get_columns(dataframe)
    
    -- Open the SQLite database
    db = sqlite.open(db_path)
    if (db == nil) then
        print("Error opening database")
        return nil
    end

    -- Prepare column names for the insert statement
    col_row = table.concat(columns, "', '")
    insert_statement = string.format("INSERT INTO %s ('%s') VALUES ", table_name, col_row)

    -- Prepare the data rows for insertion
    value_rows = {}
    for _, row in ipairs(dataframe) do
        sql_values = {}
        -- Get values for each column in the row
        for _, col_name in ipairs(columns) do
            value = row[col_name]
            if (value != nil and value != "") then
                table.insert(sql_values, string.format("'%s'", escape_sqlite(value)))
            else
                table.insert(sql_values, "NULL")
            end
        end
        -- Format the row values
        row_values = string.format("(%s)", table.concat(sql_values, ", "))
        table.insert(value_rows, row_values)
    end

    -- Complete the insert statement
    insert_statement = insert_statement .. table.concat(value_rows, ", ") .. ";"

    -- Execute the insert statement
    result = sqlite.exec(db, insert_statement)
    if (result != sqlite.OK) then
        print("Error: " .. tostring(sqlite.errmsg(db)))
        print("Insert Statement: " .. insert_statement)
        sqlite.close(db)
        return nil
    end

    -- Close the database connection
    sqlite.close(db)
    return true
end


database.local_query = local_query
database.local_update = local_update
database.import_delimited = import_delimited
database.export_delimited = export_delimited
database.load_df = load_df
database.escape_sqlite = escape_sqlite

-- Export the module
return database
