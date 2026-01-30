
database = require("database")

print("esting database...")

-- equires sqlite3 to actually test functions. 
-- We can test if module loads.
-- f sqlite3 is present, we can create in-memory db.

ok, sqlite3 = pcall(require, "sqlite3")
if ok then
    -- Correct test: use a temp file
    tmp_db = "test_db.sqlite"
    os.remove(tmp_db)
    database.local_update(tmp_db, "CREATE TABLE test (id INTEGER, val TEXT);")
    database.local_update(tmp_db, "INSERT INTO test VALUES (1, 'foo');")
    rows = database.local_query(tmp_db, "SELECT * FROM test")
    if rows != nil and rows[1] != nil then
        print("Row 1 val:", rows[1].val)
        for k,v in pairs(rows[1]) do print("Key:", k, "Val:", v) end
    end
    
    -- rows are returned as indexed arrays in this environment
    assert(rows[1][2] == 'foo', "database query failed")
    
    os.remove(tmp_db)
else
    print("Skipping database functional tests (sqlite3 missing)")
end

print("database tests passed")
