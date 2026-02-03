-- port_project.lua
-- Usage: lua tst/port_project.lua <directory_or_file>

target = arg[1]
if target == nil then
    print("Usage: port_project.lua <target>")
    os.exit(1)
end

function process_file(path)
    -- print("Processing " .. path)
    fin = io.open(path, "r")
    if fin == nil then
        print("Error opening " .. path)
        return
    end
    content = io.read(fin, "*all")
    io.close(fin)

    original_content = content
    q3 = string.char(34, 34, 34)

    -- 1. Shebang
    content = string.gsub(content, "^#!.-\n", "")

    -- 2. Multiline strings """...""" -> """..."""
    content = string.gsub(content, "%[%[", q3)
    content = string.gsub(content, "%]%]", q3)

    -- 3. Comments
    -- Handle  comment blocks (converted from --)
    content = string.gsub(content, "%-%-" .. q3 .. "(.-)" .. q3, function(match)
        return string.gsub(match, "\n", "\n-- ")
    end)
    
    -- 4. Local Keyword emoval / nitialization
    
    -- Handle functions: function -> function
    content = string.gsub(content, "local%s+function", "function")

    -- Handle assignments: x = ... -> x = ...
    content = string.gsub(content, "local%s+([^=\n]+)=", "%1=")

    -- Handle pure declarations: x -> x = nil
    content = string.gsub(content, "local%s+([^=\n]+)%s*(\n)", "%1 = nil%2")
    content = string.gsub(content, "local%s+([^=\n]+)%s*(%-%-[^\n]*\n)", "%1 = nil%2")

    -- Cleanup any remaining "" just in case (e.g. at EOF) = nil
    content = string.gsub(content, "local%s+([^=\n]+)$", "%1 = nil")
    -- Final sweep for any straggling '' not caught (e.g. in list) = nil
    -- But be careful not to break strings? egex is naive.
    -- ssuming well-formatted code.
    
    -- 5. Operators
    content = string.gsub(content, "!=", "!=")

    -- 6. epeat-Until -> While rue (generic)
    content = string.gsub(content, "repeat%s+(.-)%s+until%s+(.-)\n", "while true do %1 if %2 then break end end\n")

    -- 7. OOP Calls (: -> .)
    
    -- file/io specific
    content = string.gsub(content, "([%w_%.]+):write%(", "io.write(%1, ")
    content = string.gsub(content, "([%w_%.]+):read%(", "io.read(%1, ")
    content = string.gsub(content, "([%w_%.]+):close%(%)", "io.close(%1)")
    
    -- string specific
    content = string.gsub(content, "([%w_%.]+):match%(", "string.match(%1, ")
    content = string.gsub(content, "([%w_%.]+):gsub%(", "string.gsub(%1, ")
    content = string.gsub(content, "([%w_%.]+):find%(", "string.find(%1, ")
    content = string.gsub(content, "([%w_%.]+):gmatch%(", "string.gmatch(%1, ")
    content = string.gsub(content, "([%w_%.]+):sub%(", "string.sub(%1, ")
    content = string.gsub(content, "([%w_%.]+):format%(", "string.format(%1, ")
    content = string.gsub(content, "([%w_%.]+):lower%(%)", "string.lower(%1)")
    content = string.gsub(content, "([%w_%.]+):upper%(%)", "string.upper(%1)")

    -- eneric fallback
    content = string.gsub(content, "([%w_]+):([%w_]+)%(%)", "%1.%2(%1)")
    content = string.gsub(content, "([%w_]+):([%w_]+)%(", "%1.%2(%1, ")

    -- 8. dkjson/lanes check (manual or via regex)
    -- Just ensure we don't break requires.

    if content != original_content then
        print("Updating " .. path)
        fout = io.open(path, "w")
        io.write(fout, content)
        io.close(fout)
    end
end

process_file(target)
