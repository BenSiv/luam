
-- est unner

-- Set package path to include libraries
package.path = "lib/?.lua;lib/socket/src/?.lua;" .. package.path
-- bin/?.so added: sqlite3.so is built specially (statically linked
-- against the vendored amalgamation, via src/Makefile's own linux:
-- target -- see bld/build_libs.sh's own comment on why sqlite has a
-- second, "secondary/unused" dynamic-link path there), landing in bin/
-- not lib/. Without this, require("database") -- which unconditionally
-- requires sqlite3 at its own top level -- fails outright under this
-- runner, which is why test_database.lua was never in the tests list
-- below despite existing in this directory.
package.cpath = "lib/?.so;lib/?/?.so;lib/lfs/?.so;lib/socket/?.so;bld/?.so;bin/?.so;" .. package.cpath
tests = {
    "test_bisect.lua", "test_cf.lua", "test_echo.lua", "test_factorial.lua",
    "test_fibfor.lua", "test_hello.lua", "test_printf.lua",
    "test_sieve.lua", "test_sort.lua", "test_trace_calls.lua",
    "test_xd.lua", "test_local_default.lua", "test_expired_local.lua", "test_ne.lua",
    "test_verify_multi.lua", "test_multiassign_register.lua",
    "test_no_sugar.lua", "test_load.lua",
    "test_hex.lua",
    "test_const.lua", "test_repeat_removed.lua",
    "test_module_newproxy_removed.lua", "test_os_exit_boolean.lua",
    "test_global_escape_hatch.lua", "test_strict_conditionals.lua",
    "test_getfenv_setfenv.lua",
    "test_require_isolation.lua",
    -- New/Renamed tests
    "test_bit.lua", "test_comment.lua", "test_env.lua",
    "test_feature_check.lua", "test_fix_strings.lua",
    "test_gmatch.lua", "test_gsub.lua", "test_hello_static.lua",
    "test_hex_legacy.lua", "test_indented.lua",
    "test_port_lanes.lua", "test_port_project.lua",
    "test_readonly.lua", "test_simple_sqlite.lua",
    "test_string_debug.lua", "test_table_ext.lua",
    -- Library tests (some disabled due to missing dependencies)
    "test_delimited_files.lua",
    "test_pure_io.lua",
    "test_utils.lua",
    "test_dataframes.lua",
    "test_argparse.lua",
    "test_lfs.lua", 
    "test_socket.lua",
    "test_sqlite.lua",
    "test_database.lua",
    "test_mariadb.lua",
    "test_mariadb_wrapper.lua",
    "test_struct.lua",
    "test_string_utils.lua",
}

failed = 0
passed = 0

print("Running tests")

for _, test in ipairs(tests) do
    -- lib/?/?.so added so subdirectory-packaged bindings (lib/bcrypt/
    -- bcrypt.so, lib/hmac/hmac.so, lib/mariadb/mariadb.so) resolve via
    -- require() here regardless of whatever LUA_CPATH this script
    -- happens to inherit from its own caller's environment. bin/?.so
    -- added so require("database") (which unconditionally requires
    -- sqlite3, only ever built to bin/sqlite3.so, not lib/) doesn't
    -- fail outright under this subprocess's own explicit env either --
    -- see this file's top-level package.cpath comment for the full story.
    cmd = "LUA_PATH='lib/?.lua;lib/socket/src/?.lua;;' LUA_CPATH='lib/?.so;lib/?/?.so;lib/lfs/?.so;lib/socket/?.so;bld/?.so;bin/?.so;;' LU_PH='lib/?.lua;lib/socket/src/?.lua;;' LU_CPH='lib/?.so;lib/lfs/?.so;lib/socket/?.so;bld/?.so;;' bin/luam tst/" .. test
    -- Some tests might need input or args, skipping complex ones for now or adding dummy input
    if test == "test_echo.lua" then cmd = cmd .. " arg1 arg2" end
    if test == "test_port_project.lua" then cmd = cmd .. " tst/test_port_project.lua" end
    -- For tests that read stdin, we might pipe empty string or echo
    if test == "table.lua" or test == "globals.lua" or test == "trace-globals.lua" or test == "test_xd.lua" then
       -- table.lua reads from stdin, skipping for automated runner if complex
       -- But user said "run them all". Let's try basic run or skip interactive ones.
       -- For xd.lua, we can pass this file itself
       if test == "test_xd.lua" then cmd = cmd .. " < tst/test_xd.lua" end
    end
    
    -- Life and sieve might run forever.
    -- Sieve runs 1000 by default but loop at end picks numbers.
    -- Sieve line 24: while 1 do ... n=x() if n==nil break ... end
    -- he generator is finite if we restrict it?
    -- gen() creates finite loop? "for i=2,n". es.
    -- So sieve should terminate.
    
    -- life.lua: "run until break". t has while(1) or similar.
    -- We can skip infinite loops or run with timeout (hard in pure lua without library).
    -- 'll exclude proper infinite loops from defaults.

    exit_code = os.execute(cmd .. " > /dev/null")
    if exit_code == 0 then
        print("PASS " .. test)
        passed = passed + 1
    else
        print("FAIL " .. test)
        failed = failed + 1
    end

end

-- REPL-mode regression check: bare assignment must persist as a real
-- global across separate lines fed to dotty() (the REPL), not as an
-- implicit local scoped to a single chunk. This can't be run the same way
-- as the tests above -- passing a script filename always takes the
-- non-interactive (implicit-local) path; dotty() only starts when luam
-- gets no script argument at all. So this pipes input directly into luam
-- with no script argument via a heredoc, instead of appending to `tests`.
repl_cmd = """bin/luam > /dev/null 2>&1 <<'REPLEOF'
x = 5
if x != 5 then os.exit(1) end
os.exit(0)
REPLEOF
"""
if os.execute(repl_cmd) == 0 then
    print("PASS test_repl_persistence")
    passed = passed + 1
else
    print("FAIL test_repl_persistence")
    failed = failed + 1
end

print(string.format("\nPassed: %d, Failed: %d", passed, failed))

if failed > 0 then os.exit(1) end
