-- tst/run_all.lua
-- Luam Test Runner

print("DEBUG: Script started")

ok, lfs_mod = pcall(require, "lfs")
if not ok then
    lfs = nil
else
    lfs = lfs_mod
end

results = {
    passed = {},
    failed = {}
}

function get_test_files(dir, file_list)
    file_list = file_list or {}
    if lfs == nil then return file_list end
    for entry in lfs.dir(dir) do
        if entry != "." and entry != ".." then
            path = dir .. "/" .. entry
            attr = lfs.attributes(path)
            if attr.mode == "directory" then
                get_test_files(path, file_list)
            elseif (string.match(entry, "%.lua$") != nil) and entry != "run_all.lua" then
                table.insert(file_list, path)
            end
        end
    end
    return file_list
end

-- ... error_handler and run_test ...

function error_handler(err)
    return {
        message = err,
        traceback = debug.traceback("", 2)
    }
end

function run_test(path)
    io.write("Testing: " .. path .. " ... ")
    io.flush()
    
    -- Load the chunk
    chunk, load_err = loadfile(path)
    if chunk == nil then
        table.insert(results.failed, {
            path = path,
            message = "Load error: " .. (load_err or "unknown"),
            traceback = ""
        })
        print("[FAIL] (Load error: " .. tostring(load_err) .. ")")
        return
    end

    -- Run the chunk
    -- We can provide a clean environment if needed, but for now sharing global _G
    status_success, err_obj = xpcall(chunk, error_handler)
    
    if status_success == true then
        table.insert(results.passed, path)
        print("[PASS]")
    else
        table.insert(results.failed, {path = path, err = err_obj})
        print("[FAIL]")
        if type(err_obj) == "table" then
            print("  Error: " .. tostring(err_obj.message))
            print("  Traceback: " .. tostring(err_obj.traceback))
        else
            print("  Error: " .. tostring(err_obj))
        end
    end
end

-- Main Execution

all_tests = {}

if #arg > 0 then

   print("DEBUG: arg table has " .. #arg .. " elements.")
   -- Use provided args
   for i=1, #arg do
       path = arg[i]
       print("DEBUG: processing arg[" .. i .. "] = " .. tostring(path))
       if string.match(path, "_test.lua$") != nil or string.match(path, "test_.*%.lua$") != nil then
           table.insert(all_tests, path)
       end
   end
else
   if lfs == nil then
       print("Error: 'lfs' not found and no test files provided via arguments.")
       os.exit(1)
   end
   test_root = "tst/unit"
   print("DEBUG: scanning " .. test_root)
   all_tests = get_test_files(test_root)
   print("\nFound " .. #all_tests .. " tests in " .. test_root .. " using lfs\n")
end

print("\n--- Luam Test Suite ---")
print("Running " .. #all_tests .. " tests\n")

table.sort(all_tests)

for i=1, #all_tests do
    test_path = all_tests[i]
    run_test(test_path)
end

print("\n--- Summary ---")
print("Total:  " .. #all_tests)
print("Passed: " .. #results.passed)
print("Failed: " .. #results.failed)

if #results.failed > 0 then
    print("\n--- Failures ---")
    for _, f in ipairs(results.failed) do
        print("\nFILE: " .. f.path)
        print("ERROR: " .. tostring(f.message))
        print("TRACEBACK:")
        print(f.traceback)
    end
    print("\nTests FAILED.")
    os.exit(1)
else
    print("\nAll tests PASSED.")
    os.exit(0)
end
