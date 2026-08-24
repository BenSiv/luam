-- require()'s own Lua-file loader (src/loadlib.c's loader_Lua) gives
-- each required module its own private global table instead of the
-- real one -- __index = the real _G, so reads of genuinely shared
-- names (string, pairs, require, ...) still work, but a bare
-- (unprefixed) write never reaches outside the module that made it.
-- Closes a real, confirmed bug: two unrelated files each defining
-- their own private, never-exported `function replace(...)` helper
-- silently clobbered each other's global. See lib/static/init.lua's
-- own lua_loader, which applies the identical pattern for modules
-- bundled from embedded strings rather than real files (necessarily a
-- separate implementation -- it can't use loadfile on a string that
-- was never a file -- but the same idea).
package.path = package.path .. ";tst/?.lua"

a = require("fixture_isolation_a")
assert(_G.shared_name == nil,
       "fixture_isolation_a's own private shared_name must not leak to the real global")
assert(_G.recursive_helper == nil,
       "fixture_isolation_a's own private recursive_helper must not leak either")
assert(a.recursive_result == 5,
       "a bare recursive function inside a required module must still recurse correctly")
assert(a.forward_ref_result == "forward reference resolved",
       "a bare function calling another bare function defined LATER in the same required file must still resolve -- order must not matter")

b = require("fixture_isolation_b")
assert(_G.shared_name == nil,
       "a second, unrelated module's own private shared_name must not leak either, even though it shares fixture_isolation_a's own private name")
assert(b.marker == "from fixture b",
       "fixture_isolation_b must see its own shared_name, not fixture_isolation_a's")

-- The explicit _G.x = ... escape hatch must still reach the one real
-- global table, from inside a required module, exactly like
-- lib/utils.lua's own merge_module()/using() rely on for their
-- deliberate "expose this to bare-name scripting use" pattern.
loadstring("_G.escape_hatch_probe = 'still works'")()
assert(_G.escape_hatch_probe == "still works",
       "the explicit _G.x = ... escape hatch must still write the one real global from inside a required module")

print("PASS require()-level module isolation check")
