-- Test Strict Conditionals
-- "if <non-boolean>" should be an error.

function assert_error(code, msg_pattern)
   f, e = loadstring(code)
   if is f then
      -- If compiled OK, run it to check runtime error
      status, err = pcall(f)
      if status then
         print("FAIL: Expected error for code: " .. code)
         os.exit(1)
      else
         if not is string.find(err, msg_pattern) then
             print("FAIL: Wrong runtime error for: " .. code)
             print("Got: " .. err)
             os.exit(1)
         end
      end
   else
      -- Compile time error
      if not is string.find(e, msg_pattern) then
          print("FAIL: Wrong compile error for: " .. code)
          print("Got: " .. e)
          os.exit(1)
      end
   end
   print("PASS: " .. code .. " -> Rejected as expected.")
end

function assert_ok(code)
   f, e = loadstring(code)
   if not is f then
       print("FAIL: Compile error for valid code: " .. code)
       print(e)
       os.exit(1)
   end
   status, err = pcall(f)
   if not status then
       print("FAIL: Runtime error for valid code: " .. code)
       print(err)
       os.exit(1)
   end
   print("PASS: " .. code .. " -> Accepted.")
end

print("=== Testing Strict Conditionals ===")

-- Literals
assert_error("if 5 then end", "conditional requires a boolean")
assert_error("if 'str' then end", "conditional requires a boolean")
assert_error("if nil then end", "nil is not a conditional value") -- caught by parser
assert_error("if {} then end", "conditional requires a boolean") 

-- Variables (Runtime)
assert_error("x=5; if x then end", "conditional requires a boolean")
assert_error("x='s'; if x then end", "conditional requires a boolean")
assert_error("x={}; if x then end", "conditional requires a boolean")
assert_error("x=nil; if x then end", "conditional requires a boolean") -- Runtime OP_TEST

-- Valid cases
assert_ok("if true then end")
assert_ok("if false then end")
assert_ok("x=true; if x then end")
assert_ok("x=false; if x then end")
assert_ok("if (5 == 5) then end")
assert_ok("x=5; if is x then end") -- 'is' operator returns boolean

-- While / Repeat
assert_error("while 5 do end", "conditional requires a boolean")
-- assert_error("repeat until 5", "conditional requires a boolean") 

print("\nALL TESTS PASSED")
