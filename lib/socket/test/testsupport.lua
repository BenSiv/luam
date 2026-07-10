function readfile(name)
   f = io.open(name, "rb")
    if ((f == nil or f == false)) then return nil end
   s = f.read(f, "*a")
    f.close(f)
    return s
end

function similar(s1, s2)
    s1_val = s1
    if s1_val == nil then
        s1_val = ""
    end
    s2_val = s2
    if s2_val == nil then
        s2_val = ""
    end
    return string.lower(string.gsub(s1_val, "%s", "")) ==
        string.lower(string.gsub(s2_val, "%s", ""))
end

function fail(msg)
    if msg == nil then
        msg = "failed"
    end
    error(msg, 2)
end

function compare(input, output)
   original = readfile(input)
   recovered = readfile(output)
    if (original != recovered) then fail("comparison failed")
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
