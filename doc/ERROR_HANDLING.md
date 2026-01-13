# Luam Error Handling Strategy

## Error Handling with Explicit Nil Checks

Luam requires explicit nil checks using `!= nil` for clear, maintainable code.

## Recommended Error Handling Patterns

### 1. **Checking for Presence**

```lua
-- Check if optional value exists before using
result = some_function()
if result != nil then
  -- Safe to use result here
  process(result)
end
```

### 2. **Early Return Pattern**

```lua
function process_data(input)
  if input == nil then
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

if user != nil and profile != nil then
  display_profile(user, profile)
else
  show_error("User or profile not found")
end
```

### 4. **Return Value Patterns**

#### Nil-or-Value Pattern
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
if item != nil then
  use(item)
else
  handle_not_found()
end
```

#### Boolean-Result Pattern (for APIs)
```lua
function api_operation(params)
  if validate(params) != true then
    return false, "validation failed"
  end
  
  result = perform_operation(params)
  if result == nil then
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

#### Nil-with-Error Pattern
```lua
function parse_data(raw)
  if raw == nil then
    return nil, "no data provided"
  end
  
  parsed = try_parse(raw)
  if parsed == nil then
    return nil, "parse error: invalid format"
  end
  
  return parsed
end
```

### 5. **Default Value Pattern**

```lua
-- Provide default when value might be nil
function get_config(key)
  value = config_table[key]
  if value != nil then
    return value
  else
    return default_configs[key]
  end
end

-- Short form using 'or' operator
function get_config_short(key)
  return config_table[key] or default_configs[key]
end
```

### 6. **Chained Operations**

```lua
function process_pipeline(input)
  stage1 = validate(input)
  if stage1 == nil then
    return nil, "validation failed"
  end
  
  stage2 = transform(stage1)
  if stage2 == nil then
    return nil, "transformation failed"
  end
  
  stage3 = finalize(stage2)
  if stage3 == nil then
    return nil, "finalization failed"
  end
  
  return stage3
end
```

## Pattern Selection Guide

| Context | Pattern | Example |
|---------|---------|---------|
| **General code** | Return nil or value | `find_user(id)` → `user` or `nil` |
| **APIs** | Return `true, result` / `false, err` | `api_call()` → `true, data` or `false, "error"` |
| **Error-sensitive** | Return `nil, err` | `parse_json(str)` → `obj` or `nil, "parse error"` |

## Anti-Patterns to Avoid

### ❌ Don't use truthy/falsy in conditionals
```lua
if value then  -- ERROR: conditional requires boolean
  use(value)
end
```

### ✅ Do use explicit nil checks
```lua
if value != nil then
  use(value)
end
```

### ✅ Do use comparisons that return boolean
```lua
if x > 0 then      -- OK: comparison returns boolean
if x == true then  -- OK: comparison returns boolean
```

## Summary

- Use `!= nil` for explicit nil checks
- Use `== nil` for checking absence
- Choose return patterns based on context
- Conditionals require boolean values (comparisons, true/false)
