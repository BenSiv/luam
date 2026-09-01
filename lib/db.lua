-- Thin adapter over Luam's own `database` module, spanning two
-- backends (SQLite and MariaDB). Originated in daat (see
-- ../daat/doc/mariadb-migration.md for the migration this grew out
-- of) but generic to any downstream project: `db_path` is a fully
-- opaque value to every caller -- either a SQLite file path (a
-- string) or a MariaDB connection descriptor (a table) -- and
-- dispatch below is purely by db_path's own runtime shape (type(db_path)
-- == "table"), never a config lookup from inside this file, so there's
-- nothing here for a downstream project's own config module to wire
-- up or for this file to depend on circularly.

database = require("database")

db = {}

function is_mariadb(db_path)
    return type(db_path) == "table"
end

-- Public alias -- other modules that need to branch on backend go
-- through this rather than each re-deriving db_path's shape convention
-- for themselves.
function db.is_mariadb(db_path)
    return is_mariadb(db_path)
end

function db.query(db_path, query, ...)
    if is_mariadb(db_path) then
        return database.mariadb_query(db_path, query, ...)
    end
    return database.sqlite_query(db_path, query, ...)
end

function db.exec(db_path, statement, ...)
    if is_mariadb(db_path) then
        return database.mariadb_update(db_path, statement, ...)
    end
    return database.sqlite_update(db_path, statement, ...)
end

-- database.get_tables/get_columns go through a different sqlite binding
-- entry point (sqlite.rows(db, query), a db-level convenience call) than
-- sqlite_query's sqlite.prepare + stmt.rows/nrows -- and that path can
-- return no rows even when the query is correct. Reimplemented here
-- against the sqlite_query path instead, the one actually verified
-- working.

function db.get_tables(db_path)
    query = "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';"
    if is_mariadb(db_path) then
        query = "SELECT table_name AS name FROM information_schema.tables WHERE table_schema = DATABASE();"
    end
    rows = db.query(db_path, query)
    if rows == nil then
        return {}
    end
    names = {}
    for _, row in ipairs(rows) do
        table.insert(names, row.name)
    end
    return names
end

function db.get_columns(db_path, table_name)
    query = "PRAGMA table_info(" .. table_name .. ");"
    if is_mariadb(db_path) then
        query = string.format(
            "SELECT column_name AS name FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = %s ORDER BY ordinal_position;",
            db.quote(table_name)
        )
    end
    rows = db.query(db_path, query)
    if rows == nil then
        return {}
    end
    names = {}
    for _, row in ipairs(rows) do
        table.insert(names, row.name)
    end
    return names
end

function db.table_exists(db_path, table_name)
    query = string.format(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = %s;", db.quote(table_name)
    )
    if is_mariadb(db_path) then
        query = string.format(
            "SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = %s;",
            db.quote(table_name)
        )
    end
    rows = db.query(db_path, query)
    return rows != nil
end

-- Backtick-quotes a raw SQL identifier (column/index name), not a value --
-- db.quote/db.literal already cover values. Needed anywhere a
-- caller-defined field name (arbitrary, not controlled by this
-- module) gets interpolated as a column identifier: MySQL's reserved-
-- word list is much larger than SQLite's or MariaDB's own extensions
-- allow around, so a real field genuinely named e.g. "usage" breaks
-- CREATE TABLE/INSERT/UPDATE outright without this. Backtick quoting
-- is valid MySQL/MariaDB syntax and SQLite's own MySQL-compatibility
-- extension, so this is a single, unified fix needing no per-backend
-- branch.
function db.quote_ident(name)
    return "`" .. tostring(name) .. "`"
end

-- Real MySQL (unlike MariaDB, and unlike MySQL's own CREATE TABLE) has no
-- "IF NOT EXISTS" clause for CREATE INDEX at all -- a syntax error, not a
-- no-op. Every CREATE INDEX call site should check this first instead of
-- relying on IF NOT EXISTS, same "check, then conditionally create"
-- shape as db.table_exists already gives.
function db.index_exists(db_path, table_name, index_name)
    query = string.format(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name = %s;", db.quote(index_name)
    )
    if is_mariadb(db_path) then
        query = string.format(
            "SELECT DISTINCT index_name FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = %s AND index_name = %s;",
            db.quote(table_name), db.quote(index_name)
        )
    end
    rows = db.query(db_path, query)
    return rows != nil
end

-- Quotes a value as a safe SQL string literal: plain quote-doubling, no
-- db_path/backend parameter needed here. Correct for MariaDB too as
-- long as the connection sets NO_BACKSLASH_ESCAPES (see luam's
-- get_mariadb_connection) -- without that, a value containing a
-- literal backslash-letter sequence (a Windows path, a regex) would
-- silently come back transformed on read, even though quote-doubling
-- alone already safely closes the string boundary either way. Keeping
-- this a pure, backend-agnostic function (rather than threading
-- db_path through it) avoids a ripple through every db.quote/db.literal
-- call site, none of which need to change.
function db.quote(value)
    return "'" .. string.gsub(tostring(value), "'", "''") .. "'"
end

-- Renders `value` as a safe SQL literal: NULL for nil, a quoted string
-- otherwise. Numbers/booleans are stringified and quoted too, which is
-- harmless for either backend's dynamic-enough typing and keeps
-- callers from needing two code paths.
function db.literal(value)
    if value == nil then
        return "NULL"
    end
    return db.quote(value)
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
function db.now_expr(db_path)
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
function db.autoincrement_keyword(db_path)
    if is_mariadb(db_path) then
        return "AUTO_INCREMENT"
    end
    return "AUTOINCREMENT"
end

-- Upsert-by-replace statement prefix (goes before "<table> (<cols>) VALUES ...").
-- MariaDB's REPLACE INTO needs no "INSERT OR" prefix; semantics match
-- SQLite's INSERT OR REPLACE closely enough as long as no foreign-key
-- constraints exist for its delete+insert behavior to disturb.
function db.replace_into(db_path)
    if is_mariadb(db_path) then
        return "REPLACE INTO"
    end
    return "INSERT OR REPLACE INTO"
end

-- Insert-ignoring-conflicts statement prefix (goes before "<table> (<cols>) VALUES ...").
function db.insert_ignore(db_path)
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
function db.text_index_column(db_path, column_name)
    if is_mariadb(db_path) then
        return column_name .. "(255)"
    end
    return column_name
end

return db
