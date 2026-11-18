-- Capability-scoped execution: loads untrusted Luam source and runs it
-- bound to a restricted environment table, instead of the real global
-- environment. Originated in daat (see ../daat/doc/architecture.md,
-- "Extension sandboxing: pure Luam, no C required" -- schema files,
-- extension manifests, extension hook bodies) but generic to any
-- downstream project that needs to run untrusted Luam source under a
-- declared capability set -- no second language runtime or C-level
-- trust boundary needed, just `loadstring` + `setfenv` against a table
-- the caller controls.
--
-- Standard-library tables (`string`, `table`, `math`) are shallow-copied
-- from an immutable host snapshot per sandbox environment so untrusted
-- code mutating e.g. `string.gsub` cannot poison the host VM or other
-- sandboxes. Execution inside `sandbox.run` / `sandbox.pcall_bounded`
-- runs under a `debug.sethook` instruction cap that sandboxed `pcall`
-- cannot swallow.

sandbox = {}

sandbox.DEFAULT_MAX_INSTRUCTIONS = 5000000
SANDBOX_LIMIT_MESSAGE = "sandbox execution exceeded instruction limit"

function copy_table(src)
    out = {}
    if src == nil then
        return out
    end
    for k, v in pairs(src) do
        out[k] = v
    end
    return out
end

HOST_STRING = copy_table(string)
HOST_TABLE = copy_table(table)
HOST_MATH = copy_table(math)
HOST_PCALL = pcall
HOST_ERROR = error

_limit_tripped_depth = 0

function pack_results(...)
    return {n = select("#", ...), ...}
end

function unpack_results(packed)
    if packed == nil or packed.n == 0 then
        return
    end
    if unpack != nil then
        return unpack(packed, 1, packed.n)
    end
    return table.unpack(packed, 1, packed.n)
end

function sandbox_pcall(fn, ...)
    packed = pack_results(HOST_PCALL(fn, ...))
    if _limit_tripped_depth > 0 then
        HOST_ERROR(SANDBOX_LIMIT_MESSAGE, 0)
    end
    return unpack_results(packed)
end

-- The floor every sandboxed environment gets: enough to build and
-- inspect plain data, nothing that can touch the filesystem, network,
-- or process state, and isolated copies of stdlib tables.
function base_env()
    return {
        pairs = pairs,
        ipairs = ipairs,
        next = next,
        type = type,
        tostring = tostring,
        tonumber = tonumber,
        select = select,
        error = HOST_ERROR,
        pcall = sandbox_pcall,
        string = copy_table(HOST_STRING),
        table = copy_table(HOST_TABLE),
        math = copy_table(HOST_MATH),
    }
end

-- A data-only sandbox for definition-style files (schema/manifest/config):
-- just enough to construct and return a table literal. No capability
-- grants apply here -- these files aren't extensions, they don't
-- declare capabilities, they just describe data.
function sandbox.data_env()
    return base_env()
end

-- Builds an environment for an extension hook body, from its manifest's
-- declared capabilities. `ctx` is the set of already-capability-checked
-- callback functions (e.g. ctx.query, ctx.create_entity) the caller
-- assembles per-invocation; this just decides what else, if anything,
-- gets added to the global environment (e.g. networking libraries).
function sandbox.extension_env(capabilities)
    env = base_env()
    if capabilities == nil then
        capabilities = {}
    end
    if capabilities.net == "outbound" then
        env.socket = copy_table(require("socket"))
    end
    return env
end

-- Loads `source` (a string of Luam code) bound to `env`, without
-- calling it. Returns the loaded function, or nil + an error message.
function sandbox.load(source, chunkname, env)
    fn, err = loadstring(source, chunkname)
    if fn == nil then
        return nil, err
    end
    setfenv(fn, env)
    return fn
end

-- Executes `fn(...)` inside `pcall` under an instruction cap (`max_steps`;
-- defaults to `sandbox.DEFAULT_MAX_INSTRUCTIONS`, or disabled when `<= 0`
-- or `debug` is unavailable). Preserves and restores any pre-existing
-- `debug` hook.
function sandbox.pcall_bounded(max_steps, fn, ...)
    limit = max_steps
    if limit == nil then
        limit = sandbox.DEFAULT_MAX_INSTRUCTIONS
    end
    if debug == nil or debug.sethook == nil or tonumber(limit) == nil or tonumber(limit) <= 0 then
        return HOST_PCALL(fn, ...)
    end

    step_budget = math.floor(tonumber(limit))
    prev_hook, prev_mask, prev_count = debug.gethook()
    tripped_here = false

    function on_budget_exceeded()
        if not tripped_here then
            tripped_here = true
            _limit_tripped_depth = _limit_tripped_depth + 1
        end
        HOST_ERROR(SANDBOX_LIMIT_MESSAGE, 0)
    end

    args_packed = pack_results(...)
    function invoke_target()
        return fn(unpack_results(args_packed))
    end

    debug.sethook(on_budget_exceeded, "", step_budget)
    call_packed = pack_results(HOST_PCALL(invoke_target))
    if prev_hook != nil then
        debug.sethook(prev_hook, prev_mask, prev_count)
    else
        debug.sethook()
    end

    if tripped_here then
        _limit_tripped_depth = _limit_tripped_depth - 1
        return false, SANDBOX_LIMIT_MESSAGE
    end
    return unpack_results(call_packed)
end

-- Loads and calls `source` in one step, inside a bounded protected call
-- so a crashing, malformed, or infinite-looping script can never take
-- down or hang the caller. Returns ok (boolean), and either the call's
-- return values or an error message.
function sandbox.run(source, chunkname, env, ...)
    fn, err = sandbox.load(source, chunkname, env)
    if fn == nil then
        return false, err
    end
    max_steps = sandbox.DEFAULT_MAX_INSTRUCTIONS
    if type(env) == "table" and env.__max_instructions != nil then
        max_steps = env.__max_instructions
    end
    return sandbox.pcall_bounded(max_steps, fn, ...)
end

return sandbox
