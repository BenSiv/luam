-- Luam test runner

package.path = "lib/?.lua;lib/?/init.lua;" .. package.path
package.cpath = "lib/?.so;lib/?/?.so;bin/?.so;" .. package.cpath

tests = {
    "test_bisect.lua", "test_cf.lua", "test_echo.lua", "test_factorial.lua",
    "test_fibfor.lua", "test_hello.lua", "test_printf.lua",
    "test_sieve.lua", "test_sort.lua", "test_trace_calls.lua",
    "test_xd.lua", "test_local_default.lua", "test_expired_local.lua", "test_ne.lua",
    "test_verify_multi.lua", "test_multiassign_register.lua",
    "test_no_sugar.lua", "test_load.lua",
    "test_hex.lua", "test_dkjson_keys.lua", "test_json.lua",
    "test_const.lua", "test_repeat_removed.lua",
    "test_module_newproxy_removed.lua", "test_os_exit_boolean.lua",
    "test_global_escape_hatch.lua", "test_strict_conditionals.lua",
    "test_getfenv_setfenv.lua",
    "test_table_order.lua",
    "test_bit.lua", "test_comment.lua", "test_env.lua",
    "test_feature_check.lua", "test_fix_strings.lua",
    "test_gmatch.lua", "test_gsub.lua", "test_hello_static.lua",
    "test_hex_legacy.lua", "test_indented.lua",
    "test_port_project.lua",
    "test_readonly.lua", "test_simple_sqlite.lua", "test_sqlite_names.lua",
    "test_string_debug.lua", "test_table_ext.lua",
    "test_delimited_files.lua",
    "test_pure_io.lua",
    "test_dataframes.lua",
    "test_dates.lua",
    "test_graphs.lua",
    "test_yaml.lua",
    "test_lfs.lua",
    "test_sqlite.lua",
    "test_integrity.lua",
    "test_database.lua", "test_database_keep_open.lua",
    "test_mariadb.lua",
    "test_mariadb_wrapper.lua",
    "test_sql_mode_check.lua",
    "test_struct.lua",
    "test_strings_and_escapes.lua",
    "test_web_stack.lua",
    "test_asset.lua",
    "test_laws.lua",
    "test_phase1.lua",
    "test_phase2.lua",
    "test_security_hardening.lua",
    "test_stdlib_core.lua",
    "test_io_primitives.lua",
    "test_toolchain.lua",
}

failed = 0
passed = 0

print("Running tests")

for _, test in ipairs(tests) do
    cmd = "LUA_PATH='lib/?.lua;lib/?/init.lua;;' LUA_CPATH='lib/?.so;lib/?/?.so;bin/?.so;;' bin/luam tst/" .. test
    if test == "test_echo.lua" then
        cmd = cmd .. " arg1 arg2"
    end
    if test == "test_port_project.lua" then
        cmd = cmd .. " tst/test_port_project.lua"
    end
    if test == "test_xd.lua" then
        cmd = cmd .. " < tst/test_xd.lua"
    end

    if os.execute(cmd .. " > /dev/null") then
        print("PASS " .. test)
        passed = passed + 1
    else
        print("FAIL " .. test)
        failed = failed + 1
    end
end

-- REPL-mode regression check: bare assignment must persist as a real
-- global across separate lines fed to dotty() (the REPL), not as an
-- implicit local scoped to a single chunk.
repl_cmd = """bin/luam > /dev/null 2>&1 <<'REPLEOF'
x = 5
if x != 5 then os.exit(1) end
os.exit(0)
REPLEOF
"""
if os.execute(repl_cmd) then
    print("PASS test_repl_persistence")
    passed = passed + 1
else
    print("FAIL test_repl_persistence")
    failed = failed + 1
end

print(string.format("\nPassed: %d, Failed: %d", passed, failed))

if failed > 0 then
    os.exit(1)
end
