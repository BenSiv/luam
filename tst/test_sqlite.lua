
-- Set path to include local sqlite3 library
-- package.path set by runner

print("Loading sqlite3...")
ok, sqlite3 = pcall(require, "sqlite3")

if not ok then
    print("Failed to load sqlite3: " .. tostring(sqlite3))
    print("Skipping sqlite3 test due to missing dependencies.")
    os.exit(0)
end

print("SQLite3 loaded.")

-- Create in-memory DB
db = sqlite3.open_memory()
print("Opened memory DB")

-- Calls go through the module table (sqlite3.exec(db, ...)), not
-- db.exec(...)/db:exec(...) -- confirmed directly against this Luam
-- build that field-indexing a userdata doesn't dispatch through its
-- metatable here, even though the underlying C binding sets one up
-- correctly (a real Luam-level limitation, not a bug in this binding).
-- Matches lib/database.lua's own actual calling convention exactly.
sqlite3.exec(db, "CREATE TABLE test (id INTEGER PRIMARY KEY, content TEXT); INSERT INTO test (content) VALUES ('Hello SQLite'); INSERT INTO test (content) VALUES ('Lua is great');")

-- nrows (named-field rows), not rows (positional-only, row[1]/row[2] --
-- confirmed directly that plain .rows leaves row.id/row.content nil).
count = 0
for row in sqlite3.nrows(db, "SELECT * FROM test") do
  print(row.id, row.content)
  count = count + 1
end

assert(count == 2, "Expected 2 rows")

sqlite3.close(db)
print("SQLite3 tests passed")
