# Lua VM Debugging State - 2026-02-01

## Problem Description
The Lua VM hangs indefinitely when running `tst/run_all.lua`. Specifically, it hangs at line 83 during the evaluation of `#arg` or immediately thereafter.

```lua
83: if #arg > 0 then
85:    print("DEBUG: arg table has " .. #arg .. " elements.")
```

## Current Findings

### 1. Table Length Evaluation (`luaH_getn`)
- **Verified:** `luaH_getn` is functioning correctly.
- For the `arg` table, `sizearray` is 31 (correct for the number of test files passed in `bld/test.sh`).
- `luaH_getn` correctly enters `unbound_search` to check the hash part.
- `unbound_search` calls `luaH_getnum(t, 32)`, which correctly returns `nil` (meaning the boundary is 31).
- `luaH_getn` returns **31** successfully.

### 2. ABI and Struct Layout
- **Verified:** Odin and C structure layouts match.
- `TValue` size: 16 bytes.
- `Table` offsets:
    - `metatable`: 16
    - `array`: 24
    - `node`: 32
    - `sizearray`: 56
- `TValue.tt` is confirmed as `c.int` (4 bytes), matching Lua 5.1's C implementation.

### 3. String Interning
- Interning appears to work (verified via debug logs showing "interning hit" and "interning NEW").
- Global string table starts at size 0 and is resized to 256 (`MINSTRTABSIZE`) during initialization.

### 4. Suspected Locations for the Hang
The hang occurs *after* `luaH_getn` returns. The next VM instructions are:
1. `OP_LEN` (completed)
2. `OP_LT` (evaluating `31 > 0`)
3. `OP_CONCAT` (merging strings for the `print` statement)
4. `tostring` (converting `31` to string `"31"`)
5. `OP_CALL` (calling `print`)

**Potential culprits:**
- **`OP_LT`**: Incorrect branching logic in `vm_exec.odin`.
- **`luaV_concat`**: Infinite loop or logic error during string merging in `vm.odin`.
- **`tostring` / `num_to_str`**: Issues in the number-to-string conversion helper.
- **`luaS_newlstr`**: Potential infinite loop during bucket traversal or rehashing if `next` links are corrupted.

## Experiments & Instrumentation Done
- Added extensive logging to `luaH_getnum`, `newkey`, `unbound_search`, and `luaH_getn`.
- Added ABI verification prints in `state.odin`.
- Added instruction tracing in `vm_exec.odin` (currently commented out but ready for use).
- Integrated `fmt.bprintf` for simplified `num_to_str` implementation in `vm.odin`.

## Strategy for Next Session
1. Enable `OP_CODE` tracing in `vm_exec.odin` to see exactly which instruction hangs.
2. If `OP_CONCAT` is the culprit, instrument `luaV_concat` and `luaS_newlstr` to check for length overflows or pointer corruption.
3. If `OP_LT` is the culprit, verify the `pc` increment logic in `vm_exec.odin` for conditional jumps.
4. Verify `savestack`/`restorestack` logic in Odin, as it might be losing precision or miscalculating offsets during stack reallocations.
