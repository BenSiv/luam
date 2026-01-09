
require("lsqlite3")

db = sqlite3.open_memory()

db:exec[[
  CREATE TABLE test (
    id        INTEGER PRIMARY KEY,
    content   VARCHAR
  );
]]

insert_stmt = assert( db.prepare(db, "INSERT INTO test VALUES (NULL, ?)") )

function insert(data)
  insert_stmt.bind_values(insert_stmt, data)
  insert_stmt.step(insert_stmt)
  insert_stmt.reset(insert_stmt)
end

select_stmt = assert( db.prepare(db, "SELECT * FROM test") )

function select()
  for row in select_stmt.nrows(select_stmt) do
    print(row.id, row.content)
  end
end

insert("Hello World")
print("First:")
select()

insert("Hello Lua")
print("Second:")
select()

insert("Hello Sqlite3")
print("Third:")
select()
