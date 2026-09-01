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
-- Untrusted source is loaded with loadstring and bound to a restricted
-- environment table via setfenv, before ever being called. What that
-- environment contains is entirely up to the caller: sandbox.data_env()
-- gives a bare data-construction environment (no os, no io, not even
-- require); sandbox.extension_env(capabilities) grants only whatever a
-- manifest's declared capabilities call for, built the same way.

sandbox = {}

-- The floor every sandboxed environment gets: enough to build and
-- inspect plain data, nothing that can touch the filesystem, network,
-- or process state.
function base_env()
    return {
        pairs = pairs,
        ipairs = ipairs,
        next = next,
        type = type,
        tostring = tostring,
        tonumber = tonumber,
        select = select,
        error = error,
        pcall = pcall,
        string = string,
        table = table,
        math = math,
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
        env.socket = require("socket")
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

-- Loads and calls `source` in one step, inside a protected call so a
-- crashing or malformed script can never take down the caller. Returns
-- ok (boolean), and either the call's return values or an error message.
function sandbox.run(source, chunkname, env, ...)
    fn, err = sandbox.load(source, chunkname, env)
    if fn == nil then
        return false, err
    end
    return pcall(fn, ...)
end

return sandbox
