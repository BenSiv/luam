
require("lsqlite3")

db = sqlite3.open_memory()

db:exec[[ CREATE TABLE test (id INTEGER PRIMARY KEY, content) ]]

stmt = db:prepare[[ INSERT INTO test VALUES (:key, :value) ]]

stmt:bind_names{  key = 1,  value = "Hello World"    }
stmt.step(stmt)
stmt.reset(stmt)
stmt:bind_names{  key = 2,  value = "Hello Lua"      }
stmt.step(stmt)
stmt.reset(stmt)
stmt:bind_names{  key = 3,  value = "Hello Sqlite3"  }
stmt.step(stmt)
stmt.finalize(stmt)

for row in db.nrows(db, "SELECT * FROM test") do
  print(row.id, row.content)
end
