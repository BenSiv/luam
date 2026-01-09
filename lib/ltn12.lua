-----------------------------------------------------------------------------
-- LTN12 - Filters, sources, sinks and pumps.
-- LuaSocket toolkit.
-- Author: Diego Nehab
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Declare module
-----------------------------------------------------------------------------
string_lib = require("string")
table_lib = require("table")
unpack = unpack or table_lib.unpack
base = _G
select = select

_M = {}
if module then -- heuristic for exporting a global package table
    ltn12 = _M  -- luacheck: ignore
end
filter,source,sink,pump = {},{},{},{}

_M.filter = filter
_M.source = source
_M.sink = sink
_M.pump = pump

-- 2048 seems to be better in windows...
_M.BLOCKSIZE = 2048
_M._VERSION = "LTN12 1.0.3"

-----------------------------------------------------------------------------
-- Filter stuff
-----------------------------------------------------------------------------
-- returns a high level filter that cycles a low-level filter
function filter.cycle(low, ctx, extra)
    base.assert(low)
    return function(chunk)
        ret = nil 
        ret, ctx = low(ctx, chunk, extra)
        return ret
    end
end

-- chains a bunch of filters together
-- (thanks to Wim Couwenberg)
function filter.chain(...)
    arg = {...}
    n = select('#',...)
    top, index = 1, 1
    retry = ""
    return function(chunk_arg)
        chunk = chunk_arg
        retry = chunk and retry
        while true do
            if index == top then
                chunk = arg[index](chunk)
                if chunk == "" or top == n then return chunk
                elseif chunk then index = index + 1
                else
                    top = top+1
                    index = top
                end
            else
                chunk = arg[index](chunk or "")
                if chunk == "" then
                    index = index - 1
                    chunk = retry
                elseif chunk then
                    if index == n then return chunk
                    else index = index + 1 end
                else base.error("filter returned inappropriate nil") end
            end
        end
    end
end

-----------------------------------------------------------------------------
-- Source stuff
-----------------------------------------------------------------------------
-- create an empty source
function empty()
    return nil
end

function source.empty()
    return empty
end

-- returns a source that just outputs an error
function source.error(err)
    return function()
        return nil, err
    end
end

-- creates a file source
function source.file(handle, io_err)
    if handle then
        return function()
            chunk = io.read(handle, _M.BLOCKSIZE)
            if not chunk then io.close(handle) end
            return chunk
        end
    else return source.error(io_err or "unable to open file") end
end

-- turns a fancy source into a simple source
function source.simplify(src_arg)
    base.assert(src_arg)
    src = src_arg
    return function()
        chunk, err_or_new = src()
        src = err_or_new or src
        if not chunk then return nil, err_or_new
        else return chunk end
    end
end

-- creates string source
function source.string(s)
    if s then
        i = 1
        return function()
            chunk = string_lib.sub(s, i, i+_M.BLOCKSIZE-1)
            i = i + _M.BLOCKSIZE
            if chunk != "" then return chunk
            else return nil end
        end
    else return source.empty() end
end

-- creates table source
function source.table(t)
    base.assert('table' == type(t))
    i = 0
    return function()
        i = i + 1
        return t[i]
    end
end

-- creates rewindable source
function source.rewind(src)
    base.assert(src)
    t = {}
    return function(chunk)
        if not chunk then
            chunk = table_lib.remove(t)
            if not chunk then return src()
            else return chunk end
        else
            table_lib.insert(t, chunk)
        end
    end
end

-- chains a source with one or several filter(s)
function source.chain(src, f, ...)
    if ... then f=filter.chain(f, ...) end
    base.assert(src and f)
    last_in, last_out = "", ""
    state = "feeding"
    err = nil 
    return function()
        if not last_out then
            base.error('source is empty!', 2)
        end
        while true do
            if state == "feeding" then
                last_in, err = src()
                if err then return nil, err end
                last_out = f(last_in)
                if not last_out then
                    if last_in then
                        base.error('filter returned inappropriate nil')
                    else
                        return nil
                    end
                elseif last_out != "" then
                    state = "eating"
                    if last_in then last_in = "" end
                    return last_out
                end
            else
                last_out = f(last_in)
                if last_out == "" then
                    if last_in == "" then
                        state = "feeding"
                    else
                        base.error('filter returned ""')
                    end
                elseif not last_out then
                    if last_in then
                        base.error('filter returned inappropriate nil')
                    else
                        return nil
                    end
                else
                    return last_out
                end
            end
        end
    end
end

-- creates a source that produces contents of several sources, one after the
-- other, as if they were concatenated
-- (thanks to Wim Couwenberg)
function source.cat(...)
    arg = {...}
    src = table_lib.remove(arg, 1)
    return function()
        while src do
            chunk, err = src()
            if chunk then return chunk end
            if err then return nil, err end
            src = table_lib.remove(arg, 1)
        end
    end
end

-----------------------------------------------------------------------------
-- Sink stuff
-----------------------------------------------------------------------------
-- creates a sink that stores into a table
function sink.table(t_arg)
    t = t_arg or {}
    f = function(chunk, err)
        if chunk then table_lib.insert(t, chunk) end
        return 1
    end
    return f, t
end

-- turns a fancy sink into a simple sink
function sink.simplify(snk_arg)
    base.assert(snk_arg)
    snk = snk_arg
    return function(chunk, err)
        ret, err_or_new = snk(chunk, err)
        if not ret then return nil, err_or_new end
        snk = err_or_new or snk
        return 1
    end
end

-- creates a file sink
function sink.file(handle, io_err)
    if handle then
        return function(chunk, err)
            if not chunk then
                io.close(handle)
                return 1
            else return io.write(handle, chunk) end
        end
    else return sink.error(io_err or "unable to open file") end
end

-- creates a sink that discards data
function null()
    return 1
end

function sink.null()
    return null
end

-- creates a sink that just returns an error
function sink.error(err)
    return function()
        return nil, err
    end
end

-- chains a sink with one or several filter(s)
function sink.chain(f, snk_arg, ...)
    snk = snk_arg
    if ... then
        args = { f, snk, ... }
        snk = table_lib.remove(args, #args)
        f = filter.chain(unpack(args))
    end
    base.assert(f and snk)
    return function(chunk, err)
        if chunk != "" then
            filtered = f(chunk)
            done = chunk and ""
            while true do
                ret, snkerr = snk(filtered, err)
                if not ret then return nil, snkerr end
                if filtered == done then return 1 end
                filtered = f(done)
            end
        else return 1 end
    end
end

-----------------------------------------------------------------------------
-- Pump stuff
-----------------------------------------------------------------------------
-- pumps one chunk from the source to the sink
function pump.step(src, snk)
    chunk, src_err = src()
    ret, snk_err = snk(chunk, src_err)
    if chunk and ret then return 1
    else return nil, src_err or snk_err end
end

-- pumps all data from a source to a sink, using a step function
function pump.all(src, snk, step)
    base.assert(src and snk)
    step = step or pump.step
    while true do
        ret, err = step(src, snk)
        if not ret then
            if err then return nil, err
            else return 1 end
        end
    end
end

return _M
