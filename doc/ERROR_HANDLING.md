# Luam Error Handling Strategy

## New Language Features Summary

1. **`is` Keyword**: Unary operator that checks if a value is not nil
   - `is value` returns `true` if value is not nil, `false` if nil
   - Optimized at compile-time for constant values
   - Runtime check generates `!= nil` comparison

2. **`if nil` is Error**: Literal nil in conditionals (if/while) is a syntax error
   - Forces explicit handling of potentially-nil values
   - Prevents accidental use of nil in control flow

## Recommended Error Handling Patterns

### 1. **Checking for Presence (using `is`)**

```lua
-- Check if optional value exists before using
result = some_function()
if is result then
  -- Safe to use result here
  process(result)
end
```

### 2. **Early Return with `is`**

```lua
function process_data(input)
  if not is input then
    return nil, "input required"
  end
  
  -- Process input...
  return computed_value
end
```

### 3. **Multiple Nil Checks**

```lua
-- Check multiple optional values
user = get_user(id)
profile = get_profile(user)

if is user and is profile then
  display_profile(user, profile)
else
  show_error("User or profile not found")
end
```

### 4. **Return Value Patterns**

#### For General Code: Nil-or-Value Pattern
```lua
function find_item(list, predicate)
  for i = 1, #list do
    if predicate(list[i]) then
      return list[i]  -- Found
    end
  end
  return nil  -- Not found
end

-- Usage
item = find_item(items, checker)
if is item then
  use(item)
else
  handle_not_found()
end
```

#### For APIs: Boolean-Result Pattern
```lua
function api_operation(params)
  success = validate(params)
  if not success then
    return false, "validation failed"
  end
  
  result = perform_operation(params)
  if not is result then
    return false, "operation failed"
  end
  
  return true, result
end

-- Usage
ok, result_or_err = api_operation({...})
if ok then
  use(result_or_err)
else
  log_error(result_or_err)
end
```

#### For Error-Sensitive Code: Nil-with-Error Pattern  
```lua
function parse_data(raw)
  if not is raw then
    return nil, "no data provided"
  end
  
  parsed = try_parse(raw)
  if not is parsed then
    return nil, "parse error: invalid format"
  end
  
  return parsed
end
```

### 5. **Framework-Level: Wrapper Functions with `is`**

```lua
-- Protected call wrapper
function safe_call(fn, ...)
  ok, result = pcall(fn, ...)
  
  if not ok then
    return {ok = false, err = result}
  end
  
  if not is result then
    return {ok = false, err = "function returned nil"}
  end
  
  return {ok = true, result = result}
end

-- Usage
outcome = safe_call(risky_function, arg1, arg2)
if outcome.ok then
  process(outcome.result)
else
  handle_error(outcome.err)
end
```

### 6. **Default Value Pattern**

```lua
-- Provide default when value might be nil
function get_config(key)
  value = config_table[key]
  if is value then
    return value
  else
    return default_configs[key]
  end
end

-- Or using 'or' operator (works because nil is falsy)
function get_config_short(key)
  return config_table[key] or default_configs[key]
end
```

### 7. **Chained Operations**

```lua
function process_pipeline(input)
  stage1 = validate(input)
  if not is stage1 then
    return nil, "validation failed"
  end
  
  stage2 = transform(stage1)
  if not is stage2 then
    return nil, "transformation failed"
  end
  
  stage3 = finalize(stage2)
  if not is stage3 then
    return nil, "finalization failed"
  end
  
  return stage3
end
```

### 8. **Optional Parameters**

```lua
function create_widget(options)
  -- Extract optional fields with defaults
  width = options.width or 100
  height = options.height or 50
  color = options.color or "blue"
  
  -- Check required fields explicitly
  if not is options.name then
    return nil, "name is required"
  end
  
  return build_widget(options.name, width, height, color)
end
```

## Pattern Selection Guide

| Context | Pattern | Example |
|---------|---------|---------|
| **General code** | Return nil or value | `find_user(id)` → `user` or `nil` |
| **APIs** | Return `true, result` / `false, err` | `api_call()` → `true, data` or `false, "error msg"` |
| **Error-sensitive** | Return `nil, err` | `parse_json(str)` → `obj` or `nil, "parse error"` |
| **Frameworks** | Wrap with `{ok, result/err}` | Protected call wrappers |
| **Async/coroutines** | Yield errors or callbacks | Event-driven code |

## Migration from Existing Code

### Before (Standard Lua)
```lua
function get_user(id)
  user = db.query(id)
  if user == nil then  -- explicit nil check
    return nil
  end
  return user
end
```

### After (Luam with `is`)
```lua
function get_user(id)
  user = db.query(id)
  if not is user then  -- cleaner nil check
    return nil
  end
  return user
end
```

## Benefits of `is` Keyword

1. **More Readable**: `is value` is clearer than `value ~= nil` or `value != nil`
2. **Symmetry**: `not is value` mirrors `is value` nicely
3. **Compile-Time Optimization**: Constants are resolved at parse time
4. **Type Safety**: Makes nil-checking explicit and intentional
5. **Error Prevention**: Combined with "if nil" error, prevents accidental nil in conditionals

## Anti-Patterns to Avoid

### ❌ Don't use literal nil in conditionals
```lua
if nil then  -- SYNTAX ERROR in Luam!
  -- This is now a compile error
end
```

### ❌ Don't rely on implicit nil-to-false conversion alone
```lua
-- Less clear
if value then  -- works but doesn't explicitly check for nil
  use(value)
end

-- Better with `is` when nil-checking is the intent
if is value then
  use(value)
end
```

### ✅ Do use `is` for explicit nil-checks
```lua
if is value then
  -- Clearly checking if value exists
  use(value)
end
```

### ✅ Do combine with boolean checks when needed
```lua
-- Check both existence and truthiness
if is value and value then
  -- value exists and is truthy
end

-- Or check type
if is value and type(value) == "string" then
  -- value exists and is a string
end
```

## Summary

The `is` keyword combined with the "if nil" syntax error creates a more robust error handling paradigm in Luam:

- Use `is` to explicitly check for non-nil values
- Choose return patterns based on context (nil-or-value, boolean-result, nil-with-error)
- Leverage compile-time optimization for constant expressions
- Prevent nil-related bugs through explicit checking
- Make code intent clearer and more maintainable
