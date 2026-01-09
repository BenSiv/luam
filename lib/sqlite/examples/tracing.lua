
require("lsqlite3")

db = sqlite3.open_memory()

db.trace(db,  function(ud, sql)
  print("Sqlite Trace:", sql)
end )

db:exec[[
  CREATE TABLE test ( id INTEGER PRIMARY KEY, content VARCHAR );

  INSERT INTO test VALUES (NULL, 'Hello World');
  INSERT INTO test VALUES (NULL, 'Hello Lua');
  INSERT INTO test VALUES (NULL, 'Hello Sqlite3');
]]

for row in db.rows(db, "SELECT * FROM test") do
  -- NOP
end
