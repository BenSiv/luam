-- Thin adapter over Luam's own `database_adapter` module, spanning two
-- backends (SQLite and MariaDB). Originated in daat (see
-- ../daat/doc/mariadb-migration.md for the migration this grew out
-- of) but generic to any downstream project: `db_path` is a fully
-- opaque value to every caller -- either a SQLite file path (a
-- string) or a MariaDB connection descriptor (a table) -- and
-- dispatch below is purely by db_path's own runtime shape (type(db_path)
-- == "table"), never a config lookup from inside this file, so there's
-- nothing here for a downstream project's own config module to wire
-- up or for this file to depend on circularly.
--
-- Named for what it does, not abbreviated -- a caller wanting a short
-- local handle aliases it at the require site (`db =
-- require("database")`), the same way Python code writes
-- `import pandas as pd`; the module's own canonical name stays
-- explicit either way. The per-backend specifics (raw SQLite/MariaDB
-- bindings) live one layer down, in database_adapter -- this module is
-- the one everyday callers actually reach for.

database_adapter = require("database_adapter")

database = {}

function is_mariadb(db_path)
    return type(db_path) == "table"
end

-- Public alias -- other modules that need to branch on backend go
-- through this rather than each re-deriving db_path's shape convention
-- for themselves.
function database.is_mariadb(db_path)
    return is_mariadb(db_path)
end

function database.query(db_path, query, ...)
    if is_mariadb(db_path) then
        return database_adapter.mariadb_query(db_path, query, ...)
    end
    return database_adapter.sqlite_query(db_path, query, ...)
end

-- Normalized across both backends: -> true, insert_id, affected_rows.
-- (Historically sqlite_update returned `true, insert_id` while
-- mariadb_update returned `affected_rows, insert_id`, forcing callers
-- to avoid the first return value altogether and run extra SELECTs.)
function database.exec(db_path, statement, ...)
    if is_mariadb(db_path) then
        affected, insert_id = database_adapter.mariadb_update(db_path, statement, ...)
        return true, insert_id, affected
    end
    ok, insert_id, affected = database_adapter.sqlite_update(db_path, statement, ...)
    return ok, insert_id, affected
end

function database.sqlite_keep_open(enabled)
    return database_adapter.sqlite_keep_open(enabled)
end

function database.is_sqlite_keep_open()
    return database_adapter.is_sqlite_keep_open()
end

function database.sqlite_close_all()
    return database_adapter.sqlite_close_all()
end

function database.mariadb_close_all()
    return database_adapter.mariadb_close_all()
end

-- database_adapter.get_tables/get_columns go through a different sqlite
-- binding entry point (sqlite.rows(db, query), a db-level convenience
-- call) than sqlite_query's sqlite.prepare + stmt.rows/nrows -- and
-- that path can return no rows even when the query is correct.
-- Reimplemented here against the sqlite_query path instead, the one
-- actually verified working.

function database.get_tables(db_path)
    query = "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';"
    if is_mariadb(db_path) then
        query = "SELECT table_name AS name FROM information_schema.tables WHERE table_schema = DATABASE();"
    end
    rows = database.query(db_path, query)
    if rows == nil then
        return {}
    end
    names = {}
    for _, row in ipairs(rows) do
        table.insert(names, row.name)
    end
    return names
end

function database.get_columns(db_path, table_name)
    query = "PRAGMA table_info(" .. table_name .. ");"
    if is_mariadb(db_path) then
        query = string.format(
            "SELECT column_name AS name FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = %s ORDER BY ordinal_position;",
            database.quote(table_name)
        )
    end
    rows = database.query(db_path, query)
    if rows == nil then
        return {}
    end
    names = {}
    for _, row in ipairs(rows) do
        table.insert(names, row.name)
    end
    return names
end

function database.table_exists(db_path, table_name)
    query = string.format(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = %s;", database.quote(table_name)
    )
    if is_mariadb(db_path) then
        query = string.format(
            "SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = %s;",
            database.quote(table_name)
        )
    end
    rows = database.query(db_path, query)
    return rows != nil
end

-- Backtick-quotes a raw SQL identifier (column/index name), not a value --
-- database.quote/literal already cover values. Needed anywhere a
-- caller-defined field name (arbitrary, not controlled by this
-- module) gets interpolated as a column identifier: MySQL's reserved-
-- word list is much larger than SQLite's or MariaDB's own extensions
-- allow around, so a real field genuinely named e.g. "usage" breaks
-- CREATE TABLE/INSERT/UPDATE outright without this. Backtick quoting
-- is valid MySQL/MariaDB syntax and SQLite's own MySQL-compatibility
-- extension, so this is a single, unified fix needing no per-backend
-- branch.
function database.quote_ident(name)
    return "`" .. tostring(name) .. "`"
end

-- Real MySQL (unlike MariaDB, and unlike MySQL's own CREATE TABLE) has no
-- "IF NOT EXISTS" clause for CREATE INDEX at all -- a syntax error, not a
-- no-op. Every CREATE INDEX call site should check this first instead of
-- relying on IF NOT EXISTS, same "check, then conditionally create"
-- shape as database.table_exists already gives.
function database.index_exists(db_path, table_name, index_name)
    query = string.format(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name = %s;", database.quote(index_name)
    )
    if is_mariadb(db_path) then
        query = string.format(
            "SELECT DISTINCT index_name FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = %s AND index_name = %s;",
            database.quote(table_name), database.quote(index_name)
        )
    end
    rows = database.query(db_path, query)
    return rows != nil
end

-- Quotes a value as a safe SQL string literal: plain quote-doubling, no
-- db_path/backend parameter needed here. On MariaDB/MySQL this is only
-- safe because every connection runs with NO_BACKSLASH_ESCAPES: under
-- the default mode a trailing backslash would escape the doubled quote
-- and end the literal early. database_adapter's get_mariadb_connection
-- refuses any connection where that flag didn't take, so this function
-- never runs against a session where it would be injectable. Keeping
-- it a pure, backend-agnostic function (rather than threading db_path
-- through it) avoids a ripple through every quote/literal call site.
function database.quote(value)
    return "'" .. string.gsub(tostring(value), "'", "''") .. "'"
end

-- Renders `value` as a safe SQL literal: NULL for nil, a quoted string
-- otherwise. Numbers/booleans are stringified and quoted too, which is
-- harmless for either backend's dynamic-enough typing and keeps
-- callers from needing two code paths.
function database.literal(value)
    if value == nil then
        return "NULL"
    end
    return database.quote(value)
end

-- The four helpers below exist for downstream projects doing their own
-- SQLite<->MariaDB portability (see ../daat/doc/mariadb-migration.md
-- Phase 3 for the migration that motivated them): a caller's own
-- SQLite-dialect DDL/DML tokens (AUTOINCREMENT, datetime('now',
-- 'localtime'), INSERT OR REPLACE/IGNORE) route through these instead
-- of being hardcoded, so db_path's backend decides the actual SQL text
-- at the one call site that already has db_path in scope.

-- SQL expression for "the current timestamp", backend-appropriate.
-- Embed directly into a query string via string.format's %s.
function database.now_expr(db_path)
    if is_mariadb(db_path) then
        return "NOW()"
    end
    return "datetime('now', 'localtime')"
end

-- The auto-increment keyword for an `INTEGER PRIMARY KEY <this>` column
-- declaration. Only the keyword differs between engines -- SQLite
-- requires the type name spelled exactly "INTEGER" for its rowid-alias
-- behavior, but MariaDB doesn't care whether it's INTEGER or INT, so
-- the surrounding "INTEGER PRIMARY KEY" text stays the same for both.
function database.autoincrement_keyword(db_path)
    if is_mariadb(db_path) then
        return "AUTO_INCREMENT"
    end
    return "AUTOINCREMENT"
end

-- Upsert-by-replace statement prefix (goes before "<table> (<cols>) VALUES ...").
-- MariaDB's REPLACE INTO needs no "INSERT OR" prefix; semantics match
-- SQLite's INSERT OR REPLACE closely enough as long as no foreign-key
-- constraints exist for its delete+insert behavior to disturb.
function database.replace_into(db_path)
    if is_mariadb(db_path) then
        return "REPLACE INTO"
    end
    return "INSERT OR REPLACE INTO"
end

-- Insert-ignoring-conflicts statement prefix (goes before "<table> (<cols>) VALUES ...").
function database.insert_ignore(db_path)
    if is_mariadb(db_path) then
        return "INSERT IGNORE INTO"
    end
    return "INSERT OR IGNORE INTO"
end

-- Column reference for a `CREATE INDEX ... ON table(<this>)` clause,
-- safe to use on a TEXT column of unbounded length. MariaDB/InnoDB
-- refuses a bare TEXT/BLOB column in ANY index (not just a primary
-- key) without an explicit prefix length ("BLOB/TEXT column ... used
-- in key specification without a key length"). A 255-char prefix is
-- plenty for typical indexed TEXT columns (content hashes, external
-- ids). SQLite has no equivalent prefix-length syntax at all (it would
-- be a syntax error there), so this can't be unified into one string
-- the way VARCHAR(255) unified the primary-key case -- has to branch.
function database.text_index_column(db_path, column_name)
    if is_mariadb(db_path) then
        return column_name .. "(255)"
    end
    return column_name
end

-- Stable per-store cache key across both backends. Includes the SQLite
-- file's inode when lfs is present so tests recreating a database at
-- the same temp path never hit stale in-process caches.
_lfs_checked = false
_lfs_mod = nil

function get_lfs_optional()
    if not _lfs_checked then
        _lfs_checked = true
        ok, mod = pcall(require, "lfs")
        if ok and type(mod) == "table" then
            _lfs_mod = mod
        end
    end
    return _lfs_mod
end

function database.cache_key(db_path)
    if is_mariadb(db_path) then
        return "mariadb:" .. tostring(db_path.host) .. ":" .. tostring(db_path.port) .. ":" .. tostring(db_path.database)
    end
    lfs_mod = get_lfs_optional()
    if lfs_mod != nil then
        attr = lfs_mod.attributes(tostring(db_path))
        if attr != nil and attr.ino != nil then
            return "sqlite:" .. tostring(db_path) .. ":" .. tostring(attr.ino)
        end
    end
    return "sqlite:" .. tostring(db_path)
end

-- Finds unquoted `?` placeholder positions in SQL (skipping single- and
-- double-quoted literals and backtick identifiers so a `?` inside text
-- is never mistaken for a bind slot).
function find_sql_placeholders(sql_text)
    positions = {}
    len = string.len(sql_text)
    i = 1
    in_quote = nil
    while i <= len do
        ch = string.sub(sql_text, i, i)
        if in_quote != nil then
            if ch == in_quote then
                if i < len and string.sub(sql_text, i + 1, i + 1) == in_quote then
                    i = i + 2
                else
                    in_quote = nil
                    i = i + 1
                end
            else
                i = i + 1
            end
        else
            if ch == "'" or ch == "\"" or ch == "`" then
                in_quote = ch
            elseif ch == "?" then
                table.insert(positions, i)
            end
            i = i + 1
        end
    end
    return positions
end

-- Normalizes one parameter entry (either a typed `{type=, value=}` table
-- or a plain Lua scalar) into `(bound_scalar, sql_literal, err_msg)`.
function normalize_query_param(spec)
    if type(spec) == "table" and spec.type != nil then
        ptype = spec.type
        pval = spec.value
        if ptype == "integer" or ptype == "number" then
            num = tonumber(pval)
            if num == nil then
                return nil, nil, "parameter must be a number"
            end
            if ptype == "integer" and math.floor(num) != num then
                return nil, nil, "parameter must be an integer"
            end
            return num, tostring(num), nil
        elseif ptype == "text" then
            if pval == nil or pval == "" then
                return nil, nil, "missing required parameter"
            end
            s = tostring(pval)
            return s, database.quote(s), nil
        else
            return nil, nil, "unsupported parameter type: " .. tostring(ptype)
        end
    end
    if spec == nil then
        return nil, "NULL", nil
    end
    if type(spec) == "number" then
        return spec, tostring(spec), nil
    end
    if type(spec) == "boolean" then
        if spec then
            return 1, "1", nil
        end
        return 0, "0", nil
    end
    s = tostring(spec)
    return s, database.quote(s), nil
end

-- Executes a parameterized SELECT across SQLite (real sqlite3_bind_*)
-- and MariaDB (validated literal splice with NO_BACKSLASH_ESCAPES,
-- avoiding gsub's `%` capture-escape pitfall). Returns `rows` (`{}`
-- when no rows matched), or `nil, err_string` on error.
function database.query_params(db_path, sql_text, params)
    if params == nil then
        params = {}
    end
    positions = find_sql_placeholders(sql_text)
    if #positions != #params then
        return nil, string.format("sql placeholder count mismatch: expected %d, statement has %d", #params, #positions)
    end
    bound = {}
    literals = {}
    for i = 1, #params do
        bval, lit, perr = normalize_query_param(params[i])
        if perr != nil then
            return nil, perr
        end
        bound[i] = bval
        literals[i] = lit
    end
    if not is_mariadb(db_path) then
        return database_adapter.sqlite_query_params(db_path, sql_text, bound)
    end
    parts = {}
    cursor = 1
    for i, pos in ipairs(positions) do
        table.insert(parts, string.sub(sql_text, cursor, pos - 1))
        table.insert(parts, literals[i])
        cursor = pos + 1
    end
    table.insert(parts, string.sub(sql_text, cursor))
    substituted = table.concat(parts)
    ok_q, rows = pcall(database.query, db_path, substituted)
    if not ok_q then
        return nil, tostring(rows)
    end
    if rows == nil then
        return {}
    end
    return rows
end

-- Server-side connection identifier on MariaDB (nil on SQLite). Used by
-- database.transaction to detect a mid-transaction silent reconnect,
-- which would otherwise end the open transaction and let subsequent
-- writes autocommit.
function database.connection_id(db_path)
    if not is_mariadb(db_path) then
        return nil
    end
    rows = database.query(db_path, "SELECT CONNECTION_ID() AS id;")
    if rows == nil or rows[1] == nil then
        return nil
    end
    return tostring(rows[1].id)
end

_active_transactions = {}

function pack_varargs(...)
    return {n = select("#", ...), ...}
end

function unpack_varargs(packed)
    if packed == nil or packed.n == 0 then
        return
    end
    if unpack != nil then
        return unpack(packed, 1, packed.n)
    end
    return table.unpack(packed, 1, packed.n)
end

-- Backend-agnostic atomic transaction wrapper:
-- * Re-entrant: nested database.transaction calls on the same store
--   join the outer transaction instead of issuing a nested BEGIN (which
--   errors on SQLite and implicitly commits the outer transaction on
--   MariaDB/MySQL!).
-- * SQLite: pins a kept-open connection if needed and opens BEGIN
--   IMMEDIATE so concurrent writers wait on busy_timeout at entry
--   rather than deadlocking mid-transaction on lock upgrade.
-- * MariaDB: verifies CONNECTION_ID() has not changed before COMMIT
--   (and passes a `check_alive()` helper to `fn` for per-row checks on
--   large batches).
-- If `fn(check_alive)` raises an error, rolls back and re-raises it.
-- If `fn` returns `false, ...` (explicit abort without throwing), rolls
-- back and returns `fn`'s return values; otherwise commits and returns
-- `fn`'s return values.
function database.transaction(db_path, fn)
    tx_key = database.cache_key(db_path)
    if _active_transactions[tx_key] != nil then
        return fn(_active_transactions[tx_key])
    end

    opened_sqlite = false
    if not is_mariadb(db_path) then
        already_open = database_adapter.is_sqlite_keep_open() == true or
            database_adapter.sqlite_connection_count() > 0
        if not already_open then
            database_adapter.sqlite_keep_open(true)
            opened_sqlite = true
        end
    end

    conn_before = database.connection_id(db_path)
    check_alive = function()
        if conn_before != nil and database.connection_id(db_path) != conn_before then
            return false
        end
        return true
    end

    if is_mariadb(db_path) then
        database.exec(db_path, "START TRANSACTION;")
    else
        database.exec(db_path, "BEGIN IMMEDIATE;")
    end
    _active_transactions[tx_key] = check_alive

    results = nil
    ok, err = pcall(function()
        results = pack_varargs(fn(check_alive))
    end)

    _active_transactions[tx_key] = nil

    should_commit = ok and (results == nil or results[1] != false)
    if should_commit and not check_alive() then
        pcall(database.exec, db_path, "ROLLBACK;")
        if opened_sqlite then
            database_adapter.sqlite_keep_open(false)
        end
        error("database connection dropped during transaction; rolled back", 0)
    end

    if should_commit then
        database.exec(db_path, "COMMIT;")
    else
        pcall(database.exec, db_path, "ROLLBACK;")
    end

    if opened_sqlite then
        database_adapter.sqlite_keep_open(false)
    end

    if not ok then
        error(err, 0)
    end
    return unpack_varargs(results)
end

-- Named advisory lock across concurrent processes (for schema DDL /
-- migrations, which implicitly commit transactions on MariaDB/MySQL and
-- therefore cannot rely on database.transaction). On MariaDB, acquires
-- GET_LOCK(lock_name, timeout_secs) and guarantees RELEASE_LOCK even if
-- `fn` raises; on SQLite, WAL + busy_timeout already serialize file DDL.
function database.with_lock(db_path, lock_name, timeout_secs, fn)
    if timeout_secs == nil then
        timeout_secs = 120
    end
    locked = is_mariadb(db_path)
    if locked then
        database.query(db_path, string.format(
            "SELECT GET_LOCK(%s, %d) AS got;", database.quote(lock_name), tonumber(timeout_secs)
        ))
    end
    results = nil
    ok, err = pcall(function()
        results = pack_varargs(fn())
    end)
    if locked then
        pcall(database.query, db_path, string.format(
            "SELECT RELEASE_LOCK(%s) AS released;", database.quote(lock_name)
        ))
    end
    if not ok then
        error(err, 0)
    end
    return unpack_varargs(results)
end

return database
