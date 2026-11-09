-- Shared shape behind every "shell out to an external binary" call
-- site in this codebase (cmark-gfm, pdftotext/pandoc, curl, etc.)
-- Quoting, temp-file lifecycle, and capturing a command's stdout.

external_tool = {}

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
-- `fn(tmp_path)` -- which should itself return (result, err) -- and
-- unconditionally removes the temp file afterward, on success or failure alike.
function external_tool.with_temp_file(content, mode, fn)
    tmp_path = os.tmpname()
    file = io.open(tmp_path, mode)
    if file == nil then
        return nil, "could not create a temp file"
    end
    io.write(file, content)
    io.close(file)

    result, err = fn(tmp_path)
    os.remove(tmp_path)
    return result, err
end

return external_tool
