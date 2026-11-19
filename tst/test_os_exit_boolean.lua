-- os.exit(true|false) accepts a boolean alongside the classic integer
-- status code. Needs a subprocess since os.exit terminates this process too.

ok_true, why_true, code_true = os.execute("bin/luam -e \"os.exit(true)\"")
assert(ok_true == true and why_true == "exit" and code_true == 0,
       "os.exit(true) should exit with status 0, got " .. tostring(ok_true) .. "/" .. tostring(code_true))

ok_false, why_false, code_false = os.execute("bin/luam -e \"os.exit(false)\"")
assert(ok_false == false and why_false == "exit" and code_false != 0,
       "os.exit(false) should exit with a nonzero status, got " ..
       tostring(ok_false) .. "/" .. tostring(code_false))

print("PASS os.exit(boolean) check")
