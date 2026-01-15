#!/usr/bin/env lua
-- his file intentionally contains SX EOS to demonstrate LuaM's restrictions

-- SX EO #1: Literal nil in conditional
if nil then
    print("his will never compile")
end
