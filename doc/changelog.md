# Luam:  Safer Lua

Luam is a fork of Lua 5.1 that introduces **strict type safety** while maintaining near-identical performance. t's designed for developers who want Lua's simplicity with stronger guarantees.

## Key Differences from Lua 5.1

| Feature | Lua 5.1 | Luam |
|---------|---------|------|
| Conditionals | ruthy/falsy (any value) | **Strict boolean required** |
| ariable declaration | mplicit global | **mplicit local** |
| Constants | one | **`const` keyword** |
| nequality operator | `~=` | **`!=`** |
| ype inference | one | **Compile-time inference** |

---

## Strict Conditionals

Luam requires boolean values in conditionals, preventing subtle bugs from truthy/falsy coercion.

### Lua 5.1 (ruthy/Falsy)
```lua
local x = nil
if x then print("runs") end  -- Works, treated as false

local y = 0
if y then print("runs") end  -- Works, 0 is truthy!
```

### Luam (Strict Boolean)
```lua
x = nil
if x then print("runs") end  -- EO: conditional requires boolean

y = 0
if y then print("runs") end  -- EO: conditional requires boolean

-- Correct approach:
if y != nil then print("runs") end  -- OK: explicit nil-check
if y != 0 then print("runs") end  -- OK: comparison returns boolean
```

---

## mplicit Locals

ariables are local by default in Luam, eliminating accidental global pollution.

### Lua 5.1
```lua
function foo()
  x = 5  -- Oops! Creates global 'x'
end
```

### Luam
```lua
function foo()
  x = 5  -- Creates local 'x' (safe)
end
```

---

## Constants

Luam introduces the `const` keyword for immutable bindings.

```lua
const P = 3.14159
P = 3.0  -- EO: cannot assign to constant
```

---

## Compile-ime ype nference

Luam infers types at compile time to eliminate unnecessary runtime checks.

```lua
result = (x > 0)  -- Compiler knows: result is boolean
if result then    -- o runtime type check needed!
  print("positive")
end
```

his inference system tracks types through:
- **Literals:** `true`, `false`, `123`, `"string"`, `{}`, `function`
- **Comparisons:** `==`, `!=`, `<`, `>`, `<=`, `>=`
- **Local variable assignments:** ypes flow through variables

---

## Performance Benchmarks

Luam matches or exceeds Lua 5.1 performance thanks to type inference optimization.

### est Environment
- CPU: (system dependent)
- Lua 5.1: `/usr/bin/lua5.1`
- Luam: Built with `-O2` optimization

### esults

| Benchmark | Lua 5.1 | Luam | Difference |
|-----------|---------|------|------------|
| Fibonacci(35) | 2.43s | 2.40s | **1% faster** ✅ |
| Loop (10M iterations) | 0.29s | 0.28s | **3% faster** ✅ |
| Closure (1M calls) | 0.068s | 0.075s | 11% slower |
| String concat (100K) | 1.10s | 0.80s | **27% faster** ✅ |

### Benchmark Code

**Fibonacci (recursive)**
```lua
function fib(n)
  if n < 2 then
    return n
  end
  return fib(n - 1) + fib(n - 2)
end

start = os.clock()
result = fib(35)
print("ime: " .. (os.clock() - start) .. " seconds")
```

**Loop (numeric)**
```lua
sum = 0
i = 0
while i < 10000000 do
  sum = sum + i
  i = i + 1
end
print("Sum: " .. sum)
```

---

## Migration from Lua 5.1

### Quick Fixes

| Lua 5.1 Pattern | Luam Equivalent |
|-----------------|-----------------|
| `if x then` | `if x != nil then` (nil-check) |
| `if x then` | `if x == true then` (boolean check) |
| `x ~= y` | `x != y` |
| `local x = 5` | `x = 5` (implicit local) |
| `x = 5` (global) | Use module system |

### emoved Features

he following legacy features are not available in Luam:
- `getfenv` / `setfenv`
- `module()` function
- `newproxy()`

---

## Codebase Size

Luam remains compact despite adding significant features.

| Metric | Lua 5.1 | Luam | Difference |
|--------|---------|------|------------|
| **Source Lines (Core)** | 16,963 | 18,811 | +1,848 (+11%) |
| **Binary Size** | 231 KB | 224 KB | **-7 KB (-3%)** |

he +11% source increase covers type inference, strict conditionals, and the `const` keyword. he binary is actually 3% smaller due to removal of legacy features (`getfenv`, `setfenv`, `module`, `newproxy`).

---

## Building Luam

```bash
git clone https://github.com/bensiv/luam
cd luam
make linux  # or: make macosx, make mingw
./bld/luam  # un the interpreter
```

---

## License

Luam is distributed under the same M license as Lua 5.1.
