-- Process execution, shell quoting, and guaranteed-cleanup temp files.
--
-- Relies on Luam's C `luaL_execresult` in `io.close(popen_handle)` and
-- `os.execute(cmd)`, which return `(ok_bool, why, code)` directly without
-- needing stdout exit-code markers.

const external_tool = {}

function pack_varargs(...)
    return {n = select("#", ...), ...}
end

function unpack_varargs(packed)
    if packed == nil or packed.n == 0 then
        return
    end
    return table.unpack(packed, 1, packed.n)
end

function external_tool.shell_quote(s)
    return "'" .. string.gsub(tostring(s), "'", "'\\''") .. "'"
end

-- Runs `cmd` and captures stdout. Returns `output, nil, code` when non-empty
-- stdout was produced, or `nil, err, code` when empty/failed (preserving
-- backward compatibility with existing callers expecting nil on empty output).
function external_tool.capture(cmd)
    handle = io.popen(cmd, "r")
    if handle == nil then
        return nil, "popen failed", -1
    end
    output = io.read(handle, "*all")
    ok, _, code = io.close(handle)
    if output == nil or output == "" then
        if not ok then
            return nil, "command exited with status " .. tostring(code), code
        end
        return nil, "no output", code
    end
    return output, nil, code
end

-- Runs `cmd` with combined stdout+stderr and returns `output, ok, code`
-- where `output` is always a string ("" when silent), `ok` is boolean,
-- and `code` is the numeric exit status or signal.
function external_tool.exec(cmd)
    handle = io.popen("{ " .. cmd .. "\n} 2>&1", "r")
    if handle == nil then
        return "", false, -1
    end
    output = io.read(handle, "*all")
    if output == nil then
        output = ""
    end
    ok, _, code = io.close(handle)
    return output, ok == true, code
end

function external_tool.ok(cmd)
    _, ok, _ = external_tool.exec(cmd)
    return ok
end

-- Runs `cmd` via `exec`, raising `what .. " failed:\n" .. out` at level 0
-- when `cmd` exits non-zero.
function external_tool.must(cmd, what)
    out, ok, _ = external_tool.exec(cmd)
    if not ok then
        label = what
        if label == nil or label == "" then
            label = cmd
        end
        error(label .. " failed:\n" .. out, 0)
    end
    return out
end

-- Runs `cmd` streaming directly to the terminal via `os.execute`.
-- Returns `ok, why, code`.
function external_tool.run(cmd)
    return os.execute(cmd)
end

-- True if `binary` resolves on PATH.
function external_tool.available(binary)
    if type(binary) != "string" or binary == "" then
        return false
    end
    return external_tool.ok("command -v " .. external_tool.shell_quote(binary))
end

-- Writes `content` to a fresh temp file (`mode` "w" or "wb"), calls
-- `fn(tmp_path)` inside `pcall`, and unconditionally removes the temp
-- file afterward whether `fn` returns normally or raises an error.
function external_tool.with_temp_file(content, mode, fn)
    tmp_path = os.tmpname()
    file = io.open(tmp_path, mode)
    if file == nil then
        return nil, "could not create a temp file"
    end
    ok_write, write_err = pcall(io.write, file, content)
    io.close(file)
    if not ok_write then
        os.remove(tmp_path)
        error(write_err, 0)
    end

    function invoke_with_path()
        return pack_varargs(fn(tmp_path))
    end
    ok_fn, packed_or_err = pcall(invoke_with_path)
    os.remove(tmp_path)
    if not ok_fn then
        error(packed_or_err, 0)
    end
    return unpack_varargs(packed_or_err)
end

return external_tool
