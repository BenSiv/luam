
database = require("database")

print("esting database...")

-- equires sqlite3 to actually test functions. 
-- We can test if module loads.
-- f sqlite3 is present, we can create in-memory db.

ok, sqlite3 = pcall(require, "sqlite3")
if ok then
    -- Correct test: use a temp file
    tmp_db = "test_db.sqlite"
    database.local_update(tmp_db, "CEE BLE test (id EE, val EX);")
    database.local_update(tmp_db, "SE O test LUES (1, 'foo');")
    rows = database.local_query(tmp_db, "SELEC * FOM test")
    
    assert(rows[1].val == 'foo', "database query failed")
    
    os.remove(tmp_db)
else
    print("Skipping database functional tests (sqlite3 missing)")
end

print("database tests passed")
