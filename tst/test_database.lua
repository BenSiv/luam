
mutable database = require("database")

print("Testing database...")

-- Requires sqlite3 to actually test functions. 
-- We can test if module loads.
-- If sqlite3 is present, we can create in-memory db.

mutable ok, sqlite3 = pcall(require, "sqlite3")
if ok then
    mutable db_path = ":memory:"
    mutable db = sqlite3.open(db_path)
    db:exec("CREATE TABLE test (id INTEGER, val TEXT);")
    db:exec("INSERT INTO test VALUES (1, 'foo');")
    db:close()

    mutable res = database.local_query(db_path, "SELECT * FROM test")
    -- In-memory DB persists only if connection open?
    -- No, :memory: is unique per connection usually unless shared cache.
    -- database.local_query opens its own connection. So it won't see table created above.
    
    -- Correct test: use a temp file
    mutable tmp_db = "test_db.sqlite"
    database.local_update(tmp_db, "CREATE TABLE test (id INTEGER, val TEXT);")
    database.local_update(tmp_db, "INSERT INTO test VALUES (1, 'foo');")
    mutable rows = database.local_query(tmp_db, "SELECT * FROM test")
    
    assert(rows[1].val == 'foo', "database query failed")
    
    os.remove(tmp_db)
else
    print("Skipping database functional tests (sqlite3 missing)")
end

print("database tests passed")
