
print("Testing mariadb...")

-- Requires libmariadb-dev to have been present at build time (module
-- load) AND a real, reachable MariaDB server to actually run queries
-- against (unlike sqlite3, which needs neither -- it's an embedded,
-- file-based engine with zero external service dependency). Both are
-- treated as "skip", not "fail", the same way test_database.lua skips
-- its own functional half when sqlite3 is missing -- a dev machine or
-- CI runner without a MariaDB server configured shouldn't fail the
-- whole suite over it.
--
-- Connection details come from env vars with locally-sensible
-- defaults, not hardcoded production-shaped credentials -- set
-- MARIADB_TEST_HOST/PORT/USER/PASSWORD/DATABASE to point this at a
-- real test server (see doc/mariadb-migration.md in platform-wip for
-- the schema/dialect work this binding unblocks).
ok, mariadb = pcall(require, "mariadb")
if not ok then
    print("Skipping mariadb functional tests (module failed to load: " .. tostring(mariadb) .. ")")
    os.exit(0)
end

host = os.getenv("MARIADB_TEST_HOST")
if host == nil then host = "127.0.0.1" end
port = tonumber(os.getenv("MARIADB_TEST_PORT"))
if port == nil then port = 3306 end
user = os.getenv("MARIADB_TEST_USER")
if user == nil then user = "luam_test" end
password = os.getenv("MARIADB_TEST_PASSWORD")
if password == nil then password = "luam_test_pw" end
database = os.getenv("MARIADB_TEST_DATABASE")
if database == nil then database = "luam_test" end

conn, err = mariadb.connect(host, port, user, password, database)
if conn == nil then
    print("Skipping mariadb functional tests (no reachable test server: " .. tostring(err) .. ")")
    os.exit(0)
end

-- Real functions live flat on the module table (mariadb.query(conn, ...),
-- not conn.query(conn, ...)/conn:query(...)) -- verified directly against
-- this Luam build that userdata field-indexing doesn't dispatch through
-- a metatable's __index here, the same limitation lib/sqlite/lsqlite3.c's
-- own db/stmt objects already have (lib/database.lua's sqlite_query/
-- sqlite_update always call sqlite.exec(db, ...), never db.exec(...)).

mariadb.exec(conn, "DROP TABLE IF EXISTS luam_mariadb_test;")
affected, insert_id = mariadb.exec(conn, "CREATE TABLE luam_mariadb_test (id INT PRIMARY KEY AUTO_INCREMENT, val TEXT);")

_, first_id = mariadb.exec(conn, "INSERT INTO luam_mariadb_test (val) VALUES ('foo');")
assert(first_id > 0, "expected a positive AUTO_INCREMENT insert_id")
_, second_id = mariadb.exec(conn, "INSERT INTO luam_mariadb_test (val) VALUES ('bar');")
assert(second_id == first_id + 1, "expected consecutive AUTO_INCREMENT ids")

rows, err = mariadb.query(conn, "SELECT * FROM luam_mariadb_test ORDER BY id;")
assert(rows != nil, "query failed: " .. tostring(err))
assert(#rows == 2, "expected 2 rows, got " .. tostring(#rows))
assert(rows[1].val == "foo", "row1 val mismatch")
assert(rows[2].val == "bar", "row2 val mismatch")

-- NULL decodes as Lua nil, not the string "NULL" or "" -- matters since
-- database.lua's own sqlite path fills missing columns with "" (line
-- ~104), a convention this binding deliberately does NOT replicate --
-- see lmariadb.c's push_result_rows comment.
_, null_id = mariadb.exec(conn, "INSERT INTO luam_mariadb_test (val) VALUES (NULL);")
rows, err = mariadb.query(conn, "SELECT val FROM luam_mariadb_test WHERE id = " .. tostring(null_id) .. ";")
assert(rows[1].val == nil, "expected NULL column to decode as nil")

-- escape() is real mysql_real_escape_string, not a naive gsub -- confirm
-- a SQL-injection-shaped value round-trips safely through it.
dangerous = "O'Brien'; DROP TABLE luam_mariadb_test;--"
escaped = mariadb.escape(conn, dangerous)
mariadb.exec(conn, "INSERT INTO luam_mariadb_test (val) VALUES ('" .. escaped .. "');")
rows, err = mariadb.query(conn, "SELECT val FROM luam_mariadb_test WHERE val LIKE '%Brien%';")
assert(#rows == 1 and rows[1].val == dangerous, "escape() round-trip failed")

-- table survived (escape() actually prevented the injection, not just
-- happened to not blow up)
rows, err = mariadb.query(conn, "SELECT COUNT(*) AS n FROM luam_mariadb_test;")
assert(tonumber(rows[1].n) == 4, "expected the table to still exist with 4 rows after the escape() test")

assert(mariadb.ping(conn) == true, "ping should report true on a live connection")

-- error paths: bad SQL returns nil+err (not a thrown error), a closed
-- connection errors loudly on further use (not a silent no-op)
rows, err = mariadb.query(conn, "SELECT * FROM a_table_that_does_not_exist;")
assert(rows == nil and err != nil, "expected nil+err for a query against a nonexistent table")

mariadb.exec(conn, "DROP TABLE luam_mariadb_test;")
mariadb.close(conn)
assert(mariadb.isopen(conn) == false, "expected isopen() false after close()")
ok2 = pcall(function() return mariadb.query(conn, "SELECT 1;") end)
assert(ok2 == false, "expected an error using a closed connection, not a silent failure")

print("mariadb tests passed")
