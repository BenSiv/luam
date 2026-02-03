
-- est unner

-- Set package path to include libraries
package.path = "lib/?.lua;lib/socket/src/?.lua;" .. package.path
package.cpath = "lib/?.so;lib/lfs/?.so;lib/socket/?.so;bld/?.so;" .. package.cpath
tests = {
    "test_bisect.lua", "test_cf.lua", "test_echo.lua", "test_factorial.lua",
    "test_fibfor.lua", "test_hello.lua", "test_printf.lua",
    "test_sieve.lua", "test_sort.lua", "test_trace_calls.lua",
    "test_xd.lua", "test_local_default.lua", "test_ne.lua",
    "test_verify_multi.lua", "test_no_sugar.lua", "test_load.lua",
    "test_hex.lua",
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
    "test_struct.lua",
}

failed = 0
passed = 0

print("Running tests")

for _, test in ipairs(tests) do
    cmd = "LUA_PATH='lib/?.lua;lib/socket/src/?.lua;;' LUA_CPATH='lib/?.so;lib/lfs/?.so;lib/socket/?.so;bld/?.so;;' LU_PH='lib/?.lua;lib/socket/src/?.lua;;' LU_CPH='lib/?.so;lib/lfs/?.so;lib/socket/?.so;bld/?.so;;' bin/luam tst/" .. test
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

print(string.format("\nPassed: %d, Failed: %d", passed, failed))

if failed > 0 then os.exit(1) end
