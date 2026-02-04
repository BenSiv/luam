
print("Loading sqlite3...")
ok, sqlite3 = pcall(require, "sqlite3")

if not ok then
    print("Failed to load sqlite3: " .. tostring(sqlite3))
    os.exit(1)
end

print("SQLite3 loaded.")

-- Test case for named columns issue
-- We want to verify that we can retrieve column names correctly

db = sqlite3.open_memory()
assert(db, "Failed to open memory db")

db.exec(db, "CREATE TABLE test_names (id INTEGER PRIMARY KEY, name TEXT, value INTEGER);")
db.exec(db, "INSERT INTO test_names (name, value) VALUES ('Alpha', 10);")
db.exec(db, "INSERT INTO test_names (name, value) VALUES ('Beta', 20);")

print("Checking column names retrieval...")

-- Standard query
stmt = db.prepare(db, "SELECT * FROM test_names ORDER BY id;")
assert(stmt, "Failed to prepare statement")

names_found = false

-- Method 1: Check if we can get names from statement before stepping
if stmt.get_names then
    names = stmt.get_names(stmt)
    print("stmt:get_names():", table.concat(names, ", "))
    if names[1] == "id" and names[2] == "name" and names[3] == "value" then
         names_found = true
         print("Verified names via get_names")
    end
elseif sqlite3.stmt and sqlite3.stmt.get_names then
     names = sqlite3.stmt.get_names(stmt)
     print("sqlite3.stmt.get_names(stmt):", table.concat(names, ", "))
     if names[1] == "id" and names[2] == "name" and names[3] == "value" then
         names_found = true
          print("Verified names via sqlite3.stmt.get_names")
     end
end

-- Method 2: Check standard 'columns' count and individual name retrieval
if not names_found then
    cols = stmt.columns(stmt)
    print("Column count:", cols)
    collected_names = {}
    for i=0, cols-1 do
        table.insert(collected_names, stmt.get_name(stmt, i))
    end
    print("Names via get_name(i):", table.concat(collected_names, ", "))
    if collected_names[1] == "id" and collected_names[2] == "name" then
        names_found = true
    end
end

-- Method 3: Verify nrows iterator (which should yield named table)
print("Testing nrows iterator...")
count = 0
iterator = nil
if stmt.nrows then
    iterator = stmt.nrows
elseif sqlite3.stmt and sqlite3.stmt.nrows then
    iterator = sqlite3.stmt.nrows 
end

if iterator then
    for row in iterator(stmt) do
        count = count + 1
        print("Row " .. count .. ": id=" .. tostring(row.id) .. ", name=" .. tostring(row.name))
        if row.id == nil or row.name == nil then
            print("FAIL: Row keys are missing names!")
            os.exit(1)
        end
    end
else
    print("FAIL: nrows not found")
end
stmt.finalize(stmt)

if count != 2 then
    print("FAIL: Expected 2 rows, got " .. count)
    os.exit(1)
end

db.close(db)
print("SUCCESS: SQLite column names test passed")
