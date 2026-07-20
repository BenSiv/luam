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

function sqlite_query(db_path, query, ...)
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
    -- fresh connection per call, see sqlite_update below) is redundant
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

function sqlite_update(db_path, statement, ...)
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

    -- Read while still on the same connection that just did the insert --
    -- sqlite3_last_insert_rowid is connection-scoped (a value read after
    -- this db handle closes, or on a different one entirely, would be
    -- meaningless), which is exactly why this is safe under concurrent
    -- writers where SELECT MAX(id) is not: each caller's own db-per-call
    -- connection here only ever sees its own most recent insert,
    -- regardless of what other connections have inserted concurrently.
    -- 0 if `statement` didn't insert an AUTOINCREMENT row -- matches
    -- sqlite3_last_insert_rowid's own convention (mirrors
    -- mariadb_update's insert_id return for the same reason).
    insert_id = sqlite.last_insert_rowid(db)

    sqlite.close(db)
    return true, insert_id
end

-- ---------------------------------------------------------------------
-- MariaDB support (lib/mariadb/lmariadb.c) -- see doc/mariadb-
-- migration.md in the platform-wip repo for why this exists and how it
-- fits into that migration's phases. Lives in this same file (not a
-- separate lib/mariadb.lua) specifically to avoid a real naming
-- collision: a Lua module file named "mariadb.lua" and the native
-- binding it requires are BOTH resolved via require("mariadb"),
-- which recurses into itself mid-load ("loop or previous error loading
-- module 'mariadb'") -- confirmed directly while first writing this as
-- a standalone file. Matches this file's own existing sqlite/database
-- naming split (native module "sqlite3", wrapper module "database")
-- instead of repeating the same collision under a different name.
--
-- mariadb_native is loaded lazily (only when a mariadb_* function is
-- actually called), not at this file's own top level the way `sqlite =
-- require("sqlite3")` above is -- libmariadb-dev is a genuinely
-- optional build-time dependency (unlike sqlite, which is vendored and
-- always present), so an unconditional top-level require here would
-- break loading this whole module -- and therefore every caller's
-- sqlite functions too -- on any system that doesn't have it built.
mariadb_native = nil

function get_mariadb_native()
    if mariadb_native == nil then
        mariadb_native = require("mariadb")
    end
    return mariadb_native
end

-- One cached connection per unique descriptor, reused across calls
-- within this process -- opening a real network+auth round-trip per
-- query (mirroring sqlite_query/sqlite_update's own per-call sqlite.open)
-- would be a severe latency regression a local SQLite open() never
-- has. Not full pooling (one connection per descriptor per process,
-- not a pool of many) -- sufficient for today's CGI-per-request model
-- (reused across the several queries one request makes) and still
-- correct if task #57's persistent-process work ever lets one process
-- outlive a single request, without needing to change this code.
_mariadb_connections = {}

function mariadb_connection_key(descriptor)
    return tostring(descriptor.host) .. ":" .. tostring(descriptor.port) ..
        ":" .. tostring(descriptor.user) .. ":" .. tostring(descriptor.database)
end

-- Returns a live, cached connection for this descriptor -- opens one if
-- none is cached yet, or replaces one that's gone stale (detected via
-- mariadb.ping rather than waiting for the next real query to fail on it).
function get_mariadb_connection(descriptor)
    native = get_mariadb_native()
    key = mariadb_connection_key(descriptor)
    cached = _mariadb_connections[key]
    if cached != nil and native.ping(cached) == true then
        return cached, nil
    end
    if cached != nil then
        native.close(cached)
        _mariadb_connections[key] = nil
    end

    conn, err = native.connect(
        descriptor.host, descriptor.port, descriptor.user, descriptor.password, descriptor.database
    )
    if conn == nil then
        return nil, err
    end

    -- MariaDB's default sql_mode treats backslash as a string-literal
    -- escape character (\n -> newline, \\ -> \, etc.), independent of
    -- whichever quote-escaping convention (doubling vs backslash) a
    -- caller uses -- a value containing a literal backslash-letter
    -- sequence (a Windows path, a regex, LaTeX) would silently come
    -- back transformed on read otherwise, even though the string
    -- boundary itself was never at risk. NO_BACKSLASH_ESCAPES (a real,
    -- standard MariaDB/MySQL SQL mode flag) turns backslash back into
    -- an ordinary character in string literals, matching SQL-standard/
    -- SQLite behavior exactly -- appended via CONCAT, not a flat SET,
    -- so this doesn't clobber whatever other sql_mode flags the server
    -- defaults to (e.g. STRICT_TRANS_TABLES). This is what lets
    -- platform-wip's db.quote/db.literal use the exact same
    -- quote-doubling logic for both backends with no per-engine branch.
    native.exec(conn, "SET SESSION sql_mode = CONCAT(@@sql_mode, ',NO_BACKSLASH_ESCAPES');")

    _mariadb_connections[key] = conn
    return conn, nil
end

-- Real mysql_real_escape_string (connection/charset-aware), not a naive
-- quote-doubling gsub the way escape_sqlite above is. Requires a live
-- connection -- MariaDB's escaping is connection-state-aware, unlike
-- escape_sqlite's connection-free pure function.
function escape_mariadb(descriptor, value)
    native = get_mariadb_native()
    conn, err = get_mariadb_connection(descriptor)
    if conn == nil then
        error("Error connecting to MariaDB: " .. tostring(err))
    end
    return native.escape(conn, tostring(value))
end

-- database.mariadb_query(descriptor, query, ...) -> rows, column_names
-- Same %s-interpolation-with-escaped-varargs convention as sqlite_query
-- above -- see doc/mariadb-migration.md's "Design decisions" section on
-- bound parameters as a later, additive option, not required up front.
function mariadb_query(descriptor, query, ...)
    native = get_mariadb_native()
    local_args = {...}
    if #local_args > 0 then
        for i, val in ipairs(local_args) do
            if type(val) == "string" then
                local_args[i] = escape_mariadb(descriptor, val)
            end
        end
        query = string.format(query, unpack(local_args))
    end

    conn, err = get_mariadb_connection(descriptor)
    if conn == nil then
        error("Error connecting to MariaDB: " .. tostring(err))
    end

    rows, err = native.query(conn, query)
    if rows == nil then
        error("Invalid query: " .. tostring(err) .. "\nQuery: " .. query)
    end

    if #rows == 0 then
        return nil, {}
    end

    column_names = {}
    for k, _ in pairs(rows[1]) do
        table.insert(column_names, k)
    end
    return rows, column_names
end

-- database.mariadb_update(descriptor, statement, ...) -> affected_rows, insert_id
-- Returns affected_rows/insert_id (matching native.exec), same shape as
-- sqlite_update's own true/insert_id pair above.
function mariadb_update(descriptor, statement, ...)
    native = get_mariadb_native()
    local_args = {...}
    if #local_args > 0 then
        for i, val in ipairs(local_args) do
            if type(val) == "string" then
                local_args[i] = escape_mariadb(descriptor, val)
            end
        end
        statement = string.format(statement, unpack(local_args))
    end

    conn, err = get_mariadb_connection(descriptor)
    if conn == nil then
        error("Error connecting to MariaDB: " .. tostring(err))
    end

    affected, insert_id = native.exec(conn, statement)
    if affected == nil then
        error("Invalid statement: " .. tostring(insert_id) .. "\nStatement: " .. statement)
    end
    return affected, insert_id
end

-- Closes and forgets every cached MariaDB connection -- optional for a
-- CGI-per-request process (process exit closes the socket anyway) but
-- tidy; a persistent-process worker (task #57) would call this on
-- graceful shutdown, not per request.
function mariadb_close_all()
    native = get_mariadb_native()
    for key, conn in pairs(_mariadb_connections) do
        native.close(conn)
        _mariadb_connections[key] = nil
    end
end

-- Number of currently-cached MariaDB connections -- real operational
-- visibility (e.g. a future `platform` diagnostics command), and lets
-- tests confirm connection reuse from outside this module without
-- reaching into _mariadb_connections directly (a required module's own
-- top-level "globals" aren't visible from the caller's environment in
-- this Luam build, confirmed directly while writing this file's tests).
function mariadb_connection_count()
    count = 0
    for _ in pairs(_mariadb_connections) do
        count = count + 1
    end
    return count
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
    results, col_names = sqlite_query(db_path, query)

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


database.sqlite_query = sqlite_query
database.sqlite_update = sqlite_update
database.import_delimited = import_delimited
database.export_delimited = export_delimited
database.load_df = load_df
database.escape_sqlite = escape_sqlite

database.mariadb_query = mariadb_query
database.mariadb_update = mariadb_update
database.escape_mariadb = escape_mariadb
database.mariadb_close_all = mariadb_close_all
database.mariadb_connection_count = mariadb_connection_count

-- Export the module
return database
