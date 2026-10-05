-- Opt-in SQLite connection reuse in database_adapter: off by default,
-- one cached connection when on, and a failed multi-statement script
-- rolled back so later writes on the kept-open connection still commit.
d = require("database_adapter")
p = "test_keep_open.sqlite"
os.remove(p)
-- default: no cache
d.sqlite_update(p, "CREATE TABLE t (x INTEGER);")
assert(d.sqlite_connection_count() == 0, "no cache by default")
-- keep open
d.sqlite_keep_open(true)
d.sqlite_update(p, "INSERT INTO t VALUES (1);")
rows = d.sqlite_query(p, "SELECT count(*) AS n FROM t;")
assert(d.sqlite_connection_count() == 1, "one cached connection")
assert(tonumber(rows[1].n) == 1)
-- failed script mid-transaction must not swallow later writes
ok = pcall(d.sqlite_update, p, "BEGIN TRANSACTION; INSERT INTO t VALUES (2); INSERT INTO nope VALUES (3); COMMIT;")
assert(ok == false, "script should fail")
d.sqlite_update(p, "INSERT INTO t VALUES (4);")
d.sqlite_close_all()
assert(d.sqlite_connection_count() == 0)
d.sqlite_keep_open(false)
rows = d.sqlite_query(p, "SELECT group_concat(x) AS xs FROM t;")
print("rows:", rows[1].xs)
assert(rows[1].xs == "1,4", "rolled back 2, kept 4; got " .. tostring(rows[1].xs))
-- bad query on cached conn still errors cleanly
d.sqlite_keep_open(true)
assert(pcall(d.sqlite_query, p, "SELECT * FROM nope;") == false)
assert(d.sqlite_query(p, "SELECT 1 AS one;")[1].one == 1)
d.sqlite_close_all()
os.remove(p)
os.remove(p .. "-wal")
os.remove(p .. "-shm")
print("database_adapter keep_open: ok")
