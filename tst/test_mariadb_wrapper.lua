
print("Testing database.lua's mariadb_* wrapper (persistent connections)...")

-- Same skip-not-fail gating as tst/test_mariadb.lua -- see that file's
-- own header comment for why. database module itself always loads
-- (mariadb_native is lazy inside it, see database.lua's own comment),
-- so this only needs to pcall-gate the actual mariadb_update call.
-- The mariadb_* wrapper lives in database_adapter (database.lua's
-- query/exec dispatch to it). This test used to call it through
-- database.lua, where those names no longer exist, so the pcall guard
-- below read the missing function as "no server" and skipped silently.
database = require("database_adapter")
quote = require("database").quote

host = os.getenv("MARIADB_TEST_HOST")
if host == nil then host = "127.0.0.1" end
port = tonumber(os.getenv("MARIADB_TEST_PORT"))
if port == nil then port = 3306 end
user = os.getenv("MARIADB_TEST_USER")
if user == nil then user = "luam_test" end
password = os.getenv("MARIADB_TEST_PASSWORD")
if password == nil then password = "luam_test_pw" end
database_name = os.getenv("MARIADB_TEST_DATABASE")
if database_name == nil then database_name = "luam_test" end

descriptor = {host = host, port = port, user = user, password = password, database = database_name}

ok, err = pcall(function() return database.mariadb_update(descriptor, "SELECT 1;") end)
if not ok then
    print("Skipping mariadb wrapper tests (no reachable test server / module: " .. tostring(err) .. ")")
    os.exit(0)
end

database.mariadb_update(descriptor, "DROP TABLE IF EXISTS luam_mariadb_wrapper_test;")
database.mariadb_update(descriptor, "CREATE TABLE luam_mariadb_wrapper_test (id INT PRIMARY KEY AUTO_INCREMENT, val TEXT);")

-- %s-style interpolation with auto-escaped string varargs -- same
-- calling convention as sqlite_update's sqlite path, confirming a
-- dangerous value is escaped, not just concatenated raw.
affected, insert_id = database.mariadb_update(
    descriptor, "INSERT INTO luam_mariadb_wrapper_test (val) VALUES ('%s');", "O'Brien"
)
assert(affected == 1, "expected 1 affected row")
assert(insert_id > 0, "expected a positive insert_id")

rows, column_names = database.mariadb_query(descriptor, "SELECT * FROM luam_mariadb_wrapper_test;")
assert(rows != nil, "expected rows back")
assert(#rows == 1, "expected 1 row")
assert(rows[1].val == "O'Brien", "escaped value round-trip mismatch: " .. tostring(rows[1].val))
assert(column_names != nil and #column_names == 2 and column_names[1] == "id" and column_names[2] == "val",
    "expected ordered column_names {'id', 'val'}")

-- NULL in row 1 must NOT drop the column from column_names or hide row 2's value,
-- and 0-row SELECTs must still return ordered column_names (matching sqlite_query).
database.mariadb_update(descriptor, "DROP TABLE IF EXISTS luam_mariadb_null_cols;")
database.mariadb_update(descriptor, "CREATE TABLE luam_mariadb_null_cols (id INT PRIMARY KEY, z_col TEXT, a_col TEXT, m_col TEXT);")
database.mariadb_update(descriptor, "INSERT INTO luam_mariadb_null_cols (id, z_col, a_col, m_col) VALUES (1, NULL, 'first', NULL), (2, 'z2', 'second', 'm2');")

null_rows, null_cols = database.mariadb_query(descriptor, "SELECT z_col, a_col, m_col FROM luam_mariadb_null_cols ORDER BY id ASC;")
assert(null_rows != nil and #null_rows == 2, "expected 2 rows from null_cols table")
assert(#null_cols == 3 and null_cols[1] == "z_col" and null_cols[2] == "a_col" and null_cols[3] == "m_col",
    "expected exact SELECT column order even when row 1 has NULLs, got: " .. table.concat(null_cols, ","))
assert(null_rows[1].z_col == nil and null_rows[2].z_col == "z2" and null_rows[2].m_col == "m2",
    "expected NULL in row 1 and populated values in row 2")

zero_rows, zero_cols = database.mariadb_query(descriptor, "SELECT m_col, z_col, a_col FROM luam_mariadb_null_cols WHERE 1 = 0;")
assert(zero_rows == nil, "expected nil rows on 0-row mariadb_query (matching sqlite_query)")
assert(#zero_cols == 3 and zero_cols[1] == "m_col" and zero_cols[2] == "z_col" and zero_cols[3] == "a_col",
    "expected ordered column_names on 0-row mariadb_query, got: " .. table.concat(zero_cols, ","))
database.mariadb_update(descriptor, "DROP TABLE luam_mariadb_null_cols;")

-- Connection reuse: repeated calls must not grow the cache -- the
-- entire point of this wrapper existing over an open-per-call model.
count_before = database.mariadb_connection_count()
assert(count_before == 1, "expected exactly 1 cached connection, got " .. tostring(count_before))

for i = 1, 5 do
    database.mariadb_query(descriptor, "SELECT * FROM luam_mariadb_wrapper_test;")
end

count_after = database.mariadb_connection_count()
assert(count_after == 1, "expected connection count to stay at 1 after repeated calls, got " .. tostring(count_after))

-- Bad statement surfaces as a real Lua error (matches sqlite_update/
-- sqlite_query's own error() convention), not a silent nil.
ok3 = pcall(function() return database.mariadb_query(descriptor, "SELECT * FROM a_table_that_does_not_exist;") end)
assert(ok3 == false, "expected an error for a query against a nonexistent table")

-- database.quote only doubles single quotes; that is injection-safe
-- only because get_mariadb_connection forces NO_BACKSLASH_ESCAPES. A
-- value ending in a backslash would otherwise escape the doubled quote
-- and end the literal early. Round-trip one and check it comes back
-- byte for byte, and that the session really has the flag.
mode_rows = database.mariadb_query(descriptor, "SELECT @@SESSION.sql_mode AS sql_mode;")
assert(database.sql_mode_disables_backslash_escapes(mode_rows[1].sql_mode), "expected NO_BACKSLASH_ESCAPES in the session sql_mode")
tricky = "x\\' OR '1'='1"
database.mariadb_update(descriptor, "INSERT INTO luam_mariadb_wrapper_test (val) VALUES (" .. quote(tricky) .. ");")
back = database.mariadb_query(descriptor, "SELECT val FROM luam_mariadb_wrapper_test WHERE val = " .. quote(tricky) .. ";")
assert(back != nil and #back == 1 and back[1].val == tricky, "expected a backslash-quote value to round-trip unchanged")

-- Unified database.lua surface against MariaDB: normalized exec return,
-- query_params with '%' and '\'', transaction commit + rollback, with_lock,
-- and native EXP/LN/CHAR_LENGTH/GREATEST/DATEDIFF parity with SQLite UDFs.
db_mod = require("database")
ok_ex, ins_ex, aff_ex = db_mod.exec(descriptor, "INSERT INTO luam_mariadb_wrapper_test (val) VALUES ('norm');")
assert(ok_ex == true and ins_ex > 0 and aff_ex == 1, "expected normalized database.exec return on MariaDB")

param_val = "50% off \\' ? test"
db_mod.exec(descriptor, "INSERT INTO luam_mariadb_wrapper_test (val) VALUES (" .. quote(param_val) .. ");")
prows, perr = db_mod.query_params(descriptor,
    "SELECT id, val FROM luam_mariadb_wrapper_test WHERE val = ? AND '?' = '?';",
    {{type = "text", value = param_val}}
)
assert(prows != nil and #prows == 1 and prows[1].val == param_val,
    "database.query_params failed on MariaDB: " .. tostring(perr))

aborted_ok = db_mod.transaction(descriptor, function()
    db_mod.exec(descriptor, "INSERT INTO luam_mariadb_wrapper_test (val) VALUES ('tx_abort');")
    return false
end)
assert(aborted_ok == false, "expected soft transaction abort on MariaDB")
abort_rows = db_mod.query(descriptor, "SELECT * FROM luam_mariadb_wrapper_test WHERE val = 'tx_abort';")
assert(abort_rows == nil, "rolled-back MariaDB transaction row must not persist")

commit_res = db_mod.transaction(descriptor, function()
    db_mod.exec(descriptor, "INSERT INTO luam_mariadb_wrapper_test (val) VALUES ('tx_commit');")
    return "ok_mdb"
end)
assert(commit_res == "ok_mdb", "expected MariaDB transaction commit")
commit_rows = db_mod.query(descriptor, "SELECT * FROM luam_mariadb_wrapper_test WHERE val = 'tx_commit';")
assert(commit_rows != nil and #commit_rows == 1, "committed MariaDB transaction row must persist")

lock_val = db_mod.with_lock(descriptor, "luam_test_lock", 5, function()
    -- Re-entrant same-name lock on same store joins without round-trip deadlock
    nested_v = db_mod.with_lock(descriptor, "luam_test_lock", 0, function() return 88 end)
    assert(nested_v == 88, "nested MariaDB with_lock failed")
    return 77
end)
assert(lock_val == 77, "database.with_lock failed on MariaDB")

-- Contended GET_LOCK timeout (got == 0): a second raw connection holding
-- 'luam_contended_lock' must cause database.with_lock(..., 0, ...) to raise
-- rather than running unlocked, and must NOT release the holder's lock.
mariadb_native = require("mariadb")
holder_conn, holder_err = mariadb_native.connect(host, port, user, password, database_name)
assert(holder_conn != nil, "holder connect failed: " .. tostring(holder_err))
h_rows = mariadb_native.query(holder_conn, "SELECT GET_LOCK('luam_contended_lock', 5) AS got;")
assert(h_rows != nil and tonumber(h_rows[1].got) == 1, "holder failed to acquire GET_LOCK")

ran_unlocked = false
ok_contend, contend_err = pcall(db_mod.with_lock, descriptor, "luam_contended_lock", 0, function()
    ran_unlocked = true
    return "bad"
end)
assert(ok_contend == false and ran_unlocked == false, "expected with_lock to raise on GET_LOCK timeout rather than run unlocked")
assert(string.find(tostring(contend_err), "could not acquire database lock", 1, true) != nil,
    "unexpected lock timeout error: " .. tostring(contend_err))

still_held = mariadb_native.query(holder_conn, "SELECT IS_USED_LOCK('luam_contended_lock') = CONNECTION_ID() AS held;")
assert(still_held != nil and tonumber(still_held[1].held) == 1, "timed-out waiter must not disturb holder lock")
mariadb_native.query(holder_conn, "SELECT RELEASE_LOCK('luam_contended_lock');")
mariadb_native.close(holder_conn)

-- Pinned session protection: killing the server-side session mid-transaction
-- must raise an error rather than transparently reconnecting into autocommit.
killer_conn = mariadb_native.connect(host, port, user, password, database_name)
assert(killer_conn != nil, "killer connect failed")
leaked_after_kill = false
ok_kill_tx, kill_tx_err = pcall(db_mod.transaction, descriptor, function()
    db_mod.exec(descriptor, "INSERT INTO luam_mariadb_wrapper_test (val) VALUES ('before_kill');")
    target_id = db_mod.connection_id(descriptor)
    mariadb_native.exec(killer_conn, "KILL " .. tostring(target_id) .. ";")
    db_mod.exec(descriptor, "INSERT INTO luam_mariadb_wrapper_test (val) VALUES ('after_kill_must_not_autocommit');")
    leaked_after_kill = true
end)
mariadb_native.close(killer_conn)
assert(ok_kill_tx == false and leaked_after_kill == false,
    "expected killed MariaDB session inside transaction to fail instead of reconnecting into autocommit")
after_kill_rows = db_mod.query(descriptor,
    "SELECT * FROM luam_mariadb_wrapper_test WHERE val IN ('before_kill', 'after_kill_must_not_autocommit');")
assert(after_kill_rows == nil, "neither pre-kill uncommitted row nor post-kill statement may persist")

fn_rows = db_mod.query(descriptor,
    "SELECT EXP(1.0) AS e1, LN(EXP(2.5)) AS l25, CHAR_LENGTH('שלום') AS ulen, GREATEST(2, 9, 4) AS g, DATEDIFF('2024-03-01', '2024-02-01') AS dd;"
)
assert(math.abs(tonumber(fn_rows[1].e1) - math.exp(1.0)) < 1e-6, "MariaDB EXP mismatch")
assert(math.abs(tonumber(fn_rows[1].l25) - 2.5) < 1e-6, "MariaDB LN mismatch")
assert(tonumber(fn_rows[1].ulen) == 4 and tonumber(fn_rows[1].g) == 9 and tonumber(fn_rows[1].dd) == 29,
    "MariaDB CHAR_LENGTH/GREATEST/DATEDIFF parity mismatch")

database.mariadb_update(descriptor, "DROP TABLE luam_mariadb_wrapper_test;")
database.mariadb_close_all()

count_final = database.mariadb_connection_count()
assert(count_final == 0, "expected mariadb_close_all() to empty the connection cache")

print("database.lua mariadb_* wrapper tests passed")
