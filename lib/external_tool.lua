-- Shared shape behind every "shell out to an external binary" call
-- site in this codebase (cmark-gfm, pdftotext/pandoc, curl, etc.)
-- Quoting, temp-file lifecycle, and capturing a command's stdout.

external_tool = {}

function pack_varargs(...)
    return {n = select("#", ...), ...}
end

function unpack_varargs(packed)
    if packed == nil or packed.n == 0 then
        return
    end
    if unpack != nil then
        return unpack(packed, 1, packed.n)
    end
    return table.unpack(packed, 1, packed.n)
end

function external_tool.shell_quote(s)
    return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

-- Runs `cmd` (a fully-built shell command string -- every interpolated
-- value already shell_quote'd by the caller) and returns all of its
-- stdout, or nil, err if the popen itself failed or produced no
-- output. stderr is never captured -- a caller that wants it
-- suppressed adds " 2>/dev/null" to `cmd` itself.
function external_tool.capture(cmd)
    handle = io.popen(cmd, "r")
    output = nil
    if handle != nil then
        output = io.read(handle, "*all")
        io.close(handle)
    end
    if output == nil or output == "" then
        return nil, "no output"
    end
    return output
end

-- True if `binary` resolves on PATH. Lets a caller check up front for
-- a clean, specific "X is not installed" error instead of io.popen's
-- underlying shell silently reporting "command not found" on stderr
-- while stdout comes back empty or garbled.
function external_tool.available(binary)
    found, _ = external_tool.capture("command -v " .. external_tool.shell_quote(binary) .. " 2>/dev/null")
    return found != nil
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
