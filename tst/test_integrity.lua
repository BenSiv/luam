database = require("database")

tmp_db = os.tmpname()
os.remove(tmp_db)

database.exec(tmp_db, "CREATE TABLE test_table (id INTEGER PRIMARY KEY, content TEXT, active INTEGER);")
database.query_params(tmp_db, "INSERT INTO test_table (content, active) VALUES (?, ?);", {"hello world", true})

rows = database.query(tmp_db, "SELECT id, content, active FROM test_table;")
assert(rows != nil and #rows == 1, "Query returned wrong number of rows")
assert(rows[1].content == "hello world", "Unexpected content: " .. tostring(rows[1].content))
assert(tonumber(rows[1].active) == 1, "Boolean true param must normalize to integer 1, got " .. tostring(rows[1].active))

assert(database.table_exists(tmp_db, "test_table") == true, "table_exists failed")
cols = database.get_columns(tmp_db, "test_table")
found_content = false
for _, c in ipairs(cols) do
    if c == "content" then
        found_content = true
    end
end
assert(found_content == true, "get_columns failed to find content column")

function bad_select()
    database.query(tmp_db, "SELECT * FROM non_existent_table;")
end
ok, err = pcall(bad_select)
assert(ok == false and string.contains(tostring(err), "no such table"), "Expected error for missing table")

os.remove(tmp_db)
print("PASS test_integrity.lua")
