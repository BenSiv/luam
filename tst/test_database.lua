database_adapter = require("database_adapter")
database = require("database")

print("Testing database...")

function close_to(a, b, tol)
    if tol == nil then tol = 1e-9 end
    return math.abs(tonumber(a) - tonumber(b)) <= tol
end

ok, _ = pcall(require, "sqlite3")
if ok then
    tmp_db = os.tmpname()

    -- 1. Basic create + insert_id + unified affected_rows (Seam 2)
    database.exec(tmp_db, "CREATE TABLE test (id INTEGER PRIMARY KEY AUTOINCREMENT, val TEXT, score REAL);")

    ok2, insert_id, affected_ins = database_adapter.sqlite_update(tmp_db, "INSERT INTO test (val, score) VALUES ('foo', 1.5);")
    assert(ok2 == true, "expected sqlite_update to return true")
    assert(insert_id == 1, "expected insert_id == 1, got " .. tostring(insert_id))
    assert(affected_ins == 1, "expected 1 affected row on insert, got " .. tostring(affected_ins))

    ok_exec, id2, aff2 = database.exec(tmp_db, "INSERT INTO test (val, score) VALUES ('bar', 2.5);")
    assert(ok_exec == true and id2 == 2 and aff2 == 1, "expected normalized database.exec return (true, 2, 1)")

    _, _, aff_multi = database.exec(tmp_db, "UPDATE test SET score = score + 1.0;")
    assert(aff_multi == 2, "expected 2 affected rows on full-table update, got " .. tostring(aff_multi))

    _, _, aff_none = database.exec(tmp_db, "UPDATE test SET score = 0 WHERE id = 999;")
    assert(aff_none == 0, "expected 0 affected rows when WHERE matches nothing, got " .. tostring(aff_none))

    -- 2. Portable SQLite scalar UDFs matching MariaDB/MySQL (Seam 1)
    math_rows = database.query(tmp_db,
        "SELECT EXP(0.0) AS e0, EXP(1.0) AS e1, LN(EXP(2.5)) AS ln25, LOG10(1000) AS l10, " ..
        "POW(2, 10) AS p1, POWER(9, 0.5) AS p2, SQRT(49) AS sq, LN(-1) AS bad_ln, EXP(NULL) AS null_exp;"
    )
    mr = math_rows[1]
    assert(close_to(mr.e0, 1.0), "EXP(0) mismatch")
    assert(close_to(mr.e1, math.exp(1.0)), "EXP(1) mismatch")
    assert(close_to(mr.ln25, 2.5), "LN(EXP(2.5)) mismatch")
    assert(close_to(mr.l10, 3.0), "LOG10(1000) mismatch")
    assert(close_to(mr.p1, 1024.0) and close_to(mr.p2, 3.0) and close_to(mr.sq, 7.0), "POW/POWER/SQRT mismatch")
    assert(mr.bad_ln == "", "LN(-1) should be SQL NULL (filled as '' by sqlite_query)")
    assert(mr.null_exp == "", "EXP(NULL) should be SQL NULL")

    -- UTF-8 CHAR_LENGTH, GREATEST/LEAST, DATEDIFF
    str_rows = database.query(tmp_db,
        "SELECT CHAR_LENGTH('hello') AS ascii_len, CHARACTER_LENGTH('שלום') AS utf8_len, " ..
        "GREATEST(3, 19, -4, 7.5) AS g_num, LEAST(3, 19, -4, 7.5) AS l_num, " ..
        "GREATEST('beta', 'alpha', 'gamma') AS g_str, GREATEST(1, NULL, 5) AS g_null, " ..
        "DATEDIFF('2026-03-01 18:30:00', '2026-02-01 01:00:00') AS d_nonleap, " ..
        "DATEDIFF('2024-03-01', '2024-02-01') AS d_leap, " ..
        "DATEDIFF('2026-01-01', '2026-01-11') AS d_neg;"
    )
    sr = str_rows[1]
    assert(tonumber(sr.ascii_len) == 5, "CHAR_LENGTH('hello') != 5")
    assert(tonumber(sr.utf8_len) == 4, "CHARACTER_LENGTH('שלום') != 4, got " .. tostring(sr.utf8_len))
    assert(close_to(sr.g_num, 19.0) and close_to(sr.l_num, -4.0), "GREATEST/LEAST numeric mismatch")
    assert(sr.g_str == "gamma", "GREATEST string mismatch")
    assert(sr.g_null == "", "GREATEST with NULL arg must yield SQL NULL")
    assert(tonumber(sr.d_nonleap) == 28, "2026 Feb DATEDIFF expected 28, got " .. tostring(sr.d_nonleap))
    assert(tonumber(sr.d_leap) == 29, "2024 leap Feb DATEDIFF expected 29, got " .. tostring(sr.d_leap))
    assert(tonumber(sr.d_neg) == -10, "negative DATEDIFF expected -10, got " .. tostring(sr.d_neg))

    -- 3. Parameterized queries via database.query_params (Seam 3)
    tricky_text = "100% O'Brien ? \\' literal"
    database.exec(tmp_db, "INSERT INTO test (val, score) VALUES (" .. database.quote(tricky_text) .. ", 42.0);")
    prows, perr = database.query_params(tmp_db,
        "SELECT id, val FROM test WHERE val = ? AND '?' = '?' AND score > ?;",
        {{type = "text", value = tricky_text}, {type = "number", value = "40"}}
    )
    assert(prows != nil and #prows == 1 and prows[1].val == tricky_text,
        "query_params round-trip failed: " .. tostring(perr))

    empty_rows, eerr = database.query_params(tmp_db, "SELECT id FROM test WHERE id = ?;", {{type = "integer", value = 9999}})
    assert(empty_rows != nil and #empty_rows == 0 and eerr == nil, "query_params empty result should be {}")

    bad_rows, berr = database.query_params(tmp_db, "SELECT id FROM test WHERE id = ?;", {{type = "integer", value = "not-a-num"}})
    assert(bad_rows == nil and berr != nil, "query_params should reject non-numeric integer param")

    mismatch_rows, merr = database.query_params(tmp_db, "SELECT id FROM test WHERE id = ? AND score = ?;", {{type = "integer", value = 1}})
    assert(mismatch_rows == nil and merr != nil, "query_params should reject placeholder count mismatch")

    -- 4. Backend-agnostic re-entrant transactions (Seam 4)
    function tx_inner_body()
        database.exec(tmp_db, "INSERT INTO test (val, score) VALUES ('tx_inner', 20.0);")
        return "nested_ok"
    end
    function tx_outer_body()
        database.exec(tmp_db, "INSERT INTO test (val, score) VALUES ('tx_outer', 10.0);")
        nested = database.transaction(tmp_db, tx_inner_body)
        assert(nested == "nested_ok", "nested transaction return mismatch")
        return "committed"
    end
    tx_val = database.transaction(tmp_db, tx_outer_body)
    assert(tx_val == "committed", "outer transaction return mismatch")

    -- Explicit abort via `return false, reason` rolls back and preserves all return values
    function tx_soft_abort()
        database.exec(tmp_db, "INSERT INTO test (val, score) VALUES ('rolled_back_soft', 99.0);")
        return false, "validation_failed"
    end
    aborted, abort_detail = database.transaction(tmp_db, tx_soft_abort)
    assert(aborted == false and abort_detail == "validation_failed", "soft rollback return mismatch")

    -- Raising an error rolls back and re-raises
    function tx_raise_boom()
        database.exec(tmp_db, "INSERT INTO test (val, score) VALUES ('rolled_back_err', 99.0);")
        error("boom")
    end
    function run_raising_tx()
        database.transaction(tmp_db, tx_raise_boom)
    end
    ok_raise = pcall(run_raising_tx)
    assert(ok_raise == false, "expected raised transaction error to propagate")

    -- Nil first return value with non-nil second return value commits and preserves arity
    function tx_nil_first()
        return nil, "kept_second"
    end
    r_nil, r_meta = database.transaction(tmp_db, tx_nil_first)
    assert(r_nil == nil and r_meta == "kept_second", "pack_varargs must preserve trailing returns after nil")

    tx_check = database.query(tmp_db, "SELECT COUNT(*) AS n FROM test WHERE val LIKE 'rolled_back%';")
    assert(tonumber(tx_check[1].n) == 0, "rolled-back rows must not persist")
    tx_kept = database.query(tmp_db, "SELECT COUNT(*) AS n FROM test WHERE val IN ('tx_outer', 'tx_inner');")
    assert(tonumber(tx_kept[1].n) == 2, "committed nested transaction rows must persist")

    -- 5. Advisory with_lock & inode-aware cache_key (Seam 5)
    k1 = database.cache_key(tmp_db)
    function locked_return_123()
        return 123
    end
    lock_res = database.with_lock(tmp_db, "test_lock", 5, locked_return_123)
    assert(lock_res == 123 and type(k1) == "string" and string.find(k1, "sqlite:", 1, true) == 1, "with_lock/cache_key failed")

    os.remove(tmp_db)
else
    print("Skipping database functional tests (sqlite3 missing)")
end

print("database tests passed")
