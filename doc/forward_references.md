# Forward References and Recursion

Both `function name(...) ... end` and `name = function(...) ... end` are genuine, order-dependent locals (or module-scoped names, at the top level of a required file) -- see `README.md`'s "Implicit Locals" section for why they're treated identically despite looking like two different things, and `changelog.md` for the full history of the two other fixes for this that were tried and reverted before landing here. Being order-dependent means:

- **Self-recursion works with no extra effort.** A function calling itself by its own bare name, anywhere in its own body, always resolves correctly -- the name is active before its own body is compiled.
- **Calling a different function defined later in the same file does not work by default.** The name doesn't exist yet at the point the earlier code is compiled, so the reference falls through to an unresolved global -- `nil` at call time, a loud crash pointing at the exact line, not silent misbehavior.

## The fix: pre-declare before defining

When one function genuinely needs to call another that's defined later -- including the genuinely cyclic case, where two functions call each other -- pre-declare the names as locals first, with an explicit placeholder value, before defining either one:

```lua
f, g = nil, nil

function f(x)
  return g(x - 1)   -- g is already a real local here, correctly captured
end

function g(x)
  if x <= 0 then return 0 end
  return f(x)
end
```

This is exactly the same idiom stock Lua's `local f, g` provides -- Luam just spells it with an ordinary assignment instead of a removed keyword, since `f, g = nil, nil` is itself nothing special: it's the same implicit-local mechanism as any other bare assignment, just with an explicit `nil` value standing in until the real one is assigned. No new syntax, no hoisting, no lookahead in the compiler -- the compiler processes these as two ordinary statements, in the order they appear.

The same pattern works across files too: if file A needs to call a bare helper that's only ever defined in file B, the fix is to alias it after requiring B (`helper = other_module.helper`) rather than relying on it being reachable by its bare name -- a bare name is a lexical local, scoped to the file that declares it, so it was never visible outside that file to begin with.
