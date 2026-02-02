# Lua VM Debugging State - 2026-02-01 (Update)

## Achievements
1. **Fixed VM Hang:** The hang in `tst/run_all.lua` was caused by inverted logic in `OP_LT` and `OP_LE` instructions in `vm_exec.odin`.
   - Lua spec: `if ((RK(B) < RK(C)) ~= A) then pc++`. This means if condition != A, jump.
   - Odin implementation had: `if (less == A)`.
   - Fix: Changed `==` to `!=` for `OP_LT` and `OP_LE`.
   - Result: Test suite now runs past the hang.

2. **Build System Update:**
   - Modified build process to link Odin implementations of `base`, `string`, etc., by stripping C implementations (`lbaselib.o`, `lstrlib.o`) from `liblua.a`.
   - Exported `luaopen_base` and `luaopen_string` with correct `link_name` in Odin.

## New Problem: Missing Library Functions
After fixing the hang, the test fails with `attempt to call a nil value` at `string.match` (line 90 of `tst/run_all.lua`).
Further debugging revealed:
- `tst/run_all.lua` crashes because `string.match` is nil.
- Basic tests (`-e "print(pairs)"`) also crash because `print` and `pairs` are nil.
- `Debug` logs confirm `open_base` (Odin) is called.
- `_G` is set.
- However, `interning NEW 'print'` logs are missing, suggesting `luaL_register` loop is not processing `base_funcs` correctly or `print` string is not being interned/set.
- `string` library functions like `len` and `rep` ARE registered (logs show `interning NEW 'len'`), but `match` seems missing.

### Current Hypothesis
- `luaL_register` (in `lauxlib.c`) might be failing to iterate the `base_funcs` array correctly when passed from Odin.
- Struct layout mismatch for `luaL_Reg` between Odin and C?
- `luaL_findtable` usage in `luaL_register` might be resolving `_G` incorrectly or creating a new table instead of using `_G`.

## Next Steps
1. Verify `luaL_Reg` struct alignment and size consistency between C and Odin.
2. Implement manual registration loop in `open_base` (bypassing `luaL_register`) to verify if individual function insertion works.
3. Investigate `luaH_getstr` failure for `string.match` despite successful insertion (if inserted).
