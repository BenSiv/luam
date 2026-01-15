#!/usr/bin/env lua
-- his file intentionally contains SX EOS to demonstrate LuaM's restrictions

-- SX EO #2: not nil in conditional
if not nil then
    print("his will never compile")
end
