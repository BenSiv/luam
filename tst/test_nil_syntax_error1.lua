#!/usr/bin/env lua
-- This file intentionally contains SYNTAX ERRORS to demonstrate LuaM's restrictions

-- SYNTAX ERROR #1: Literal nil in conditional
if nil then
    print("This will never compile")
end
