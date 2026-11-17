-- Generic property-based and stateful law-checking library for Luam.
-- Zero external or C dependencies, zero domain-specific vocabulary:
-- usable for pure algebraic laws (idempotence, involution, homomorphism,
-- commutative diagrams, monotonicity) and stateful state-machine models
-- with integrated counterexample shrinking.
--
-- Reproducibility: defaults to deterministic seed 20261117 unless
-- opts.seed or LAWS_SEED=<int|random> is set. Every failure reports the
-- exact seed and the minimal shrunk input or command trace.

laws = {}

DEFAULT_SEED = 20261117
MOD32 = 4294967296

--------------------------------------------------------------------------
-- Deterministic 32-bit PRNG (exact in IEEE-754 binary64; max product
-- below 2^53 is 1664525 * (2^32 - 1) + 1013904223 ~= 7.15e15 < 9.007e15)
--------------------------------------------------------------------------

function resolve_seed(explicit_seed)
    if explicit_seed != nil then
        return math.floor(math.abs(tonumber(explicit_seed))) % MOD32
    end
    env_seed = os.getenv("LAWS_SEED")
    if env_seed == "random" then
        return (os.time() + math.floor(os.clock() * 1000000)) % MOD32
    end
    if env_seed != nil and tonumber(env_seed) != nil then
        return math.floor(math.abs(tonumber(env_seed))) % MOD32
    end
    return DEFAULT_SEED
end

function laws.rng(seed)
    s = resolve_seed(seed)
    -- Warm up initial state so small adjacent integer seeds diverge immediately.
    state = (s * 1664525 + 1013904223) % MOD32
    state = (state * 1664525 + 1013904223) % MOD32
    r = {seed = s, state = state}
    return r
end

function rng_u32(r)
    r.state = (r.state * 1664525 + 1013904223) % MOD32
    -- Mix high and low bits (xorshift-like permutation via arithmetic)
    hi = math.floor(r.state / 65536)
    lo = r.state % 65536
    mixed = ((lo * 40503) % 65536) * 65536 + ((hi + lo) % 65536)
    return mixed % MOD32
end

function rng_float(r)
    return rng_u32(r) / MOD32
end

function rng_int(r, lo, hi)
    if hi <= lo then
        return lo
    end
    span = hi - lo + 1
    return lo + (rng_u32(r) % span)
end

--------------------------------------------------------------------------
-- Formatting & Structural Equality
--------------------------------------------------------------------------

format_value = nil
format_value = function(v)
    t = type(v)
    if t == "nil" then
        return "nil"
    end
    if t == "number" or t == "boolean" then
        return tostring(v)
    end
    if t == "string" then
        return string.format("%q", v)
    end
    if t != "table" then
        return "<" .. t .. ">"
    end
    -- Detect dense 1..N array vs map for clean output
    count = 0
    max_idx = 0
    is_array = true
    keys = {}
    for k, _ in pairs(v) do
        count = count + 1
        table.insert(keys, k)
        if type(k) == "number" and k >= 1 and math.floor(k) == k then
            if k > max_idx then
                max_idx = k
            end
        else
            is_array = false
        end
    end
    if count == 0 then
        return "{}"
    end
    if is_array and max_idx == count then
        parts = {}
        for i = 1, count do
            table.insert(parts, format_value(v[i]))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    parts = {}
    for _, k in ipairs(keys) do
        key_str = "[" .. format_value(k) .. "]"
        if type(k) == "string" and string.match(k, "^[%a_][%w_]*$") != nil then
            key_str = k
        end
        table.insert(parts, key_str .. " = " .. format_value(v[k]))
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

laws.format = format_value

deep_equal = nil
deep_equal = function(a, b, tolerance)
    ta = type(a)
    tb = type(b)
    if ta != tb then
        return false
    end
    if ta == "number" then
        if a != a and b != b then
            return true
        end
        if tolerance != nil and tolerance > 0 then
            return math.abs(a - b) <= tolerance
        end
        return a == b
    end
    if ta != "table" then
        return a == b
    end
    for k, va in pairs(a) do
        if not deep_equal(va, b[k], tolerance) then
            return false
        end
    end
    for k, _ in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

laws.deep_equal = deep_equal

--------------------------------------------------------------------------
-- Integrated Shrink Trees: node = {value = v, shrinks = function() -> {node, ...}}
--------------------------------------------------------------------------

function leaf_node(v)
    return {value = v, shrinks = function() return {} end}
end

make_int_node = nil
make_int_node = function(val, target)
    return {
        value = val,
        shrinks = function()
            if val == target then
                return {}
            end
            out = {}
            seen = {}
            diff = val - target
            step = diff
            -- First try jumping straight to `target`, then binary-search midpoints toward `val`.
            table.insert(out, make_int_node(target, target))
            seen[target] = true
            while math.abs(step) > 1 do
                if step > 0 then
                    step = math.floor(step / 2)
                else
                    step = -math.floor((-step) / 2)
                end
                cand = val - step
                if cand != val and seen[cand] == nil then
                    seen[cand] = true
                    table.insert(out, make_int_node(cand, target))
                end
            end
            if val > target and seen[val - 1] == nil then
                table.insert(out, make_int_node(val - 1, target))
            elseif val < target and seen[val + 1] == nil then
                table.insert(out, make_int_node(val + 1, target))
            end
            return out
        end,
    }
end

make_real_node = nil
make_real_node = function(val, lo, hi, depth)
    return {
        value = val,
        shrinks = function()
            if depth >= 12 then
                return {}
            end
            target = 0.0
            if lo > 0.0 then
                target = lo
            elseif hi < 0.0 then
                target = hi
            end
            if math.abs(val - target) < 1e-9 then
                return {}
            end
            cands = {target}
            rounded = math.floor(val)
            if rounded >= lo and rounded <= hi and math.abs(rounded - val) > 1e-9 then
                table.insert(cands, rounded)
            end
            mid = target + (val - target) * 0.5
            if mid >= lo and mid <= hi then
                table.insert(cands, mid)
            end
            out = {}
            for _, c in ipairs(cands) do
                if math.abs(c - val) > 1e-9 then
                    table.insert(out, make_real_node(c, lo, hi, depth + 1))
                end
            end
            return out
        end,
    }
end

map_node = nil
map_node = function(node, fn)
    return {
        value = fn(node.value),
        shrinks = function()
            children = node.shrinks()
            mapped = {}
            for _, child in ipairs(children) do
                table.insert(mapped, map_node(child, fn))
            end
            return mapped
        end,
    }
end

filter_node = nil
filter_node = function(node, pred)
    return {
        value = node.value,
        shrinks = function()
            filtered = {}
            for _, child in ipairs(node.shrinks()) do
                if pred(child.value) == true then
                    table.insert(filtered, filter_node(child, pred))
                end
            end
            return filtered
        end,
    }
end

--------------------------------------------------------------------------
-- Value Generators: gen = {generate = function(rng, size) -> node}
--------------------------------------------------------------------------

function laws.constant(val)
    return {
        generate = function(_, _)
            return leaf_node(val)
        end,
    }
end

function laws.boolean()
    return {
        generate = function(r, _)
            b = rng_int(r, 0, 1) == 1
            if not b then
                return leaf_node(false)
            end
            return {
                value = true,
                shrinks = function()
                    return {leaf_node(false)}
                end,
            }
        end,
    }
end

function laws.int(lo, hi)
    if lo == nil then lo = -100 end
    if hi == nil then hi = 100 end
    target = 0
    if lo > 0 then
        target = lo
    elseif hi < 0 then
        target = hi
    end
    return {
        generate = function(r, size)
            eff_lo = lo
            eff_hi = hi
            if size != nil and size >= 0 then
                bound_lo = target - size
                bound_hi = target + size
                if bound_lo > eff_lo and bound_lo <= eff_hi then
                    eff_lo = bound_lo
                end
                if bound_hi < eff_hi and bound_hi >= eff_lo then
                    eff_hi = bound_hi
                end
            end
            v = rng_int(r, eff_lo, eff_hi)
            return make_int_node(v, target)
        end,
    }
end

function laws.real(lo, hi)
    if lo == nil then lo = -100.0 end
    if hi == nil then hi = 100.0 end
    return {
        generate = function(r, _)
            v = lo + rng_float(r) * (hi - lo)
            return make_real_node(v, lo, hi, 0)
        end,
    }
end

function laws.one_of(items)
    if items == nil or #items == 0 then
        error("laws.one_of requires a non-empty list")
    end
    return {
        generate = function(r, _)
            idx = rng_int(r, 1, #items)
            return map_node(make_int_node(idx, 1), function(i) return items[i] end)
        end,
    }
end

function laws.frequency(weighted_gens)
    if weighted_gens == nil or #weighted_gens == 0 then
        error("laws.frequency requires a non-empty list of {weight, gen} pairs")
    end
    total_w = 0
    for _, pair in ipairs(weighted_gens) do
        total_w = total_w + pair[1]
    end
    if total_w <= 0 then
        error("laws.frequency total weight must be positive")
    end
    return {
        generate = function(r, size)
            pick = rng_int(r, 1, total_w)
            acc = 0
            chosen = weighted_gens[1][2]
            for _, pair in ipairs(weighted_gens) do
                acc = acc + pair[1]
                if pick <= acc then
                    chosen = pair[2]
                    break
                end
            end
            return chosen.generate(r, size)
        end,
    }
end

make_list_node = nil
make_list_node = function(elem_nodes, min_len)
    vals = {}
    for i, en in ipairs(elem_nodes) do
        vals[i] = en.value
    end
    return {
        value = vals,
        shrinks = function()
            n = #elem_nodes
            out = {}
            -- 1. Drop chunks / single elements down toward min_len
            if n > min_len then
                if min_len == 0 then
                    table.insert(out, make_list_node({}, 0))
                end
                chunk = math.floor((n - min_len) / 2)
                while chunk >= 1 do
                    k = 1
                    while k + chunk - 1 <= n and (n - chunk) >= min_len do
                        sliced = {}
                        for j = 1, n do
                            if j < k or j > k + chunk - 1 then
                                table.insert(sliced, elem_nodes[j])
                            end
                        end
                        table.insert(out, make_list_node(sliced, min_len))
                        k = k + chunk
                    end
                    chunk = math.floor(chunk / 2)
                end
            end
            -- 2. Shrink individual elements in place
            for i = 1, n do
                for _, shrunk_elem in ipairs(elem_nodes[i].shrinks()) do
                    copy = {}
                    for j = 1, n do
                        copy[j] = elem_nodes[j]
                    end
                    copy[i] = shrunk_elem
                    table.insert(out, make_list_node(copy, min_len))
                end
            end
            return out
        end,
    }
end

function laws.list(elem_gen, opts)
    min_len = 0
    max_len = 20
    if opts != nil then
        if opts.min_len != nil then min_len = opts.min_len end
        if opts.max_len != nil then max_len = opts.max_len end
    end
    return {
        generate = function(r, size)
            cap = max_len
            if size != nil and size < cap then
                cap = size
                if cap < min_len then
                    cap = min_len
                end
            end
            len = rng_int(r, min_len, cap)
            nodes = {}
            for i = 1, len do
                nodes[i] = elem_gen.generate(r, size)
            end
            return make_list_node(nodes, min_len)
        end,
    }
end

DEFAULT_ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-./:'\"[]"

function laws.text(opts)
    min_len = 0
    max_len = 24
    alphabet = DEFAULT_ALPHABET
    if opts != nil then
        if opts.min_len != nil then min_len = opts.min_len end
        if opts.max_len != nil then max_len = opts.max_len end
        if opts.alphabet != nil and string.len(opts.alphabet) > 0 then
            alphabet = opts.alphabet
        end
    end
    alpha_len = string.len(alphabet)
    char_idx_gen = {
        generate = function(r, _)
            idx = rng_int(r, 1, alpha_len)
            return make_int_node(idx, 1)
        end,
    }
    list_gen = laws.list(char_idx_gen, {min_len = min_len, max_len = max_len})
    return laws.map(list_gen, function(indices)
        chars = {}
        for i, idx in ipairs(indices) do
            chars[i] = string.sub(alphabet, idx, idx)
        end
        return table.concat(chars)
    end)
end

make_record_node = nil
make_record_node = function(sorted_keys, field_nodes)
    rec = {}
    for _, k in ipairs(sorted_keys) do
        rec[k] = field_nodes[k].value
    end
    return {
        value = rec,
        shrinks = function()
            out = {}
            for _, k in ipairs(sorted_keys) do
                for _, shrunk_field in ipairs(field_nodes[k].shrinks()) do
                    next_nodes = {}
                    for _, k2 in ipairs(sorted_keys) do
                        next_nodes[k2] = field_nodes[k2]
                    end
                    next_nodes[k] = shrunk_field
                    table.insert(out, make_record_node(sorted_keys, next_nodes))
                end
            end
            return out
        end,
    }
end

function laws.record(schema_tbl)
    sorted_keys = {}
    for k, _ in pairs(schema_tbl) do
        table.insert(sorted_keys, k)
    end
    table.sort(sorted_keys, function(a, b) return tostring(a) < tostring(b) end)
    return {
        generate = function(r, size)
            field_nodes = {}
            for _, k in ipairs(sorted_keys) do
                field_nodes[k] = schema_tbl[k].generate(r, size)
            end
            return make_record_node(sorted_keys, field_nodes)
        end,
    }
end

function laws.tuple(...)
    gens = {...}
    schema_tbl = {}
    for i, g in ipairs(gens) do
        schema_tbl[i] = g
    end
    return laws.record(schema_tbl)
end

function laws.map(gen, fn)
    return {
        generate = function(r, size)
            return map_node(gen.generate(r, size), fn)
        end,
    }
end

function laws.filter(gen, pred, max_tries)
    limit = 100
    if max_tries != nil then
        limit = max_tries
    end
    return {
        generate = function(r, size)
            for _ = 1, limit do
                cand = gen.generate(r, size)
                if pred(cand.value) == true then
                    return filter_node(cand, pred)
                end
            end
            error("laws.filter: exhausted " .. tostring(limit) .. " attempts without matching predicate")
        end,
    }
end

function laws.bind(gen, fn)
    return {
        generate = function(r, size)
            outer = gen.generate(r, size)
            next_gen = fn(outer.value)
            return next_gen.generate(r, size)
        end,
    }
end

--------------------------------------------------------------------------
-- Property Execution, Shrinking & Algebraic Law Combinators
--------------------------------------------------------------------------

function run_predicate(prop_fn, val)
    ok_call, res, msg = pcall(prop_fn, val)
    if not ok_call then
        return false, "raised error: " .. tostring(res)
    end
    if res == true then
        return true, nil
    end
    if msg != nil then
        return false, tostring(msg)
    end
    return false, "property returned " .. tostring(res)
end

function shrink_node(failing_node, prop_fn, max_shrinks)
    best_node = failing_node
    _, best_reason = run_predicate(prop_fn, best_node.value)
    steps = 0
    improved = true
    while improved and steps < max_shrinks do
        improved = false
        for _, cand in ipairs(best_node.shrinks()) do
            steps = steps + 1
            passed, reason = run_predicate(prop_fn, cand.value)
            if not passed then
                best_node = cand
                best_reason = reason
                improved = true
                break
            end
            if steps >= max_shrinks then
                break
            end
        end
    end
    return best_node.value, best_reason, steps
end

-- Runs `prop_fn(val)` across `trials` generated inputs without throwing:
-- returns `true, {trials = N, seed = S}` on success, or `false, failure_tbl`
-- with both `original` and minimal `shrunk` counterexample.
function laws.check(name, gen, prop_fn, opts)
    trials = 100
    max_size = 50
    max_shrinks = 300
    explicit_seed = nil
    if opts != nil then
        if opts.trials != nil then trials = opts.trials end
        if opts.max_size != nil then max_size = opts.max_size end
        if opts.max_shrinks != nil then max_shrinks = opts.max_shrinks end
        if opts.seed != nil then explicit_seed = opts.seed end
    end
    r = laws.rng(explicit_seed)
    for i = 1, trials do
        size = 1 + math.floor(((i - 1) * max_size) / math.max(1, trials))
        node = gen.generate(r, size)
        passed, reason = run_predicate(prop_fn, node.value)
        if not passed then
            shrunk_val, shrunk_reason, shrink_steps = shrink_node(node, prop_fn, max_shrinks)
            return false, {
                name = name,
                seed = r.seed,
                trial = i,
                original = node.value,
                shrunk = shrunk_val,
                reason = shrunk_reason,
                original_reason = reason,
                shrink_steps = shrink_steps,
            }
        end
    end
    return true, {name = name, seed = r.seed, trials = trials}
end

function laws.forall(name, gen, prop_fn, opts)
    ok, info = laws.check(name, gen, prop_fn, opts)
    if ok then
        return true
    end
    error(string.format(
        "Law '%s' violated (LAWS_SEED=%d, trial=%d, shrinks=%d):\n  counterexample: %s\n  original input: %s\n  reason: %s",
        tostring(info.name), info.seed, info.trial, info.shrink_steps,
        format_value(info.shrunk), format_value(info.original), tostring(info.reason)
    ), 2)
end

function resolve_eq(opts)
    if opts != nil and opts.eq != nil then
        return opts.eq
    end
    tol = nil
    if opts != nil then
        tol = opts.tolerance
    end
    return function(a, b)
        return deep_equal(a, b, tol)
    end
end

-- f(f(x)) == f(x)
function laws.idempotent(name, gen, fn, opts)
    eq = resolve_eq(opts)
    return laws.forall(name, gen, function(x)
        fx = fn(x)
        ffx = fn(fx)
        if eq(ffx, fx) == true then
            return true
        end
        return false, "f(f(x)) != f(x): f(x)=" .. format_value(fx) .. ", f(f(x))=" .. format_value(ffx)
    end, opts)
end

-- f(f(x)) == x
function laws.involution(name, gen, fn, opts)
    eq = resolve_eq(opts)
    return laws.forall(name, gen, function(x)
        ffx = fn(fn(x))
        if eq(ffx, x) == true then
            return true
        end
        return false, "f(f(x)) != x: got " .. format_value(ffx)
    end, opts)
end

-- left_fn(x) == right_fn(x)
function laws.commutative_diagram(name, gen, left_fn, right_fn, opts)
    eq = resolve_eq(opts)
    return laws.forall(name, gen, function(x)
        lv = left_fn(x)
        rv = right_fn(x)
        if eq(lv, rv) == true then
            return true
        end
        return false, "diagram did not commute: left=" .. format_value(lv) .. " vs right=" .. format_value(rv)
    end, opts)
end

-- phi(op_src(a, b)) == op_dst(phi(a), phi(b))
function laws.homomorphism(name, gen_a, gen_b, op_src, op_dst, phi, opts)
    eq = resolve_eq(opts)
    pair_gen = laws.tuple(gen_a, gen_b)
    return laws.forall(name, pair_gen, function(pair)
        a = pair[1]
        b = pair[2]
        lhs = phi(op_src(a, b))
        rhs = op_dst(phi(a), phi(b))
        if eq(lhs, rhs) == true then
            return true
        end
        return false, "phi(a (*) b) != phi(a) (+) phi(b): lhs=" .. format_value(lhs) .. " vs rhs=" .. format_value(rhs)
    end, opts)
end

-- le_in(a, b) => le_out(fn(a), fn(b))
function laws.monotone(name, gen_a, gen_b, le_in, le_out, fn, opts)
    pair_gen = laws.tuple(gen_a, gen_b)
    return laws.forall(name, pair_gen, function(pair)
        a = pair[1]
        b = pair[2]
        if le_in(a, b) == true then
            fa = fn(a)
            fb = fn(b)
            if le_out(fa, fb) != true then
                return false, "a <= b did not imply f(a) <= f(b): f(a)=" .. format_value(fa) .. ", f(b)=" .. format_value(fb)
            end
        elseif le_in(b, a) == true then
            fb = fn(b)
            fa = fn(a)
            if le_out(fb, fa) != true then
                return false, "b <= a did not imply f(b) <= f(a): f(b)=" .. format_value(fb) .. ", f(a)=" .. format_value(fa)
            end
        end
        return true
    end, opts)
end

--------------------------------------------------------------------------
-- Stateful Command-Trace Law Runner (`laws.state_machine`)
--------------------------------------------------------------------------
--
-- spec = {
--   name = "...",
--   trials = 40,          -- default 40 traces
--   max_steps = 25,       -- default 25 commands per trace
--   max_shrinks = 200,
--   seed = optional,
--   init = function() -> sut, model end,
--   teardown = optional function(sut) end,
--   commands = {
--     {
--       name = "...",
--       weight = optional integer >= 1 (default 1),
--       applicable = optional function(model) -> boolean,
--       args = optional function(model) -> generator (default const({})),
--       valid_args = optional function(model, args_val) -> boolean,
--       run = function(sut, args_val, model) -> result,
--       next_model = optional function(model, args_val, result) -> new_model (may mutate model in place and return nil),
--       check = optional function(sut, model, args_val, result) -> boolean, reason,
--     }, ...
--   },
--   invariants = {
--     {name = "...", check = function(sut, model) -> boolean, reason}, ...
--   }
-- }

function cmd_is_applicable(cmd, model)
    if cmd.applicable == nil then
        return true
    end
    return cmd.applicable(model) == true
end

function cmd_args_valid(cmd, model, args_val)
    if not cmd_is_applicable(cmd, model) then
        return false
    end
    if cmd.valid_args == nil then
        return true
    end
    return cmd.valid_args(model, args_val) == true
end

function advance_model(cmd, model, args_val, result)
    if cmd.next_model != nil then
        updated = cmd.next_model(model, args_val, result)
        if updated != nil then
            return updated
        end
    end
    return model
end

function safe_teardown(spec, sut)
    if spec.teardown != nil and sut != nil then
        pcall(spec.teardown, sut)
    end
end

-- Executes a concrete candidate `steps` list (`{{cmd = cmd_spec, node = args_node}, ...}`)
-- from a fresh `spec.init()`. Returns `true, nil` if all steps are valid
-- and every postcondition + invariant holds, or:
--   `"invalid", nil` if a shrunk prefix invalidated a later step's precondition,
--   `"failed", {step_index = k, steps_run = prefix, where = ..., reason = ...}` on a real law violation!
function execute_trace(spec, steps)
    sut, model = spec.init()
    invariants = spec.invariants
    if invariants == nil then
        invariants = {}
    end

    -- Check invariants on initial state too
    for _, inv in ipairs(invariants) do
        ok_inv, inv_res, inv_msg = pcall(inv.check, sut, model)
        if not ok_inv then
            safe_teardown(spec, sut)
            return "failed", {step_index = 0, steps_run = {}, where = "invariant '" .. tostring(inv.name) .. "' (init)", reason = "raised: " .. tostring(inv_res)}
        end
        if inv_res != true then
            safe_teardown(spec, sut)
            return "failed", {step_index = 0, steps_run = {}, where = "invariant '" .. tostring(inv.name) .. "' (init)", reason = tostring(inv_msg)}
        end
    end

    executed = {}
    for k, entry in ipairs(steps) do
        cmd = entry.cmd
        args_val = entry.node.value
        if not cmd_args_valid(cmd, model, args_val) then
            safe_teardown(spec, sut)
            return "invalid", nil
        end
        table.insert(executed, entry)
        ok_run, run_res = pcall(cmd.run, sut, args_val, model)
        if not ok_run then
            safe_teardown(spec, sut)
            return "failed", {
                step_index = k,
                steps_run = executed,
                where = "command '" .. tostring(cmd.name) .. "'",
                reason = "raised error: " .. tostring(run_res),
            }
        end
        model = advance_model(cmd, model, args_val, run_res)

        if cmd.check != nil then
            ok_chk, chk_res, chk_msg = pcall(cmd.check, sut, model, args_val, run_res)
            if not ok_chk then
                safe_teardown(spec, sut)
                return "failed", {step_index = k, steps_run = executed, where = "postcondition '" .. tostring(cmd.name) .. "'", reason = "raised: " .. tostring(chk_res)}
            end
            if chk_res != true then
                safe_teardown(spec, sut)
                return "failed", {step_index = k, steps_run = executed, where = "postcondition '" .. tostring(cmd.name) .. "'", reason = tostring(chk_msg)}
            end
        end

        for _, inv in ipairs(invariants) do
            ok_inv, inv_res, inv_msg = pcall(inv.check, sut, model)
            if not ok_inv then
                safe_teardown(spec, sut)
                return "failed", {step_index = k, steps_run = executed, where = "invariant '" .. tostring(inv.name) .. "'", reason = "raised: " .. tostring(inv_res)}
            end
            if inv_res != true then
                safe_teardown(spec, sut)
                return "failed", {step_index = k, steps_run = executed, where = "invariant '" .. tostring(inv.name) .. "'", reason = tostring(inv_msg)}
            end
        end
    end

    safe_teardown(spec, sut)
    return "passed", nil
end

function generate_and_run_trace(spec, r, num_steps)
    sut, model = spec.init()
    invariants = spec.invariants
    if invariants == nil then
        invariants = {}
    end

    for _, inv in ipairs(invariants) do
        ok_inv, inv_res, inv_msg = pcall(inv.check, sut, model)
        if (not ok_inv) or inv_res != true then
            safe_teardown(spec, sut)
            reason = tostring(inv_msg)
            if not ok_inv then reason = "raised: " .. tostring(inv_res) end
            return false, {step_index = 0, steps_run = {}, where = "invariant '" .. tostring(inv.name) .. "' (init)", reason = reason}
        end
    end

    executed = {}
    for k = 1, num_steps do
        eligible = {}
        total_weight = 0
        for _, cmd in ipairs(spec.commands) do
            if cmd_is_applicable(cmd, model) then
                w = 1
                if cmd.weight != nil and cmd.weight > 0 then
                    w = cmd.weight
                end
                table.insert(eligible, {cmd = cmd, weight = w})
                total_weight = total_weight + w
            end
        end
        if #eligible == 0 then
            break
        end
        pick = rng_int(r, 1, total_weight)
        acc = 0
        chosen_cmd = eligible[1].cmd
        for _, item in ipairs(eligible) do
            acc = acc + item.weight
            if pick <= acc then
                chosen_cmd = item.cmd
                break
            end
        end

        args_node = leaf_node({})
        if chosen_cmd.args != nil then
            args_gen = chosen_cmd.args(model)
            args_node = args_gen.generate(r, 20)
        end
        entry = {cmd = chosen_cmd, node = args_node}
        table.insert(executed, entry)

        ok_run, run_res = pcall(chosen_cmd.run, sut, args_node.value, model)
        if not ok_run then
            safe_teardown(spec, sut)
            return false, {step_index = k, steps_run = executed, where = "command '" .. tostring(chosen_cmd.name) .. "'", reason = "raised error: " .. tostring(run_res)}
        end
        model = advance_model(chosen_cmd, model, args_node.value, run_res)

        if chosen_cmd.check != nil then
            ok_chk, chk_res, chk_msg = pcall(chosen_cmd.check, sut, model, args_node.value, run_res)
            if (not ok_chk) or chk_res != true then
                safe_teardown(spec, sut)
                reason = tostring(chk_msg)
                if not ok_chk then reason = "raised: " .. tostring(chk_res) end
                return false, {step_index = k, steps_run = executed, where = "postcondition '" .. tostring(chosen_cmd.name) .. "'", reason = reason}
            end
        end

        for _, inv in ipairs(invariants) do
            ok_inv, inv_res, inv_msg = pcall(inv.check, sut, model)
            if (not ok_inv) or inv_res != true then
                safe_teardown(spec, sut)
                reason = tostring(inv_msg)
                if not ok_inv then reason = "raised: " .. tostring(inv_res) end
                return false, {step_index = k, steps_run = executed, where = "invariant '" .. tostring(inv.name) .. "'", reason = reason}
            end
        end
    end

    safe_teardown(spec, sut)
    return true, nil
end

function shrink_trace(spec, failing_info, max_shrinks)
    best_steps = {}
    for i, e in ipairs(failing_info.steps_run) do
        best_steps[i] = e
    end
    best_fail = failing_info
    budget = 0

    -- Pass 1: chunk & single-step deletion
    improved = true
    while improved and budget < max_shrinks and #best_steps > 1 do
        improved = false
        chunk = math.floor(#best_steps / 2)
        if chunk < 1 then chunk = 1 end
        while chunk >= 1 and budget < max_shrinks do
            pos = 1
            while pos + chunk - 1 <= #best_steps and #best_steps - chunk >= 1 and budget < max_shrinks do
                cand = {}
                for j = 1, #best_steps do
                    if j < pos or j > pos + chunk - 1 then
                        table.insert(cand, best_steps[j])
                    end
                end
                budget = budget + 1
                outcome, fail_detail = execute_trace(spec, cand)
                if outcome == "failed" then
                    best_steps = fail_detail.steps_run
                    best_fail = fail_detail
                    improved = true
                    break
                end
                pos = pos + 1
            end
            if improved then
                break
            end
            if chunk == 1 then
                break
            end
            chunk = math.floor(chunk / 2)
            if chunk < 1 then chunk = 1 end
        end
    end

    -- Pass 2: shrink individual command arguments
    arg_improved = true
    while arg_improved and budget < max_shrinks do
        arg_improved = false
        for i = 1, #best_steps do
            for _, shrunk_arg_node in ipairs(best_steps[i].node.shrinks()) do
                if budget >= max_shrinks then break end
                cand = {}
                for j = 1, #best_steps do
                    cand[j] = best_steps[j]
                end
                cand[i] = {cmd = best_steps[i].cmd, node = shrunk_arg_node}
                budget = budget + 1
                outcome, fail_detail = execute_trace(spec, cand)
                if outcome == "failed" then
                    best_steps = fail_detail.steps_run
                    best_fail = fail_detail
                    arg_improved = true
                    break
                end
            end
            if arg_improved or budget >= max_shrinks then
                break
            end
        end
    end

    return best_fail, budget
end

function format_trace_steps(steps)
    if #steps == 0 then
        return "    (initial state before any command)"
    end
    lines = {}
    for i, e in ipairs(steps) do
        table.insert(lines, string.format("    %d. %s(%s)", i, tostring(e.cmd.name), format_value(e.node.value)))
    end
    return table.concat(lines, "\n")
end

function laws.check_state_machine(spec)
    if spec == nil or spec.commands == nil or #spec.commands == 0 then
        error("laws.state_machine requires spec.commands")
    end
    trials = 40
    max_steps = 25
    max_shrinks = 200
    if spec.trials != nil then trials = spec.trials end
    if spec.max_steps != nil then max_steps = spec.max_steps end
    if spec.max_shrinks != nil then max_shrinks = spec.max_shrinks end

    r = laws.rng(spec.seed)
    for trial = 1, trials do
        step_budget = 1 + rng_int(r, 0, max_steps - 1)
        ok, fail_info = generate_and_run_trace(spec, r, step_budget)
        if not ok then
            orig_len = #fail_info.steps_run
            shrunk_fail, shrinks_used = shrink_trace(spec, fail_info, max_shrinks)
            return false, {
                name = spec.name,
                seed = r.seed,
                trial = trial,
                original_length = orig_len,
                shrunk_length = #shrunk_fail.steps_run,
                shrink_steps = shrinks_used,
                where = shrunk_fail.where,
                reason = shrunk_fail.reason,
                steps = shrunk_fail.steps_run,
            }
        end
    end
    return true, {name = spec.name, seed = r.seed, trials = trials}
end

function laws.state_machine(spec)
    ok, info = laws.check_state_machine(spec)
    if ok then
        return true
    end
    error(string.format(
        "State-machine law '%s' violated (LAWS_SEED=%d, trial=%d, shrunk %d -> %d step(s) in %d tries):\n%s\n  failed at %s: %s",
        tostring(info.name), info.seed, info.trial,
        info.original_length, info.shrunk_length, info.shrink_steps,
        format_trace_steps(info.steps), tostring(info.where), tostring(info.reason)
    ), 2)
end

return laws
