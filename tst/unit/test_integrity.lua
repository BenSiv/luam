
database = require("database")
utils = require("utils")
lfs = require("lfs")
sqlite = require("sqlite3")

print("Running database integrity integrity test...")

-- 1. Verify String Constants (Indirectly via function usage)
-- If strings like "SELECT" were corrupted to "SELEC", preparing a query would fail.

-- Setup temp db
tmp_db = "integrity_test.db"
os.remove(tmp_db)

-- Open DB to ensure sqlite works
db = sqlite.open(tmp_db)
if db == nil then
    error("Failed to create temp db")
end
sqlite.close(db)

-- 2. Test local_update (INSERT)
-- This uses "INSERT INTO..." or similar. If the string is corrupted in the library, this will fail.
print("Testing local_update...")
status, err = pcall(function() 
    return database.local_update(tmp_db, "CREATE TABLE test_table (id INTEGER PRIMARY KEY, content TEXT);") 
end)

if not status then
    error("failed to create table: " .. tostring(err))
end

status, err = pcall(function()
    return database.local_update(tmp_db, "INSERT INTO test_table (content) VALUES ('hello world');")
end)

if not status then
    error("failed to insert data: " .. tostring(err))
end


-- 3. Test local_query (SELECT)
-- This uses "SELECT ..." inside. If "SELECT" is corrupted in the library? 
-- Actually local_query takes the query string as arg, but `get_tables` or `get_schema` use internal queries.
-- Let's test a simple query first.
print("Testing local_query...")
rows = database.local_query(tmp_db, "SELECT * FROM test_table;")
if rows == nil or #rows != 1 then
    error("Query failed or returned wrong number of rows")
end

-- rows are indexed arrays
if rows[1][2] != "hello world" then
    error("Query returned wrong content: " .. tostring(rows[1][2]))
end

-- 4. Test internal queries in helper functions
-- `get_tables` uses "SELECT name FROM sqlite_master ..."
print("Testing get_tables...")
tables = database.get_tables(tmp_db)
if tables == nil or not utils.in_table("test_table", tables) then
    error("get_tables failed to find test_table")
end

-- 5. Test get_columns / get_schema which uses "PRAGMA table_info"
print("Testing get_columns...")
cols = database.get_columns(tmp_db, "test_table")
if cols == nil or not utils.in_table("content", cols) then
    error("get_columns failed to find content column")
end

-- 6. Test Error Handling
-- We want to ensure that an invalid query raises a clear error, not a cryptic one or a crash.
print("Testing error handling...")
status, err = pcall(function()
    database.local_query(tmp_db, "SELECT * FROM non_existent_table;")
end)

if status then
    error("Expected error for non-existent table, but got success")
end

if string.find(err, "no such table") == nil and string.find(err, "Generic error") == nil then 
    -- "Generic error" sometimes comes from older sqlite wrappers, but we expect "no such table" usually.
    -- luam/database.lua now appends db error message.
    print("Warning: Error message might be vague: " .. tostring(err))
end
print("Caught expected error: " .. err)

-- Cleanup
os.remove(tmp_db)
print("Database integrity check passed!")
