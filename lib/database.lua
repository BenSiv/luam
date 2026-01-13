utils = require("utils")
delimited_files = require("delimited_files")
dataframes = require("dataframes")
sqlite = require("sqlite3")
_G.sqlite3 = nil


-- Define a module table
database = {}

function local_query(db_path, query)
    query = query
    db = sqlite.open(db_path)
    if not is db then
        error("Error opening database")
    end
    db.exec(db, "PRAGMA busy_timeout = 5000;")

    query = utils.unescape_string(query)
    stmt, err = db.prepare(db, query)
    if not is stmt then
        db.close(db)
        error("Invalid query: " .. err)
    end

    result_rows = {}
    column_names = {}

    for row in stmt.rows(stmt) do
        table.insert(result_rows, row)
        for col_name, _ in pairs(row) do
        	table.insert(column_names, col_name)
        end
    end

    db.close(db)

    if utils.length(result_rows) == 0 then
        -- print("Query executed successfully, but no rows were returned.")
        return nil
    end

    for _, row in ipairs(result_rows) do
        for _, col_name in ipairs(column_names) do
            if row[col_name] == nil then
                row[col_name] = ""
            end
        end
    end

    return result_rows
end

function local_update(db_path, statement)
    statement = statement
    db = sqlite.open(db_path)

    if not is db then
        error("Error opening database")
    end
    db.exec(db, "PRAGMA busy_timeout = 5000;")
    
    statement = utils.unescape_string(statement)
    _, err = db.exec(db, statement)
    if is err then
        error("Error: " .. tostring(err))
    end

    db.close(db)
    return true
end

function get_sql_values(row, col_names)
	value = nil 
	sql_values = {}
	for _, col in pairs(col_names) do
		value = row[col]
		if value and value != "" then
			table.insert(sql_values, string.format("'%s'", value))
		else
			table.insert(sql_values, "NULL")
		end
	end
	return sql_values
end

function import_delimited(db_path, file_path, table_name, delimiter)    
    db = sqlite.open(db_path)
    if not is db then
        error("Error opening database")
    end

    content = delimited_files.readdlm(file_path, delimiter, true)
    if not is content then
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

    _, err = db.exec(db, insert_statement)
    if is err then
        error("Error: " .. err)
    end

    db.close(db)
    return true
end

function export_delimited(db_path, query, file_path, delimiter, header)
    results = local_query(db_path, query)

    if not is results then
    	print("Failed query")
    	return nil
    end
    
   	if utils.length(results) == 0 then
        print("No data found")
        return nil
    end

    delimited_files.writedlm(results, file_path, delimiter, header)
    return true
end

-- Escapes single quotes for safe SQLite string usage
function escape_sqlite(value)
    return string.gsub(tostring(value), "'", "''")
end

function load_df_rows(db_path, table_name, dataframe)
    -- Validate dataframe
    if not dataframes.is_dataframe(dataframe) then
        error("The provided table is not a valid dataframe.")
    end

    columns = dataframes.get_columns(dataframe)
    col_names = "'" .. table.concat(columns, "', '") .. "'"

    -- Open DB
    db = sqlite.open(db_path)
    if not is db then
        error("Error opening database")
    end

    -- Insert row by row
    for row_index, row in ipairs(dataframe) do
        sql_values = {}
        for _, col_name in ipairs(columns) do
            value = row[col_name]
            if value and value != "" then
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

        ok, err = db.exec(db, insert_sql)
        if not ok and err then
            print(string.format(
                "Row %d insert failed: %s\nSQL: %s",
                row_index, tostring(err), insert_sql
            ))
            -- continue to next row instead of stopping
        end
    end

    db.close(db)
    return true
end

function load_df(db_path, table_name, dataframe)
    -- Check if the provided dataframe is valid
    if not dataframes.is_dataframe(dataframe) then
        error("The provided table is not a valid dataframe.")
    end

    -- Get the columns from the dataframe
    columns = dataframes.get_columns(dataframe)
    
    -- Open the SQLite database
    db = sqlite.open(db_path)
    if not is db then
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
            if value and value != "" then
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
    _, err = db.exec(db, insert_statement)
    if is err then
        print("Error: " .. err)
        print("Insert Statement: " .. insert_statement)
        db.close(db)
        return nil
    end

    -- Close the database connection
    db.close(db)
    return true
end

function get_tables(db_path)
	db = sqlite.open(db_path)
    if not is db then
        print("Error opening database")
        return nil
    end
    
	table_list = {}
	for row in db.rows(db, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';") do
	    table.insert(table_list, row.name)
	end

	db.close(db)
	return table_list
end

function get_columns(db_path, table_name)
    db = sqlite.open(db_path)
    if not is db then
        error("Failed to open database at " .. db_path)
    end

    columns = {}
    query = string.format("PRAGMA table_info(%s);", table_name)

    for row in db.rows(db, query) do
        table.insert(columns, row.name)
    end

    db.close(db)
    return columns
end

function get_table_info(db_path, table_name)
    -- Open the database
    db = sqlite.open(db_path)
    if not is db then
        error(string.format("Failed to open database at %s", db_path))
    end

    -- Collect column info
    columns = {}
    sql = string.format("PRAGMA table_info(%s);", table_name)

    for row in db.rows(db, sql) do
        columns[#columns + 1] = {
            name = row.name,
            type = row.type,
            notnull = row.notnull == 1,
            default = row.dflt_value,
            pk = row.pk == 1
        }
    end

    db.close(db)
    return columns
end

function get_schema(db_path)
    db = sqlite.open(db_path)
    if not is db then
        error(string.format("Failed to open database at %s", db_path))
    end

    schema = {}
    -- Get all user tables
    for row in db.rows(db, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';") do
        table_name = row.name
        schema[table_name] = {}

        sql = string.format("PRAGMA table_info(%s);", table_name)
        for col in db.rows(db, sql) do
            schema[table_name][#schema[table_name] + 1] = {
                name = col.name,
                type = col.type,
                notnull = col.notnull == 1,
                default = col.dflt_value,
                pk = col.pk == 1
            }
        end
    end

    db.close(db)
    return schema
end

-- function get_schema(db_path)
--     schema = {}
--     tables = get_tables(db_path)
-- 
--     for _, tname in ipairs(tables) do
--         schema[tname] = get_table_info(db_path, tname)
--     end
-- 
--     return schema
-- end

function compare_schemas(old_schema, new_schema, migration_config)
    migration_config = migration_config
    migration_config = migration_config or {}
    migration_config.tables = migration_config.tables or {}
    migration_config.columns = migration_config.columns or {}

    changes = {
        tables_dropped = {},
        tables_added = {},
        tables_changed = {},
        tables_renamed = {},
        columns_renamed = {}
    }

    -- track tables dropped, renamed, or changed
    for old_tname, old_cols in pairs(old_schema) do
        mapped_new_tname = migration_config.tables[old_tname]
        new_tname = mapped_new_tname or old_tname

        if not is new_schema[new_tname] then
            table.insert(changes.tables_dropped, old_tname)
        else
            if is mapped_new_tname then
                changes.tables_renamed[old_tname] = mapped_new_tname
            end

            new_cols = new_schema[new_tname]

            old_col_map = {}
            for _, col in ipairs(old_cols) do
                old_col_map[col.name] = col
            end

            new_col_map = {}
            for _, col in ipairs(new_cols) do
                new_col_map[col.name] = col
            end

            diff = { 
                columns_added = {}, 
                columns_dropped = {}, 
                columns_changed = {}, 
                columns_renamed = {} 
            }

            column_renames = migration_config.columns[old_tname] or {}

            -- detect dropped, changed, and renamed columns
            for old_colname, oldcol in pairs(old_col_map) do
                mapped_new_colname = column_renames[old_colname]
                newcol = new_col_map[old_colname] or (mapped_new_colname and new_col_map[mapped_new_colname])

                if not is newcol then
                    table.insert(diff.columns_dropped, old_colname)
                else
                    if mapped_new_colname and old_colname != mapped_new_colname then
                        diff.columns_renamed[old_colname] = mapped_new_colname
                        changes.columns_renamed[old_tname .. "." .. old_colname] = mapped_new_colname
                    end

                    if oldcol.type != newcol.type or
                       oldcol.notnull != newcol.notnull or
                       oldcol.pk != newcol.pk or
                       oldcol.default != newcol.default then
                        diff.columns_changed[old_colname] = { old = oldcol, new = newcol }
                    end
                end
            end

            -- detect added columns (not from rename)
            for _, newcol in ipairs(new_cols) do
                if not is old_col_map[newcol.name] then
                    is_rename = false
                    for _, mapped in pairs(column_renames) do
                        if mapped == newcol.name then
                            is_rename = true
                            break
                        end
                    end
                    if not is_rename then
                        table.insert(diff.columns_added, newcol.name)
                    end
                end
            end

            if #diff.columns_added > 0 or
               #diff.columns_dropped > 0 or
               next(diff.columns_changed) != nil or
               next(diff.columns_renamed) != nil then
                changes.tables_changed[new_tname] = diff
            end
        end
    end

    -- track tables added (not from rename)
    for new_tname, _ in pairs(new_schema) do
        is_rename = false
        for _, mapped in pairs(migration_config.tables) do
            if mapped == new_tname then
                is_rename = true
                break
            end
        end

        if not is old_schema[new_tname] and not is_rename then
            table.insert(changes.tables_added, new_tname)
        end
    end

    return changes
end

database.local_query = local_query
database.local_update = local_update
database.import_delimited = import_delimited
database.export_delimited = export_delimited
database.load_df = load_df
database.get_tables = get_tables
database.get_columns = get_columns
database.get_table_info = get_table_info
database.get_schema = get_schema
database.compare_schemas = compare_schemas

-- Export the module
return database
