
print("Testing database.lua's mariadb_* wrapper (persistent connections)...")

-- Same skip-not-fail gating as tst/test_mariadb.lua -- see that file's
-- own header comment for why. database module itself always loads
-- (mariadb_native is lazy inside it, see database.lua's own comment),
-- so this only needs to pcall-gate the actual mariadb_update call.
database = require("database")

host = os.getenv("MARIADB_TEST_HOST")
if host == nil then host = "127.0.0.1" end
port = tonumber(os.getenv("MARIADB_TEST_PORT"))
if port == nil then port = 3306 end
user = os.getenv("MARIADB_TEST_USER")
if user == nil then user = "luam_test" end
password = os.getenv("MARIADB_TEST_PASSWORD")
if password == nil then password = "luam_test_pw" end
database_name = os.getenv("MARIADB_TEST_DATABASE")
if database_name == nil then database_name = "luam_test" end

descriptor = {host = host, port = port, user = user, password = password, database = database_name}

ok, err = pcall(function() return database.mariadb_update(descriptor, "SELECT 1;") end)
if not ok then
    print("Skipping mariadb wrapper tests (no reachable test server / module: " .. tostring(err) .. ")")
    os.exit(0)
end

database.mariadb_update(descriptor, "DROP TABLE IF EXISTS luam_mariadb_wrapper_test;")
database.mariadb_update(descriptor, "CREATE TABLE luam_mariadb_wrapper_test (id INT PRIMARY KEY AUTO_INCREMENT, val TEXT);")

-- %s-style interpolation with auto-escaped string varargs -- same
-- calling convention as sqlite_update's sqlite path, confirming a
-- dangerous value is escaped, not just concatenated raw.
affected, insert_id = database.mariadb_update(
    descriptor, "INSERT INTO luam_mariadb_wrapper_test (val) VALUES ('%s');", "O'Brien"
)
assert(affected == 1, "expected 1 affected row")
assert(insert_id > 0, "expected a positive insert_id")

rows, column_names = database.mariadb_query(descriptor, "SELECT * FROM luam_mariadb_wrapper_test;")
assert(rows != nil, "expected rows back")
assert(#rows == 1, "expected 1 row")
assert(rows[1].val == "O'Brien", "escaped value round-trip mismatch: " .. tostring(rows[1].val))

-- Connection reuse: repeated calls must not grow the cache -- the
-- entire point of this wrapper existing over an open-per-call model.
count_before = database.mariadb_connection_count()
assert(count_before == 1, "expected exactly 1 cached connection, got " .. tostring(count_before))

for i = 1, 5 do
    database.mariadb_query(descriptor, "SELECT * FROM luam_mariadb_wrapper_test;")
end

count_after = database.mariadb_connection_count()
assert(count_after == 1, "expected connection count to stay at 1 after repeated calls, got " .. tostring(count_after))

-- Bad statement surfaces as a real Lua error (matches sqlite_update/
-- sqlite_query's own error() convention), not a silent nil.
ok3 = pcall(function() return database.mariadb_query(descriptor, "SELECT * FROM a_table_that_does_not_exist;") end)
assert(ok3 == false, "expected an error for a query against a nonexistent table")

database.mariadb_update(descriptor, "DROP TABLE luam_mariadb_wrapper_test;")
database.mariadb_close_all()

count_final = database.mariadb_connection_count()
assert(count_final == 0, "expected mariadb_close_all() to empty the connection cache")

print("database.lua mariadb_* wrapper tests passed")
