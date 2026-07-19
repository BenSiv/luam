sqlite = require("sqlite3")
_G.sqlite3 = nil

-- Define a module table
sqlite_schema = {}

function get_tables(db_path)
    db = sqlite.open(db_path)
    if (db == nil) then
        print("Error opening database")
        return nil
    end

    table_list = {}
    for row in sqlite.nrows(db, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';") do
        table.insert(table_list, row.name)
    end

    sqlite.close(db)
    return table_list
end

function get_columns(db_path, table_name)
    db = sqlite.open(db_path)
    if (db == nil) then
        error("Failed to open database at " .. db_path)
    end

    columns = {}
    query = string.format("PRAGMA table_info(%s);", table_name)

    for row in sqlite.nrows(db, query) do
        table.insert(columns, row.name)
    end

    sqlite.close(db)
    return columns
end

function get_table_info(db_path, table_name)
    db = sqlite.open(db_path)
    if (db == nil) then
        error(string.format("Failed to open database at %s", db_path))
    end

    columns = {}
    sql = string.format("PRAGMA table_info(%s);", table_name)

    for row in sqlite.nrows(db, sql) do
        columns[#columns + 1] = {
            name = row.name,
            type = row.type,
            notnull = row.notnull == 1,
            default = row.dflt_value,
            pk = row.pk == 1
        }
    end

    sqlite.close(db)
    return columns
end

function get_schema(db_path)
    db = sqlite.open(db_path)
    if (db == nil) then
        error(string.format("Failed to open database at %s", db_path))
    end

    schema = {}
    for row in sqlite.nrows(db, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';") do
        table_name = row.name
        schema[table_name] = {}

        sql = string.format("PRAGMA table_info(%s);", table_name)
        for col in sqlite.nrows(db, sql) do
            schema[table_name][#schema[table_name] + 1] = {
                name = col.name,
                type = col.type,
                notnull = col.notnull == 1,
                default = col.dflt_value,
                pk = col.pk == 1
            }
        end
    end

    sqlite.close(db)
    return schema
end

sqlite_schema.get_tables = get_tables
sqlite_schema.get_columns = get_columns
sqlite_schema.get_table_info = get_table_info
sqlite_schema.get_schema = get_schema

return sqlite_schema
