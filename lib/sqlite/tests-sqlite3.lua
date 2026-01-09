
--[[--------------------------------------------------------------------------

    Author: Michael Roth <mroth@nessie.de>

    Copyright (c) 2004, 2005 Michael Roth <mroth@nessie.de>

    Permission is hereby granted, free of charge, to any person 
    obtaining a copy of this software and associated documentation
    files (the "Software"), to deal in the Software without restriction,
    including without limitation the rights to use, copy, modify, merge,
    publish, distribute, sublicense, and/or sell copies of the Software,
    and to permit persons to whom the Software is furnished to do so,
    subject to the following conditions:

    The above copyright notice and this permission notice shall be 
    included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

--]]--------------------------------------------------------------------------


require "lsqlite3"

require "lunit"

lunit.setprivfenv()
lunit.import "assertions"
lunit.import "checks"






-------------------------------
-- Basic open and close test --
-------------------------------

lunit.wrap("open_memory", function()
 db = assert_userdata( sqlite3.open_memory() )
  assert( db.close(db) )
end)

lunit.wrap("open", function()
 filename = "/tmp/__lua-sqlite3-20040906135849." .. os.time()
 db = assert_userdata( sqlite3.open(filename) )
  assert( db.close(db) )
  os.remove(filename)
end)



-------------------------------------
-- Presence of db member functions --
-------------------------------------

db_funcs = lunit.TestCase("Database Member Functions")

function db_funcs.setup(db_funcs)
  self.db = assert( sqlite3.open_memory() )
end

function db_funcs.teardown(db_funcs)
  assert( self.db.close(db) )
end

function db_funcs.test(db_funcs)
 db = self.db
  assert_function( db.close )
  assert_function( db.exec )
--e  assert_function( db.irows )
  assert_function( db.rows )
--e  assert_function( db.cols )
--e  assert_function( db.first_irow )
--e  assert_function( db.first_row )
--e  assert_function( db.first_cols )
  assert_function( db.prepare )
  assert_function( db.interrupt )
  assert_function( db.last_insert_rowid )
  assert_function( db.changes )
  assert_function( db.total_changes )
end



---------------------------------------
-- Presence of stmt member functions --
---------------------------------------

stmt_funcs = lunit.TestCase("Statement Member Functions")

function stmt_funcs.setup(stmt_funcs)
  self.db = assert( sqlite3.open_memory() )
  self.stmt = assert( self.db.prepare(db, "CREATE TABLE test (id, content)") )
end

function stmt_funcs.teardown(stmt_funcs)
--e-  assert( self.stmt.close(stmt) )
  assert( self.stmt.finalize(stmt) ) --e+
  assert( self.db.close(db) )
end

function stmt_funcs.test(stmt_funcs)
 stmt = self.stmt
--e  assert_function( stmt.close )
  assert_function( stmt.reset )
--e  assert_function( stmt.exec )
  assert_function( stmt.bind )
--e  assert_function( stmt.irows )
--e  assert_function( stmt.rows )
--e  assert_function( stmt.cols )
--e  assert_function( stmt.first_irow )
--e  assert_function( stmt.first_row )
--e  assert_function( stmt.first_cols )
--e  assert_function( stmt.column_names )
--e  assert_function( stmt.column_decltypes )
--e  assert_function( stmt.column_count )
--e +
  assert_function( stmt.isopen )
  assert_function( stmt.step )
  assert_function( stmt.reset )
  assert_function( stmt.finalize )
  assert_function( stmt.columns )
  assert_function( stmt.bind )
  assert_function( stmt.bind_values )
  assert_function( stmt.bind_names )
  assert_function( stmt.bind_blob )
  assert_function( stmt.bind_parameter_count )
  assert_function( stmt.bind_parameter_name )
  assert_function( stmt.get_value )
  assert_function( stmt.get_values )
  assert_function( stmt.get_name )
  assert_function( stmt.get_names )
  assert_function( stmt.get_type )
  assert_function( stmt.get_types )
  assert_function( stmt.get_uvalues )
  assert_function( stmt.get_unames )
  assert_function( stmt.get_utypes )
  assert_function( stmt.get_named_values )
  assert_function( stmt.get_named_types )
  assert_function( stmt.idata )
  assert_function( stmt.inames )
  assert_function( stmt.itypes )
  assert_function( stmt.data )
  assert_function( stmt.type )
--e +
end



------------------
-- Tests basics --
------------------

basics = lunit.TestCase("Basics")

function basics.setup(basics)
  self.db = assert_userdata( sqlite3.open_memory() )
end

function basics.teardown(basics)
  assert_number( self.db.close(db) )
end

function basics.create_table(basics)
  assert_number( self.db.exec(db, "CREATE TABLE test (id, name)") )
end

function basics.drop_table(basics)
  assert_number( self.db.exec(db, "DROP TABLE test") )
end

function basics.insert(basics, id, name)
  assert_number( self.db.exec(db, "INSERT INTO test VALUES ("..id..", '"..name.."')") )
end

function basics.update(basics, id, name)
  assert_number( self.db.exec(db, "UPDATE test SET name = '"..name.."' WHERE id = "..id) )
end

function basics.test_create_drop(basics)
  self.create_table(self)
  self.drop_table(self)
end

function basics.test_multi_create_drop(basics)
  self.create_table(self)
  self.drop_table(self)
  self.create_table(self)
  self.drop_table(self)
end

function basics.test_insert(basics)
  self.create_table(self)
  self.insert(self, 1, "Hello World")
  self.insert(self, 2, "Hello Lua")
  self.insert(self, 3, "Hello sqlite3")
end

function basics.test_update(basics)
  self.create_table(self)
  self.insert(self, 1, "Hello Home")
  self.insert(self, 2, "Hello Lua")
  self.update(self, 1, "Hello World")
end


---------------------------------
-- Statement Column Info Tests --
---------------------------------

lunit.wrap("Column Info Test", function()
 db = assert_userdata( sqlite3.open_memory() )
  assert_number( db.exec(db, "CREATE TABLE test (id INTEGER, name TEXT)") )
 stmt = assert_userdata( db.prepare(db, "SELECT * FROM test") )
  
  assert_equal(2, stmt.columns(stmt), "Wrong number of columns." )
  
 names = assert_table( stmt.get_names(stmt) )
  assert_equal(2, #(names), "Wrong number of names.")
  assert_equal("id", names[1] )
  assert_equal("name", names[2] )
  
 types = assert_table( stmt.get_types(stmt) )
  assert_equal(2, #(types), "Wrong number of declaration types.")
  assert_equal("INTEGER", types[1] )
  assert_equal("TEXT", types[2] )
  
  assert_equal( sqlite3.OK, stmt.finalize(stmt) )
  assert_equal( sqlite3.OK, db.close(db) )
end)



---------------------
-- Statement Tests --
---------------------

st = lunit.TestCase("Statement Tests")

function st.setup(st)
  self.db = assert( sqlite3.open_memory() )
  assert_equal( sqlite3.OK, self.db.exec(db, "CREATE TABLE test (id, name)") )
  assert_equal( sqlite3.OK, self.db.exec(db, "INSERT INTO test VALUES (1, 'Hello World')") )
  assert_equal( sqlite3.OK, self.db.exec(db, "INSERT INTO test VALUES (2, 'Hello Lua')") )
  assert_equal( sqlite3.OK, self.db.exec(db, "INSERT INTO test VALUES (3, 'Hello sqlite3')") )
end

function st.teardown(st)
  assert_equal( sqlite3.OK, self.db.close(db) )
end

function st.check_content(st, expected)
 stmt = assert( self.db.prepare(db, "SELECT * FROM test ORDER BY id") )
 i = 0
  for row in stmt.rows(stmt) do
    i = i + 1
    assert( i <= #(expected), "Too many rows." )
    assert_equal(2, #(row), "Two result column expected.")
    assert_equal(i, row[1], "Wrong 'id'.")
    assert_equal(expected[i], row[2], "Wrong 'name'.")
  end
  assert_equal( #(expected), i, "Too few rows." )
  assert_number( stmt.finalize(stmt) )
end

function st.test_setup(st)
  assert_pass(function() self:check_content{ "Hello World", "Hello Lua", "Hello sqlite3" } end)
  assert_error(function() self:check_content{ "Hello World", "Hello Lua" } end)
  assert_error(function() self:check_content{ "Hello World", "Hello Lua", "Hello sqlite3", "To much" } end)
  assert_error(function() self:check_content{ "Hello World", "Hello Lua", "Wrong" } end)
  assert_error(function() self:check_content{ "Hello World", "Wrong", "Hello sqlite3" } end)
  assert_error(function() self:check_content{ "Wrong", "Hello Lua", "Hello sqlite3" } end)
end

function st.test_questionmark_args(st)
 stmt = assert_userdata( self.db.prepare(db, "INSERT INTO test VALUES (?, ?)")  )
  assert_number( stmt.bind_values(stmt, 0, "Test") )
  assert_error(function() stmt.bind_values(stmt, "To few") end)
  assert_error(function() stmt.bind_values(stmt, 0, "Test", "To many") end)
end

function st.test_questionmark(st)
 stmt = assert_userdata( self.db.prepare(db, "INSERT INTO test VALUES (?, ?)")  )
  assert_number( stmt.bind_values(stmt, 4, "Good morning") )
  assert_number( stmt.step(stmt) )
  assert_number( stmt.reset(stmt) )
  self:check_content{ "Hello World", "Hello Lua", "Hello sqlite3", "Good morning" }
  assert_number( stmt.bind_values(stmt, 5, "Foo Bar") )
  assert_number( stmt.step(stmt) )
  assert_number( stmt.reset(stmt) )
  self:check_content{ "Hello World", "Hello Lua", "Hello sqlite3", "Good morning", "Foo Bar" }
  assert_number( stmt.finalize(stmt) )
end

--[===[
function st.test_questionmark_multi(st)
 stmt = assert_userdata( self.db.prepare(db, [[
    INSERT INTO test VALUES (?, ?); INSERT INTO test VALUES (?, ?) ]]))
  assert( stmt.bind_values(stmt, 5, "Foo Bar", 4, "Good morning") )
  assert_number( stmt.step(stmt) )
  assert_number( stmt.reset(stmt) )
  self:check_content{ "Hello World", "Hello Lua", "Hello sqlite3", "Good morning", "Foo Bar" }
  assert_number( stmt.finalize(stmt) )
end
]===]

function st.test_identifiers(st)
 stmt = assert_userdata( self.db.prepare(db, "INSERT INTO test VALUES (:id, :name)")  )
  assert_number( stmt.bind_values(stmt, 4, "Good morning") )
  assert_number( stmt.step(stmt) )
  assert_number( stmt.reset(stmt) )
  self:check_content{ "Hello World", "Hello Lua", "Hello sqlite3", "Good morning" }
  assert_number( stmt.bind_values(stmt, 5, "Foo Bar") )
  assert_number( stmt.step(stmt) )
  assert_number( stmt.reset(stmt) )
  self:check_content{ "Hello World", "Hello Lua", "Hello sqlite3", "Good morning", "Foo Bar" }
  assert_number( stmt.finalize(stmt) )
end

--[===[
function st.test_identifiers_multi(st)
 stmt = assert_table( self.db.prepare(db, [[
    INSERT INTO test VALUES (:id1, :name1); INSERT INTO test VALUES (:id2, :name2) ]]))
  assert( stmt.bind_values(stmt, 5, "Foo Bar", 4, "Good morning") )
  assert( stmt.exec(stmt) )
  self:check_content{ "Hello World", "Hello Lua", "Hello sqlite3", "Good morning", "Foo Bar" }
end
]===]

function st.test_identifiers_names(st)
  --local stmt = assert_userdata( self.db.prepare(db, {"name", "id"}, "INSERT INTO test VALUES (:id, $name)")  )
 stmt = assert_userdata( self.db.prepare(db, "INSERT INTO test VALUES (:id, $name)")  )
  assert_number( stmt.bind_names(stmt, {name="Good morning", id=4}) )
  assert_number( stmt.step(stmt) )
  assert_number( stmt.reset(stmt) )
  self:check_content{ "Hello World", "Hello Lua", "Hello sqlite3", "Good morning" }
  assert_number( stmt.bind_names(stmt, {name="Foo Bar", id=5}) )
  assert_number( stmt.step(stmt) )
  assert_number( stmt.reset(stmt) )
  self:check_content{ "Hello World", "Hello Lua", "Hello sqlite3", "Good morning", "Foo Bar" }
  assert_number( stmt.finalize(stmt) )
end

--[===[
function st.test_identifiers_multi_names(st)
 stmt = assert_table( self.db.prepare(db,  {"name", "id1", "id2"},[[
    INSERT INTO test VALUES (:id1, $name); INSERT INTO test VALUES ($id2, :name) ]]))
  assert( stmt.bind_values(stmt, "Hoho", 4, 5) )
  assert( stmt.exec(stmt) )
  self:check_content{ "Hello World", "Hello Lua", "Hello sqlite3", "Hoho", "Hoho" }
end
]===]

function st.test_colon_identifiers_names(st)
 stmt = assert_userdata( self.db.prepare(db, "INSERT INTO test VALUES (:id, :name)")  )
  assert_number( stmt.bind_names(stmt, {name="Good morning", id=4}) )
  assert_number( stmt.step(stmt) )
  assert_number( stmt.reset(stmt) )
  self:check_content{ "Hello World", "Hello Lua", "Hello sqlite3", "Good morning" }
  assert_number( stmt.bind_names(stmt, {name="Foo Bar", id=5}) )
  assert_number( stmt.step(stmt) )
  assert_number( stmt.reset(stmt) )
  self:check_content{ "Hello World", "Hello Lua", "Hello sqlite3", "Good morning", "Foo Bar" }
  assert_number( stmt.finalize(stmt) )
end

--[===[
function st.test_colon_identifiers_multi_names(st)
 stmt = assert_table( self.db.prepare(db,  {":name", ":id1", ":id2"},[[
    INSERT INTO test VALUES (:id1, $name); INSERT INTO test VALUES ($id2, :name) ]]))
  assert( stmt.bind_values(stmt, "Hoho", 4, 5) )
  assert( stmt.exec(stmt) )
  self:check_content{ "Hello World", "Hello Lua", "Hello sqlite3", "Hoho", "Hoho" }
end


function st.test_dollar_identifiers_names(st)
 stmt = assert_table( self.db.prepare(db, {"$name", "$id"}, "INSERT INTO test VALUES (:id, $name)")  )
  assert_table( stmt.bind_values(stmt, "Good morning", 4) )
  assert_table( stmt.exec(stmt) )
  self:check_content{ "Hello World", "Hello Lua", "Hello sqlite3", "Good morning" }
  assert_table( stmt.bind_values(stmt, "Foo Bar", 5) )
  assert_table( stmt.exec(stmt) )
  self:check_content{ "Hello World", "Hello Lua", "Hello sqlite3", "Good morning", "Foo Bar" }
end

function st.test_dollar_identifiers_multi_names(st)
 stmt = assert_table( self.db.prepare(db,  {"$name", "$id1", "$id2"},[[
    INSERT INTO test VALUES (:id1, $name); INSERT INTO test VALUES ($id2, :name) ]]))
  assert( stmt.bind_values(stmt, "Hoho", 4, 5) )
  assert( stmt.exec(stmt) )
  self:check_content{ "Hello World", "Hello Lua", "Hello sqlite3", "Hoho", "Hoho" }
end
]===]

function st.test_bind_by_names(st)
 stmt = assert_userdata( self.db.prepare(db, "INSERT INTO test VALUES (:id, :name)")  )
 args = { }
  args.id = 5
  args.name = "Hello girls"
  assert( stmt.bind_names(stmt, args) )
  assert_number( stmt.step(stmt) )
  assert_number( stmt.reset(stmt) )
  args.id = 4
  args.name = "Hello boys"
  assert( stmt.bind_names(stmt, args) )
  assert_number( stmt.step(stmt) )
  assert_number( stmt.reset(stmt) )
  self:check_content{ "Hello World", "Hello Lua", "Hello sqlite3",  "Hello boys", "Hello girls" }
  assert_number( stmt.finalize(stmt) )
end



--------------------------------
-- Tests binding of arguments --
--------------------------------

b = lunit.TestCase("Binding Tests")

function b.setup(b)
  self.db = assert( sqlite3.open_memory() )
  assert_number( self.db.exec(db, "CREATE TABLE test (id, name, u, v, w, x, y, z)") )
end

function b.teardown(b)
  assert_number( self.db.close(db) )
end

function b.test_auto_parameter_names(b)
 stmt = assert_userdata( self.db.prepare(db, "INSERT INTO test VALUES(:a, $b, :a2, :b2, $a, :b, $a3, $b3)") )
 parameters = assert_number( stmt.bind_parameter_count(stmt) )
  assert_equal( 8, parameters )
  assert_equal( ":a", stmt.bind_parameter_name(stmt, 1) )
  assert_equal( "$b", stmt.bind_parameter_name(stmt, 2) )
  assert_equal( ":a2", stmt.bind_parameter_name(stmt, 3) )
  assert_equal( ":b2", stmt.bind_parameter_name(stmt, 4) )
  assert_equal( "$a", stmt.bind_parameter_name(stmt, 5) )
  assert_equal( ":b", stmt.bind_parameter_name(stmt, 6) )
  assert_equal( "$a3", stmt.bind_parameter_name(stmt, 7) )
  assert_equal( "$b3", stmt.bind_parameter_name(stmt, 8) )
end

function b.test_auto_parameter_names(b)
 stmt = assert_userdata( self.db.prepare(db, "INSERT INTO test VALUES($a, $b, $a2, $b2, $a, $b, $a3, $b3)") )
 parameters = assert_number( stmt.bind_parameter_count(stmt) )
  assert_equal( 6, parameters )
  assert_equal( "$a", stmt.bind_parameter_name(stmt, 1) )
  assert_equal( "$b", stmt.bind_parameter_name(stmt, 2) )
  assert_equal( "$a2", stmt.bind_parameter_name(stmt, 3) )
  assert_equal( "$b2", stmt.bind_parameter_name(stmt, 4) )
  assert_equal( "$a3", stmt.bind_parameter_name(stmt, 5) )
  assert_equal( "$b3", stmt.bind_parameter_name(stmt, 6) )
end

function b.test_no_parameter_names_1(b)
 stmt = assert_userdata( self.db.prepare(db, [[ SELECT * FROM test ]]))
 parameters = assert_number( stmt.bind_parameter_count(stmt) )
  assert_equal( 0, (parameters) )
end

function b.test_no_parameter_names_2(b)
 stmt = assert_userdata( self.db.prepare(db, [[ INSERT INTO test VALUES(?, ?, ?, ?, ?, ?, ?, ?) ]]))
 parameters = assert_number( stmt.bind_parameter_count(stmt) )
  assert_equal( 8, (parameters) )
  assert_nil( stmt.bind_parameter_name(stmt, 1) )
end







--------------------------------------------
-- Tests loop break and statement reusage --
--------------------------------------------



----------------------------
-- Test for bugs reported --
----------------------------

bug = lunit.TestCase("Bug-Report Tests")

function bug.setup(bug)
  self.db = assert( sqlite3.open_memory() )
end

function bug.teardown(bug)
  assert_number( self.db.close(db) )
end

--[===[
function bug.test_1(bug)
  self.db.exec(db, "CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)")
  
 query = assert_userdata( self.db.prepare(db, "SELECT id FROM test WHERE value=?") )
  
  assert_table ( query.bind_values(query, "1") )
  assert_nil   ( query.first_cols(query) )
  assert_table ( query.bind_values(query, "2") )
  assert_nil   ( query.first_cols(query) )
end
]===]

function bug.test_nils(bug)   -- appeared in lua-5.1 (holes in arrays)
 function check(arg1, arg2, arg3, arg4, arg5)
    assert_equal(1, arg1)
    assert_equal(2, arg2)
    assert_nil(arg3)
    assert_equal(4, arg4)
    assert_nil(arg5)
  end
  
  self.db.create_function(db, "test_nils", 5, function(arg1, arg2, arg3, arg4, arg5)
    check(arg1, arg2, arg3, arg4, arg5)
  end, {})
  
  assert_number( self.db.exec(db, [[ SELECT test_nils(1, 2, NULL, 4, NULL) ]]) )
  
  for arg1, arg2, arg3, arg4, arg5 in self.db.urows(db, [[ SELECT 1, 2, NULL, 4, NULL ]])
  do check(arg1, arg2, arg3, arg4, arg5) 
  end
  
  for row in self.db.rows(db, [[ SELECT 1, 2, NULL, 4, NULL ]])
  do assert_table( row ) 
     check(row[1], row[2], row[3], row[4], row[5])
  end
end

----------------------------
-- Test for collation fun --
----------------------------

colla = lunit.TestCase("Collation Tests")

function colla.setup(colla)
   function collate(s1,s2)
        -- if p then print("collation callback: ",s1,s2) end
        s1=s1.lower(s1)
        s2=s2.lower(s2)
        if s1==s2 then return 0
        elseif s1<s2 then return -1
        else return 1 end
    end
    self.db = assert( sqlite3.open_memory() )
    assert_nil(self.db.create_collation(db, 'CINSENS',collate))
    self.db:exec[[
      CREATE TABLE test(id INTEGER PRIMARY KEY,content COLLATE CINSENS);
      INSERT INTO test VALUES(NULL,'hello world');
      INSERT INTO test VALUES(NULL,'Buenos dias');
      INSERT INTO test VALUES(NULL,'HELLO WORLD');
      INSERT INTO test VALUES(NULL,'Guten Tag');
      INSERT INTO test VALUES(NULL,'HeLlO WoRlD');
      INSERT INTO test VALUES(NULL,'Bye for now');
    ]]
end

function colla.teardown(colla)
  assert_number( self.db.close(db) )
end

function colla.test(colla)
    --for row in db.nrows(db, 'SELECT * FROM test') do
    --  print(row.id,row.content)
    --end
   n = 0
    for row in self.db.nrows(db, 'SELECT * FROM test WHERE content="hElLo wOrLd"') do
      -- print(row.id,row.content)
      assert_equal (row.content.lower(content), "hello world")
      n = n + 1
    end
    assert_equal (n, 3)
end

lunit.run()
