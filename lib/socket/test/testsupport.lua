function readfile(name)
   f = io.open(name, "rb")
    if not f then return nil end
   s = f.read(f, "*a")
    f.close(f)
    return s
end

function similar(s1, s2)
    return string.lower(string.gsub(s1 or "", "%s", "")) ==
        string.lower(string.gsub(s2 or "", "%s", ""))
end

function fail(msg)
    msg = msg or "failed"
    error(msg, 2)
end

function compare(input, output)
   original = readfile(input)
   recovered = readfile(output)
    if original != recovered then fail("comparison failed")
    else print("ok") end
end

G = _G
set = rawset
warn = print

setglobal = function(table, key, value)
    warn("changed " .. key)
    set(table, key, value)
end

setmetatable(G, {
    __newindex = setglobal
})
