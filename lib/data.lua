-- Canonical Luam table literal serialization, sandboxed loading,
-- variable interpolation, and declarative table-schema validation.

const paths = require("paths")
const sandbox = require("sandbox")

const data = {}

function key_order(a, b)
    ta = type(a)
    tb = type(b)
    if ta != tb then
        return ta < tb
    end
    return a < b
end

function data.sorted_keys(tbl)
    keys = {}
    for k, _ in pairs(tbl) do
        table.insert(keys, k)
    end
    table.sort(keys, key_order)
    return keys
end

function data.is_list(tbl)
    if type(tbl) != "table" then
        return false
    end
    count = 0
    for k, _ in pairs(tbl) do
        if type(k) != "number" or k < 1 or math.floor(k) != k then
            return false
        end
        count = count + 1
    end
    return count == #tbl
end

serialize_impl = nil

function key_literal(key)
    if type(key) == "string" and string.match(key, "^[%a_][%w_]*$") != nil then
        return key
    end
    return "[" .. serialize_impl(key, "") .. "]"
end

serialize_impl = function(value, indent)
    if indent == nil then
        indent = ""
    end
    kind = type(value)
    if kind == "string" then
        return string.format("%q", value)
    end
    if kind == "number" then
        if value != value then
            error("cannot serialize NaN", 0)
        end
        if value == math.huge then
            return "math.huge"
        end
        if value == -math.huge then
            return "-math.huge"
        end
        return tostring(value)
    end
    if kind == "boolean" then
        return tostring(value)
    end
    if kind != "table" then
        error("cannot serialize a " .. kind, 0)
    end
    if next(value) == nil then
        return "{}"
    end
    inner = indent .. "    "
    parts = {}
    if data.is_list(value) then
        for _, item in ipairs(value) do
            table.insert(parts, inner .. serialize_impl(item, inner))
        end
    else
        for _, key in ipairs(data.sorted_keys(value)) do
            table.insert(parts, inner .. key_literal(key) .. " = " .. serialize_impl(value[key], inner))
        end
    end
    return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
end

function data.serialize(value, indent)
    return serialize_impl(value, indent)
end

-- Evaluates Luam source text inside `sandbox.data_env()` and verifies it
-- returns a table. Returns `tbl, nil` or `nil, err`.
function data.loads(source, chunkname)
    label = chunkname
    if label == nil then
        label = "data"
    end
    ok, value = sandbox.run(source, label, sandbox.data_env())
    if not ok then
        return nil, tostring(value)
    end
    if type(value) != "table" then
        return nil, "must return a table, got " .. type(value)
    end
    return value, nil
end

-- Loads a table literal file in the data-only sandbox. Returns `nil` when
-- the file does not exist (unless `opts.required == true`), or raises on
-- malformed source / non-table result.
function data.load(path, opts)
    source = paths.read_file(path)
    if source == nil then
        if opts != nil and opts.required == true then
            error(path .. ": file not found", 0)
        end
        return nil
    end
    tbl, err = data.loads(source, "@" .. path)
    if tbl == nil then
        error(path .. ": " .. err, 0)
    end
    return tbl
end

-- Writes `value` as `"return " .. data.serialize(value)` atomically to `path`.
function data.save(path, value, header)
    text = "return " .. data.serialize(value) .. "\n"
    if header != nil and header != "" then
        text = header .. "\n" .. text
    end
    ok, err = paths.write_atomic(path, text)
    if not ok then
        error(err, 0)
    end
    return true
end

-- Expands `${var}` placeholders (and optional leading `~/` when
-- `expand_tilde == true`) across a string or nested table. Raises on
-- unknown variable names.
function data.expand_vars(value, vars, where, expand_tilde)
    loc = where
    if loc == nil or loc == "" then
        loc = "config"
    end
    vmap = vars
    if vmap == nil then
        vmap = {}
    end
    kind = type(value)
    if kind == "string" then
        missing = nil
        expanded = string.gsub(value, "%${([%w_]+)}", function(name)
            if vmap[name] == nil then
                missing = name
                return ""
            end
            return tostring(vmap[name])
        end)
        if missing != nil then
            error(loc .. ": unknown variable '${" .. missing .. "}'", 0)
        end
        if expand_tilde == true then
            expanded = paths.expand_home(expanded)
        end
        return expanded
    end
    if kind == "table" then
        out = {}
        for k, v in pairs(value) do
            sub_loc = loc .. "." .. tostring(k)
            if type(k) == "number" then
                sub_loc = loc .. "[" .. tostring(k) .. "]"
            end
            out[k] = data.expand_vars(v, vmap, sub_loc, expand_tilde)
        end
        return out
    end
    return value
end

validate_value = nil

-- Validates `value` against `spec`:
--   - string type name: "string", "number", "boolean", "table", "function", "any"
--   - `{list_of = <spec>}`: contiguous list whose elements satisfy `<spec>`
--   - `{map_of = <spec>}`: string-keyed map whose values satisfy `<spec>`
--   - `{one_of = {"a", "b", ...}}`: literal enum membership
--   - `{fields = {k = <spec>, ...}, required = {"k", ...}, allow_extra = bool}`: record table
validate_value = function(value, spec, where)
    if type(spec) == "string" then
        if spec == "any" then
            return true, nil
        end
        if type(value) != spec then
            return false, where .. ": expected " .. spec .. ", got " .. type(value)
        end
        return true, nil
    end

    if type(spec) != "table" then
        return false, where .. ": invalid schema specification"
    end

    if spec.one_of != nil then
        for _, allowed in ipairs(spec.one_of) do
            if value == allowed then
                return true, nil
            end
        end
        parts = {}
        for _, allowed in ipairs(spec.one_of) do
            table.insert(parts, tostring(allowed))
        end
        return false, where .. ": must be one of {" .. table.concat(parts, ", ") .. "}, got " .. tostring(value)
    end

    if type(value) != "table" then
        return false, where .. ": expected table, got " .. type(value)
    end

    if spec.list_of != nil then
        if not data.is_list(value) then
            return false, where .. ": expected a list table"
        end
        for idx, item in ipairs(value) do
            ok_item, err_item = validate_value(item, spec.list_of, where .. "[" .. tostring(idx) .. "]")
            if not ok_item then
                return false, err_item
            end
        end
        return true, nil
    end

    if spec.map_of != nil then
        for k, v in pairs(value) do
            if type(k) != "string" then
                return false, where .. ": expected string map keys, got " .. type(k)
            end
            ok_val, err_val = validate_value(v, spec.map_of, where .. "." .. k)
            if not ok_val then
                return false, err_val
            end
        end
        return true, nil
    end

    if spec.fields != nil then
        if spec.allow_extra != true then
            for _, k in ipairs(data.sorted_keys(value)) do
                if spec.fields[k] == nil then
                    return false, where .. ": unknown field '" .. tostring(k) .. "'"
                end
            end
        end
        if spec.required != nil then
            for _, req_key in ipairs(spec.required) do
                if value[req_key] == nil then
                    return false, where .. ": missing required field '" .. req_key .. "'"
                end
            end
        end
        for _, k in ipairs(data.sorted_keys(spec.fields)) do
            fval = value[k]
            if fval != nil then
                ok_f, err_f = validate_value(fval, spec.fields[k], where .. "." .. tostring(k))
                if not ok_f then
                    return false, err_f
                end
            end
        end
        return true, nil
    end

    return true, nil
end

function data.validate(value, spec, where)
    loc = where
    if loc == nil or loc == "" then
        loc = "root"
    end
    return validate_value(value, spec, loc)
end

function data.must_validate(value, spec, where)
    ok, err = data.validate(value, spec, where)
    if not ok then
        error(err, 0)
    end
    return value
end

return data
