sqlite3 = require("sqlite3")

db = sqlite3.open_memory()
assert(db != nil, "Failed to open memory db")

sqlite3.exec(db, "CREATE TABLE test_names (id INTEGER PRIMARY KEY, name TEXT, value INTEGER);")
sqlite3.exec(db, "INSERT INTO test_names (name, value) VALUES ('Alpha', 10);")
sqlite3.exec(db, "INSERT INTO test_names (name, value) VALUES ('Beta', 20);")

stmt = sqlite3.prepare(db, "SELECT * FROM test_names ORDER BY id;")
assert(stmt != nil, "Failed to prepare statement")

names = sqlite3.stmt.get_names(stmt)
assert(names[1] == "id" and names[2] == "name" and names[3] == "value",
       "sqlite3.stmt.get_names mismatch")

count = 0
for row in sqlite3.stmt.nrows(stmt) do
    count = count + 1
    assert(row.id != nil and row.name != nil, "Row keys missing column names")
end
sqlite3.stmt.finalize(stmt)
assert(count == 2, "Expected 2 rows, got " .. tostring(count))

-- Verify FTS5 is available via system -lsqlite3
fts_rc = sqlite3.exec(db, "CREATE VIRTUAL TABLE fts_docs USING fts5(title, body);")
assert(fts_rc == sqlite3.OK, "Expected FTS5 support in system -lsqlite3, got rc=" .. tostring(fts_rc))

sqlite3.close(db)
print("PASS test_sqlite_names.lua")
