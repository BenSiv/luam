-- os.exit(true|false) accepts a boolean alongside the classic integer
-- status code. Needs a subprocess since os.exit terminates this process too.

status_true = os.execute("bin/luam -e 'os.exit(true)'")
assert(status_true == 0,
       "os.exit(true) should exit with status 0, got " .. tostring(status_true))

status_false = os.execute("bin/luam -e 'os.exit(false)'")
assert(status_false != 0,
       "os.exit(false) should exit with a nonzero status, got " ..
       tostring(status_false))

print("PASS os.exit(boolean) check")
