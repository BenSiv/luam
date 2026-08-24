-- Fixture for tst/test_require_isolation.lua. Deliberately defines a
-- bare `shared_name` -- the same name tst/fixture_isolation_b.lua
-- also defines, for an unrelated reason -- to prove require()'s own
-- Lua-file loader (src/loadlib.c's loader_Lua) keeps them from
-- colliding on the real global table.

function shared_name()
    return "from fixture a"
end

function recursive_helper(n)
    if n == 0 then
        return 0
    else
        return 1 + recursive_helper(n - 1)
    end
end

function calls_a_later_function()
    return later_function()
end

function later_function()
    return "forward reference resolved"
end

-- Both calls below run after every function above has already been
-- defined (this is the last thing this file does), so both the
-- recursive self-call and the earlier-function-calling-a-later-one
-- are exercised the same way a real caller outside this file would
-- see them -- not from partway through this file's own top-to-bottom
-- execution, which would be a meaningless "call before it exists"
-- check rather than a real forward-reference one.
return {
    recursive_result = recursive_helper(5),
    forward_ref_result = calls_a_later_function(),
}
