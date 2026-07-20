
database = require("database")

print("Testing database...")

-- Requires sqlite3 to actually test functions.
-- We can test if module loads.
-- If sqlite3 is present, we can create in-memory db.

ok, sqlite3 = pcall(require, "sqlite3")
if ok then
    -- Correct test: use a temp file
    tmp_db = "test_db.sqlite"
    database.sqlite_update(tmp_db, "CREATE TABLE test (id INTEGER PRIMARY KEY AUTOINCREMENT, val TEXT);")

    -- sqlite_update's second return value is last_insert_rowid(), read
    -- on the same connection the insert itself ran on -- connection-
    -- scoped and therefore race-free under concurrent writers, unlike
    -- a separate SELECT MAX(id) query (see ledger.lua's own fix for
    -- exactly this, task #77).
    ok2, insert_id = database.sqlite_update(tmp_db, "INSERT INTO test (val) VALUES ('foo');")
    assert(ok2 == true, "expected sqlite_update to return true")
    assert(insert_id > 0, "expected a positive insert_id, got " .. tostring(insert_id))

    rows = database.sqlite_query(tmp_db, "SELECT * FROM test")

    assert(rows[1].val == 'foo', "database query failed")
    assert(tonumber(rows[1].id) == insert_id, "insert_id should match the row's own id")

    os.remove(tmp_db)
else
    print("Skipping database functional tests (sqlite3 missing)")
end

print("database tests passed")
