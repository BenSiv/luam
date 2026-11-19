sqlite = require("sqlite3")
_G.sqlite3 = nil

-- Define a module table
database_adapter = {}

unpack = unpack
if (unpack == nil) then
    unpack = table.unpack
end

-- Escapes single quotes for safe SQLite string usage
function escape_sqlite(value)
    return string.gsub(tostring(value), "'", "''")
end

-- Opt-in connection reuse for SQLite, mirroring the MariaDB cache below.
-- Off by default: each sqlite_query/sqlite_update opens and closes its own
-- connection, which costs nothing on a local disk. A caller whose database
-- sits on a slow filesystem (e.g. a 9p/drvfs mount, where one open costs
-- seconds) turns it on with sqlite_keep_open(true) and calls
-- sqlite_close_all() before exiting. Statements still autocommit, so a
-- kept-open connection holds no lock between calls.
_sqlite_keep_open = false
_sqlite_connections = {}

function sqlite_close_all()
    for path, conn in pairs(_sqlite_connections) do
        if sqlite.isopen(conn) then
            sqlite.close(conn)
        end
        _sqlite_connections[path] = nil
    end
end

function sqlite_keep_open(enabled)
    _sqlite_keep_open = (enabled == true)
    if _sqlite_keep_open == false then
        sqlite_close_all()
    end
end

function is_sqlite_keep_open()
    return _sqlite_keep_open == true
end

-- Civil YYYY-MM-DD prefix -> integer days since 1970-01-01 (Howard
-- Hinnant's Gregorian algorithm, pure integer arithmetic so host TZ/DST
-- never shifts DATEDIFF). Returns nil if `value` does not begin with a
-- valid YYYY-MM-DD date prefix.
function civil_days_from_ymd(value)
    if value == nil then
        return nil
    end
    ys, ms, ds = string.match(tostring(value), "^%s*(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if ys == nil then
        return nil
    end
    y = tonumber(ys)
    m = tonumber(ms)
    d = tonumber(ds)
    if y == nil or m == nil or d == nil or m < 1 or m > 12 or d < 1 or d > 31 then
        return nil
    end
    if m <= 2 then
        y = y - 1
    end
    era = math.floor(y / 400)
    yoe = y - (era * 400)
    mp = m + 9
    if m > 2 then
        mp = m - 3
    end
    doy = math.floor((153 * mp + 2) / 5) + d - 1
    doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

function sqlite_udf_exp(ctx, x)
    n = tonumber(x)
    if x == nil or n == nil then
        sqlite.result_null(ctx)
        return
    end
    sqlite.result_number(ctx, math.exp(n))
end

function sqlite_udf_ln(ctx, x)
    n = tonumber(x)
    if x == nil or n == nil or n <= 0 then
        sqlite.result_null(ctx)
        return
    end
    sqlite.result_number(ctx, math.log(n))
end

function sqlite_udf_log10(ctx, x)
    n = tonumber(x)
    if x == nil or n == nil or n <= 0 then
        sqlite.result_null(ctx)
        return
    end
    sqlite.result_number(ctx, math.log10(n))
end

function sqlite_udf_pow(ctx, x, y)
    nx = tonumber(x)
    ny = tonumber(y)
    if x == nil or y == nil or nx == nil or ny == nil then
        sqlite.result_null(ctx)
        return
    end
    sqlite.result_number(ctx, nx ^ ny)
end

function sqlite_udf_sqrt(ctx, x)
    n = tonumber(x)
    if x == nil or n == nil or n < 0 then
        sqlite.result_null(ctx)
        return
    end
    sqlite.result_number(ctx, math.sqrt(n))
end

-- UTF-8 codepoint count (bytes that are not 10xxxxxx continuation
-- bytes), matching MariaDB/MySQL's CHAR_LENGTH / CHARACTER_LENGTH.
function sqlite_udf_char_length(ctx, s)
    if s == nil then
        sqlite.result_null(ctx)
        return
    end
    _, count = string.gsub(tostring(s), "[^\x80-\xbf]", "")
    sqlite.result_int(ctx, count)
end

function sqlite_udf_extremum(is_greatest, ctx, ...)
    argc = select("#", ...)
    if argc == 0 then
        sqlite.result_null(ctx)
        return
    end
    all_num = true
    vals = {}
    for i = 1, argc do
        v = select(i, ...)
        if v == nil then
            -- Matches MariaDB/MySQL standard GREATEST/LEAST: any NULL
            -- argument yields NULL (unlike SQLite's MAX/MIN only when
            -- all args are non-NULL).
            sqlite.result_null(ctx)
            return
        end
        vals[i] = v
        if type(v) != "number" and tonumber(v) == nil then
            all_num = false
        end
    end
    if all_num then
        best = tonumber(vals[1])
        for i = 2, argc do
            cur = tonumber(vals[i])
            if is_greatest and cur > best then
                best = cur
            elseif (not is_greatest) and cur < best then
                best = cur
            end
        end
        sqlite.result_number(ctx, best)
    else
        best_s = tostring(vals[1])
        for i = 2, argc do
            cur_s = tostring(vals[i])
            if is_greatest and cur_s > best_s then
                best_s = cur_s
            elseif (not is_greatest) and cur_s < best_s then
                best_s = cur_s
            end
        end
        sqlite.result_text(ctx, best_s)
    end
end

function sqlite_udf_greatest(ctx, ...)
    sqlite_udf_extremum(true, ctx, ...)
end

function sqlite_udf_least(ctx, ...)
    sqlite_udf_extremum(false, ctx, ...)
end

function sqlite_udf_datediff(ctx, d1, d2)
    days1 = civil_days_from_ymd(d1)
    days2 = civil_days_from_ymd(d2)
    if days1 == nil or days2 == nil then
        sqlite.result_null(ctx)
        return
    end
    sqlite.result_int(ctx, days1 - days2)
end

-- Registers scalar SQL functions that MariaDB/MySQL provide natively
-- but Debian/Ubuntu's system libsqlite3 omits (compiled without
-- -DSQLITE_ENABLE_MATH_FUNCTIONS, and lacking CHAR_LENGTH/GREATEST/
-- LEAST/DATEDIFF). Keeping these here in native Luam lets callers write
-- portable SQL across both backends with zero C binding changes.
function register_sqlite_compat_functions(db)
    if sqlite.create_function == nil then
        return
    end
    sqlite.create_function(db, "EXP", 1, sqlite_udf_exp)
    sqlite.create_function(db, "LN", 1, sqlite_udf_ln)
    sqlite.create_function(db, "LOG10", 1, sqlite_udf_log10)
    sqlite.create_function(db, "POW", 2, sqlite_udf_pow)
    sqlite.create_function(db, "POWER", 2, sqlite_udf_pow)
    sqlite.create_function(db, "SQRT", 1, sqlite_udf_sqrt)
    sqlite.create_function(db, "CHAR_LENGTH", 1, sqlite_udf_char_length)
    sqlite.create_function(db, "CHARACTER_LENGTH", 1, sqlite_udf_char_length)
    sqlite.create_function(db, "GREATEST", -1, sqlite_udf_greatest)
    sqlite.create_function(db, "LEAST", -1, sqlite_udf_least)
    sqlite.create_function(db, "DATEDIFF", 2, sqlite_udf_datediff)
end

function open_sqlite_connection(db_path)
    db = sqlite.open(db_path)
    if (db == nil) then
        error("Error opening database: " .. tostring(db_path))
    end
    sqlite.exec(db, "PRAGMA busy_timeout = 5000;")
    -- WAL mode is a persistent property of the database file itself, not
    -- this connection -- re-issuing it on every open is redundant after
    -- the first time but harmless, and guarantees it's actually set
    -- rather than depending on some other code path having done it first.
    -- Lets readers and a writer proceed concurrently instead of blocking
    -- each other, which matters once more than one client (e.g. several
    -- browser tabs against the same store) is hitting the database at once.
    sqlite.exec(db, "PRAGMA journal_mode = WAL;")
    register_sqlite_compat_functions(db)
    return db
end

-- Returns db, owned: owned is true when the caller must close it (no cache).
function acquire_sqlite_connection(db_path)
    if _sqlite_keep_open == false then
        return open_sqlite_connection(db_path), true
    end
    cached = _sqlite_connections[db_path]
    if cached != nil and sqlite.isopen(cached) then
        return cached, false
    end
    cached = open_sqlite_connection(db_path)
    _sqlite_connections[db_path] = cached
    return cached, false
end

-- After a failed statement a multi-statement script may have left a
-- transaction open (BEGIN ran, COMMIT never did). A per-call connection
-- rolls it back by closing; a kept-open one must roll back explicitly or
-- every later write in this process would silently join that transaction.
-- ROLLBACK with no transaction active just returns an error, ignored here.
function release_sqlite_connection(db, owned, failed)
    if owned then
        sqlite.close(db)
    elseif failed then
        sqlite.exec(db, "ROLLBACK;")
    end
end

function sqlite_connection_count()
    count = 0
    for _ in pairs(_sqlite_connections) do
        count = count + 1
    end
    return count
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
    db, owned = acquire_sqlite_connection(db_path)

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
        release_sqlite_connection(db, owned, true)
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

    -- Finalize explicitly: closing a per-call connection used to clean the
    -- statement up implicitly, but on a kept-open connection a leftover
    -- statement outlives its query and crashed in the sqlite binding.
    sqlite.stmt.finalize(stmt)
    release_sqlite_connection(db, owned, false)

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
    db, owned = acquire_sqlite_connection(db_path)

    result = sqlite.exec(db, statement)
    if (result != sqlite.OK) then
        err_msg = tostring(sqlite.errmsg(db))
        release_sqlite_connection(db, owned, true)
        error("Error executing statement: " .. err_msg)
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
    affected = 0
    if sqlite.changes != nil then
        affected = sqlite.changes(db)
    end

    release_sqlite_connection(db, owned, false)
    return true, insert_id, affected
end

-- Executes a parameterized SELECT against SQLite using real prepared
-- statement binding (sqlite3_prepare_v2 + sqlite3_bind_*). Returns
-- rows ({} when empty), or nil, err_string on prepare/placeholder/bind
-- failure. Owned here alongside sqlite_query so callers never need to
-- import the raw `sqlite3` C module directly.
function sqlite_query_params(db_path, sql_text, bound_values)
    expected_count = 0
    if bound_values != nil then
        expected_count = #bound_values
    end
    ok_open, db, owned = pcall(acquire_sqlite_connection, db_path)
    if not ok_open or db == nil then
        return nil, "cannot open database"
    end
    vm, err = sqlite.prepare(db, sql_text)
    if vm == nil then
        err_msg = tostring(err)
        if type(err) == "number" then
            db_err = sqlite.errmsg(db)
            if db_err != nil then
                err_msg = err_msg .. " (" .. tostring(db_err) .. ")"
            end
        end
        release_sqlite_connection(db, owned, false)
        return nil, "invalid sql: " .. err_msg
    end
    actual_count = sqlite.stmt.bind_parameter_count(vm)
    if actual_count != expected_count then
        sqlite.stmt.finalize(vm)
        release_sqlite_connection(db, owned, false)
        return nil, string.format("sql placeholder count mismatch: expected %d, statement has %d", expected_count, actual_count)
    end
    for i = 1, expected_count do
        bind_rc = sqlite.stmt.bind(vm, i, bound_values[i])
        if bind_rc != 0 then
            sqlite.stmt.finalize(vm)
            release_sqlite_connection(db, owned, false)
            return nil, "failed to bind parameter #" .. tostring(i)
        end
    end
    rows = {}
    for row in sqlite.stmt.nrows(vm) do
        table.insert(rows, row)
    end
    sqlite.stmt.finalize(vm)
    release_sqlite_connection(db, owned, false)
    return rows
end

-- ---------------------------------------------------------------------
-- MariaDB support (lib/mariadb/lmariadb.c) -- see doc/mariadb-
-- migration.md in the daat repo for why this exists and how it
-- fits into that migration's phases. Lives in this same file (not a
-- separate lib/mariadb.lua) specifically to avoid a real naming
-- collision: a Lua module file named "mariadb.lua" and the native
-- binding it requires are BOTH resolved via require("mariadb"),
-- which recurses into itself mid-load ("loop or previous error loading
-- module 'mariadb'") -- confirmed directly while first writing this as
-- a standalone file. Matches this file's own existing sqlite/
-- database_adapter naming split (native module "sqlite3", wrapper
-- module "database_adapter") instead of repeating the same collision
-- under a different name.
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
_mariadb_last_used = {}
_mariadb_pin_depth = {}
MARIADB_PING_INTERVAL_SECS = 5

function mariadb_connection_key(descriptor)
    return tostring(descriptor.host) .. ":" .. tostring(descriptor.port) ..
        ":" .. tostring(descriptor.user) .. ":" .. tostring(descriptor.database)
end

function is_mariadb_pinned(key)
    depth = _mariadb_pin_depth[key]
    return depth != nil and depth > 0
end

-- True when a sql_mode string (as read back from @@SESSION.sql_mode,
-- comma-separated flags) contains NO_BACKSLASH_ESCAPES as a whole flag.
function sql_mode_disables_backslash_escapes(mode)
    if mode == nil then
        return false
    end
    for flag in string.gmatch(string.upper(tostring(mode)), "[^,%s]+") do
        if flag == "NO_BACKSLASH_ESCAPES" then
            return true
        end
    end
    return false
end

-- Returns a live, cached connection for this descriptor -- opens one if
-- none is cached yet, or replaces one that's gone stale. Within a short
-- window (MARIADB_PING_INTERVAL_SECS) of the previous use, skips the extra
-- wire-level mysql_ping() round-trip and falls back to transparent
-- reconnect-once in mariadb_query/mariadb_update if the socket dropped.
function get_mariadb_connection_internal(descriptor, force_reconnect)
    native = get_mariadb_native()
    key = mariadb_connection_key(descriptor)
    pinned = is_mariadb_pinned(key)
    now = os.time()
    cached = _mariadb_connections[key]
    if cached != nil and force_reconnect != true then
        if native.isopen(cached) == true then
            last_used = _mariadb_last_used[key]
            if last_used != nil and (now - last_used) >= 0 and (now - last_used) < MARIADB_PING_INTERVAL_SECS then
                _mariadb_last_used[key] = now
                return cached, nil
            elseif native.ping(cached) == true then
                _mariadb_last_used[key] = now
                return cached, nil
            end
        end
    end
    if cached != nil then
        if native.isopen(cached) == true then
            native.close(cached)
        end
        _mariadb_connections[key] = nil
        _mariadb_last_used[key] = nil
    end
    if pinned then
        return nil, "MariaDB connection dropped while holding an active transaction or advisory lock"
    end

    conn, err = native.connect(
        descriptor.host, descriptor.port, descriptor.user, descriptor.password, descriptor.database
    )
    if conn == nil then
        return nil, err
    end

    -- MariaDB/MySQL's default sql_mode treats backslash as an escape
    -- character inside string literals. database.quote only doubles
    -- single quotes, so under the default mode a value ending in a
    -- backslash (e.g. `\'`) escapes the doubled quote and closes the
    -- literal early: SQL injection, not just a display problem.
    -- NO_BACKSLASH_ESCAPES makes backslash an ordinary character, as
    -- in SQLite and standard SQL, which is what makes quote-doubling
    -- correct on this backend. Appended via CONCAT rather than a flat
    -- SET so the server's other flags (e.g. STRICT_TRANS_TABLES) stay.
    --
    -- Every quoted value in every query depends on this one statement,
    -- so it fails closed: the mode is read back and the connection is
    -- refused unless the flag is really set. A request then errors
    -- instead of running with injectable quoting. A reconnect always
    -- comes back through here (a dead cached connection is replaced
    -- above, never silently reconnected by the client library), so a
    -- new session can't skip the check either.
    native.exec(conn, "SET SESSION sql_mode = CONCAT(@@SESSION.sql_mode, ',NO_BACKSLASH_ESCAPES');")
    mode_rows, mode_err = native.query(conn, "SELECT @@SESSION.sql_mode AS sql_mode;")
    mode = nil
    if mode_rows != nil and mode_rows[1] != nil then
        mode = mode_rows[1].sql_mode
    end
    if not sql_mode_disables_backslash_escapes(mode) then
        native.close(conn)
        return nil, "refusing MariaDB connection: could not enable NO_BACKSLASH_ESCAPES (sql_mode = " ..
            tostring(mode) .. ", " .. tostring(mode_err) .. ")"
    end

    _mariadb_connections[key] = conn
    _mariadb_last_used[key] = os.time()
    return conn, nil
end

function get_mariadb_connection(descriptor)
    return get_mariadb_connection_internal(descriptor, false)
end

-- Pins (delta = +1) or unpins (delta = -1) the cached MariaDB session for
-- `descriptor` while an open transaction or session-scoped advisory lock
-- (`GET_LOCK`) is active. While pinned, a dropped socket MUST raise an
-- error rather than transparently opening a fresh connection (which would
-- silently drop the lock or run subsequent writes in autocommit mode).
function mariadb_pin_connection(descriptor, delta)
    native = get_mariadb_native()
    key = mariadb_connection_key(descriptor)
    cur = _mariadb_pin_depth[key]
    if cur == nil then
        cur = 0
    end
    if delta > 0 and cur == 0 then
        conn, err = get_mariadb_connection_internal(descriptor, false)
        if conn == nil then
            error("Error connecting to MariaDB: " .. tostring(err))
        end
    end
    next_depth = cur + delta
    if next_depth <= 0 then
        _mariadb_pin_depth[key] = nil
        cached = _mariadb_connections[key]
        if cached != nil and native.isopen(cached) == false then
            _mariadb_connections[key] = nil
            _mariadb_last_used[key] = nil
        end
    else
        _mariadb_pin_depth[key] = next_depth
    end
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

function format_mariadb_sql(native, conn, template, raw_args)
    if #raw_args == 0 then
        return template
    end
    formatted_args = {}
    for i, val in ipairs(raw_args) do
        if type(val) == "string" then
            formatted_args[i] = native.escape(conn, val)
        else
            formatted_args[i] = val
        end
    end
    return string.format(template, unpack(formatted_args))
end

-- database_adapter.mariadb_query(descriptor, query, ...) -> rows, column_names
-- Same %s-interpolation-with-escaped-varargs convention as sqlite_query
-- above -- see doc/mariadb-migration.md's "Design decisions" section on
-- bound parameters as a later, additive option, not required up front.
function mariadb_query(descriptor, query, ...)
    native = get_mariadb_native()
    raw_args = {...}
    key = mariadb_connection_key(descriptor)
    was_cached = (_mariadb_connections[key] != nil)

    conn, err = get_mariadb_connection_internal(descriptor, false)
    if conn == nil then
        error("Error connecting to MariaDB: " .. tostring(err))
    end

    formatted_query = format_mariadb_sql(native, conn, query, raw_args)
    rows, err, column_names = native.query(conn, formatted_query)
    if rows == nil and was_cached and (native.isopen(conn) == false or native.ping(conn) == false) then
        if is_mariadb_pinned(key) then
            if native.isopen(conn) == true then
                native.close(conn)
            end
            _mariadb_connections[key] = nil
            _mariadb_last_used[key] = nil
            error("MariaDB connection dropped while holding an active transaction or advisory lock: " .. tostring(err))
        end
        conn, reconn_err = get_mariadb_connection_internal(descriptor, true)
        if conn == nil then
            error("Error connecting to MariaDB: " .. tostring(reconn_err))
        end
        formatted_query = format_mariadb_sql(native, conn, query, raw_args)
        rows, err, column_names = native.query(conn, formatted_query)
    end
    if rows == nil then
        error("Invalid query: " .. tostring(err) .. "\nQuery: " .. formatted_query)
    end

    _mariadb_last_used[key] = os.time()
    if column_names == nil then
        column_names = {}
    end

    if #rows == 0 then
        return nil, column_names
    end

    return rows, column_names
end

-- database_adapter.mariadb_update(descriptor, statement, ...) -> affected_rows, insert_id
-- Returns affected_rows/insert_id (matching native.exec), same shape as
-- sqlite_update's own true/insert_id pair above.
function mariadb_update(descriptor, statement, ...)
    native = get_mariadb_native()
    raw_args = {...}
    key = mariadb_connection_key(descriptor)
    was_cached = (_mariadb_connections[key] != nil)

    conn, err = get_mariadb_connection_internal(descriptor, false)
    if conn == nil then
        error("Error connecting to MariaDB: " .. tostring(err))
    end

    formatted_stmt = format_mariadb_sql(native, conn, statement, raw_args)
    affected, insert_id = native.exec(conn, formatted_stmt)
    if affected == nil and was_cached and (native.isopen(conn) == false or native.ping(conn) == false) then
        if is_mariadb_pinned(key) then
            if native.isopen(conn) == true then
                native.close(conn)
            end
            _mariadb_connections[key] = nil
            _mariadb_last_used[key] = nil
            error("MariaDB connection dropped while holding an active transaction or advisory lock: " .. tostring(insert_id))
        end
        conn, reconn_err = get_mariadb_connection_internal(descriptor, true)
        if conn == nil then
            error("Error connecting to MariaDB: " .. tostring(reconn_err))
        end
        formatted_stmt = format_mariadb_sql(native, conn, statement, raw_args)
        affected, insert_id = native.exec(conn, formatted_stmt)
    end
    if affected == nil then
        error("Invalid statement: " .. tostring(insert_id) .. "\nStatement: " .. formatted_stmt)
    end

    _mariadb_last_used[key] = os.time()
    return affected, insert_id
end

-- Closes and forgets every cached MariaDB connection -- optional for a
-- CGI-per-request process (process exit closes the socket anyway) but
-- tidy; a persistent-process worker (task #57) would call this on
-- graceful shutdown, not per request.
function mariadb_close_all()
    native = get_mariadb_native()
    for key, conn in pairs(_mariadb_connections) do
        if native.isopen(conn) == true then
            native.close(conn)
        end
        _mariadb_connections[key] = nil
        _mariadb_last_used[key] = nil
    end
    _mariadb_pin_depth = {}
end

_lfs_lock_checked = false
_lfs_lock_mod = nil

function get_lfs_for_lock()
    if not _lfs_lock_checked then
        _lfs_lock_checked = true
        ok, mod = pcall(require, "lfs")
        if ok and type(mod) == "table" then
            _lfs_lock_mod = mod
        end
    end
    return _lfs_lock_mod
end

function canonical_sqlite_path(db_path)
    p = tostring(db_path)
    if string.sub(p, 1, 1) != "/" then
        lfs_mod = get_lfs_for_lock()
        if lfs_mod != nil and lfs_mod.currentdir != nil then
            cwd = lfs_mod.currentdir()
            if cwd != nil and cwd != "" then
                p = cwd .. "/" .. p
            end
        end
    end
    p = string.gsub(p, "/%./", "/")
    p = string.gsub(p, "//+", "/")
    return p
end

function sqlite_lock_file_path(db_path, lock_name)
    raw_key = canonical_sqlite_path(db_path) .. "\0" .. tostring(lock_name)
    h1 = 5381
    h2 = 2166136261
    for i = 1, string.len(raw_key) do
        b = string.byte(raw_key, i)
        h1 = (h1 * 33 + b) % 4294967296
        h2 = (h2 * 131 + b) % 4294967296
    end
    tmpdir = os.getenv("TMPDIR")
    if tmpdir == nil or tmpdir == "" then
        tmpdir = "/tmp"
    end
    tmpdir = string.gsub(tmpdir, "/+$", "")
    return string.format("%s/luam_dblock_%08x%08x.lck", tmpdir, h1, h2)
end

-- Acquires a cross-process advisory lock for a SQLite database by opening a
-- dedicated companion SQLite lock file in /tmp and entering `BEGIN EXCLUSIVE`
-- under `PRAGMA busy_timeout`. Kernel file locks release automatically if a
-- worker crashes or is SIGKILLed, and keeping the companion handle separate
-- from `db_path` allows `fn()` to freely open/close connections or run DDL on
-- `db_path` itself without self-contention.
function sqlite_acquire_lock(db_path, lock_name, timeout_secs)
    path_str = tostring(db_path)
    if path_str == ":memory:" or (string.sub(path_str, 1, 5) == "file:" and string.find(path_str, "mode=memory", 1, true) != nil) then
        return nil
    end
    t_secs = tonumber(timeout_secs)
    if t_secs == nil or t_secs < 0 then
        t_secs = 0
    end
    timeout_ms = math.floor(t_secs * 1000)
    lock_path = sqlite_lock_file_path(db_path, lock_name)
    lock_conn = sqlite.open(lock_path)
    if lock_conn == nil then
        error("could not open SQLite advisory lock file: " .. tostring(lock_path))
    end
    sqlite.exec(lock_conn, string.format("PRAGMA busy_timeout = %d;", timeout_ms))
    rc = sqlite.exec(lock_conn, "BEGIN EXCLUSIVE;")
    if rc != sqlite.OK then
        err_msg = tostring(sqlite.errmsg(lock_conn))
        sqlite.close(lock_conn)
        error(string.format("could not acquire database lock %s within %ss (%s)",
            tostring(lock_name), tostring(t_secs), err_msg), 0)
    end
    return {conn = lock_conn, path = lock_path}
end

function sqlite_release_lock(handle)
    if handle != nil and handle.conn != nil and sqlite.isopen(handle.conn) then
        sqlite.exec(handle.conn, "ROLLBACK;")
        sqlite.close(handle.conn)
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
    delimited_files = require("delimited_files")
    db, owned = acquire_sqlite_connection(db_path)

    content = delimited_files.readdlm(file_path, delimiter, true)
    if (content == nil) then
        release_sqlite_connection(db, owned, false)
        error("Error reading delimited file")
    end
    
    col_names = {}
    if type(content[1]) == "table" then
        for k, _ in pairs(content[1]) do
            table.insert(col_names, k)
        end
    end
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
        err_msg = tostring(sqlite.errmsg(db))
        release_sqlite_connection(db, owned, true)
        error("Error: " .. err_msg)
    end

    release_sqlite_connection(db, owned, false)
    return true
end

function export_delimited(db_path, query, file_path, delimiter, header)
    results, col_names = sqlite_query(db_path, query)

    if (results == nil) then
        print("Failed query")
        return nil
    end
    
    if (#results == 0) then
        print("No data found")
        return nil
    end

    delimited_files = require("delimited_files")
    delimited_files.writedlm(results, file_path, delimiter, header, false, col_names)
    return true
end

function load_df_rows(db_path, table_name, dataframe)
    dataframes = require("dataframes")
    -- Validate dataframe
    if (not dataframes.is_dataframe(dataframe)) then
        error("The provided table is not a valid dataframe.")
    end

    columns = dataframes.get_columns(dataframe)
    col_names = "'" .. table.concat(columns, "', '") .. "'"

    -- Open DB
    db, owned = acquire_sqlite_connection(db_path)

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

    release_sqlite_connection(db, owned, false)
    return true
end

function load_df(db_path, table_name, dataframe)
    dataframes = require("dataframes")
    -- Check if the provided dataframe is valid
    if (not dataframes.is_dataframe(dataframe)) then
        error("The provided table is not a valid dataframe.")
    end

    -- Get the columns from the dataframe
    columns = dataframes.get_columns(dataframe)
    
    -- Open the SQLite database
    ok, db, owned = pcall(acquire_sqlite_connection, db_path)
    if (not ok or db == nil) then
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
        release_sqlite_connection(db, owned, true)
        return nil
    end

    -- Close the database connection
    release_sqlite_connection(db, owned, false)
    return true
end


database_adapter.sqlite_query = sqlite_query
database_adapter.sqlite_query_params = sqlite_query_params
database_adapter.sqlite_update = sqlite_update
database_adapter.sqlite_keep_open = sqlite_keep_open
database_adapter.is_sqlite_keep_open = is_sqlite_keep_open
database_adapter.sqlite_close_all = sqlite_close_all
database_adapter.sqlite_connection_count = sqlite_connection_count
database_adapter.acquire_sqlite_connection = acquire_sqlite_connection
database_adapter.release_sqlite_connection = release_sqlite_connection
database_adapter.sqlite_acquire_lock = sqlite_acquire_lock
database_adapter.sqlite_release_lock = sqlite_release_lock
database_adapter.import_delimited = import_delimited
database_adapter.export_delimited = export_delimited
database_adapter.load_df = load_df
database_adapter.escape_sqlite = escape_sqlite
database_adapter.sql_mode_disables_backslash_escapes = sql_mode_disables_backslash_escapes

database_adapter.mariadb_query = mariadb_query
database_adapter.mariadb_update = mariadb_update
database_adapter.escape_mariadb = escape_mariadb
database_adapter.mariadb_close_all = mariadb_close_all
database_adapter.mariadb_connection_count = mariadb_connection_count
database_adapter.mariadb_pin_connection = mariadb_pin_connection

-- Export the module
return database_adapter
