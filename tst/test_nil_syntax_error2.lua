#!/usr/bin/env lua
-- This file intentionally contains SYNTAX ERRORS to demonstrate LuaM's restrictions

-- SYNTAX ERROR #2: not nil in conditional
if not nil then
    print("This will never compile")
end
