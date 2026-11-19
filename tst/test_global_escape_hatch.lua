-- Bare assignment is local to the chunk that made it -- even for a
-- non-interactive one-liner passed via -e (a separate -e chunk can't see
-- another -e chunk's bare-assigned names). The only way to deliberately
-- create a real, host-visible global is to write through _G explicitly.
-- Subprocess-based since it needs two separate chunks in one process.

ok_bare = os.execute("bin/luam -e \"x = 5\" -e \"os.exit(x == nil)\"")
assert(ok_bare == true,
       "bare assignment in one chunk must not leak into a later chunk")

ok_explicit = os.execute("bin/luam -e \"_G.y = 6\" -e \"os.exit(y == 6)\"")
assert(ok_explicit == true,
       "_G.y = ... should create a real global visible to later chunks")

print("PASS explicit _G escape hatch check")
