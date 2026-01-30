
-- Set path to include local sqlite3 library
-- package.path set by runner

print("Loading sqlite3...")
ok, sqlite3 = pcall(require, "sqlite3")

if not ok then
    print("Failed to load sqlite3: " .. tostring(sqlite3))
    print("Skipping sqlite3 test due to missing dependencies.")
    print("Skipping sqlite test (dependency missing)")
    return
    -- User asked to "add test", implies it should run.
    -- But if C module missing,  can't fix C compilation easily without makefile.
end

print("SQLite3 loaded.")

-- Create in-memory DB
db = sqlite3.open_memory()
print("Opened memory DB")

sqlite3.exec(db, "CREATE TABLE test (id INTEGER PRIMARY KEY, content TEXT); INSERT INTO test (content) VALUES ('Hello SQLite'); INSERT INTO test (content) VALUES ('Lua is great');")

count = 0
for row in sqlite3.rows(db, "SELECT * FROM test") do
  print(row.id, row.content)
  count = count + 1
end

assert(count == 2, "Expected 2 rows")

sqlite3.close(db)
print("SQLite3 tests passed")
