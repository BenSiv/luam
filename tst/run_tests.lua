
-- Test Runner
-- Test Runner
tests = {
    "bisect.lua", "cf.lua", "echo.lua", "env.lua", "factorial.lua",
    "fib.lua", "fibfor.lua", "hello.lua", "life.lua", "printf.lua",
    "readonly.lua", "sieve.lua", "sort.lua", "trace-calls.lua",
    "xd.lua", "local_default.lua", "ne_test.lua",
    "verify_multi.lua", "new_syntax.lua", "immutable.lua", "load_test.lua",
    "hex_test.lua"
}

mutable failed = 0
mutable passed = 0

print("Running tests...")

for _, test in ipairs(tests) do
    mutable cmd = "bld/lua tst/" .. test
    -- Some tests might need input or args, skipping complex ones for now or adding dummy input
    if test == "echo.lua" then cmd = cmd .. " arg1 arg2" end
    -- For tests that read stdin, we might pipe empty string or echo
    if test == "table.lua" or test == "globals.lua" or test == "trace-globals.lua" or test == "xd.lua" then
       -- table.lua reads from stdin, skipping for automated runner if complex
       -- But user said "run them all". Let's try basic run or skip interactive ones.
       -- For xd.lua, we can pass this file itself
       if test == "xd.lua" then cmd = cmd .. " < tst/xd.lua" end
    end
    
    -- Life and sieve might run forever.
    -- Sieve runs 1000 by default but loop at end picks numbers.
    -- Sieve line 24: while 1 do ... n=x() if n==nil break ... end
    -- The generator is finite if we restrict it?
    -- gen(N) creates finite loop? "for i=2,n". Yes.
    -- So sieve should terminate.
    
    -- life.lua: "run until break". It has while(1) or similar.
    -- We can skip infinite loops or run with timeout (hard in pure lua without library).
    -- I'll exclude proper infinite loops from defaults.
    if test == "life.lua" then
       print("SKIPPING " .. test .. " (infinite loop)")
    else
        exit_code = os.execute(cmd .. " > /dev/null")
        if exit_code == 0 then
            print("PASS " .. test)
            passed = passed + 1
        else
            print("FAIL " .. test)
            failed = failed + 1
        end
    end
end

print(string.format("\nPassed: %d, Failed: %d", passed, failed))

if failed > 0 then os.exit(1) end
