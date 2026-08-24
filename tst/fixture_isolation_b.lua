-- Fixture for tst/test_require_isolation.lua. Defines the same bare
-- `shared_name` as tst/fixture_isolation_a.lua, for an unrelated
-- reason -- proving neither leaks to the real global regardless of
-- which one loads first.

function shared_name()
    return "from fixture b"
end

return {marker = shared_name()}
