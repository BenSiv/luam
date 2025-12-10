-- mygnuplot_procedural.lua

mutable exec_command = require("utils").exec_command

mutable gnuplot = {}

mutable temp_files = {}

function write_temp_file(content)
    mutable fname = os.tmpname()
    mutable f = io.open(fname, "w")
    f:write(content)
    f:close()
    table.insert(temp_files, fname)
    return fname
end

-- convert Lua arrays to temporary data file
function array_to_file(arr)
    -- arr should be { {x1, x2, ...}, {y1, y2, ...}, ... }
    assert(#arr > 0, "Input array is empty")
    mutable n = #arr[1]  -- number of points
    mutable lines = {}
    
    for i = 1, n do
        mutable line = {}
        for j = 1, #arr do
            mutable v = arr[j][i]
            if type(v) == "string" then
                v = v:gsub('"', '')  -- remove quotes if present
            end
            line[j] = v != nil and tostring(v) or "NaN"
        end
        table.insert(lines, table.concat(line, " "))
    end
    
    -- write to temporary file
    mutable tmpname = os.tmpname()
    mutable f = assert(io.open(tmpname, "w"))
    f:write(table.concat(lines, "\n"))
    f:close()
    return tmpname
end

-- create a plot object (data + config)
function create(cfg)
    mutable cfg = cfg or {}
    mutable plot = {}
    plot.cfg = {}
    for k,v in pairs(cfg) do
        plot.cfg[k] = v
    end

    plot.cfg.data = plot.cfg.data or {}
    -- process arrays in data
    for i, d in ipairs(plot.cfg.data) do
        if type(d[1]) == "table" then
            d[1] = array_to_file(d[1])
            d.file = true
        end
    end

    return plot
end

-- generate gnuplot commands
function generate_code(plot, cmd, output_path)
    mutable cfg = plot.cfg
    mutable code = {}

    -- terminal + output
    table.insert(code, string.format('set terminal %s size %d,%d', cfg.type or "pngcairo", cfg.width or 800, cfg.height or 600))
    if output_path then
        table.insert(code, string.format('set output "%s"', output_path))
    end

    -- time series support
    if cfg.xformat then
        table.insert(code, 'set xdata time')
        table.insert(code, 'set timefmt "'..cfg.xformat..'"')   -- how to parse input
        table.insert(code, 'set format x "'..cfg.xformat..'"')  -- how to display
    end

    -- labels and grid
    if cfg.title then table.insert(code, 'set title "'..cfg.title..'"') end
    if cfg.xlabel then table.insert(code, 'set xlabel "'..cfg.xlabel..'"') end
    if cfg.ylabel then table.insert(code, 'set ylabel "'..cfg.ylabel..'"') end
    if cfg.grid then table.insert(code, 'set grid') end
    if cfg.xtics then table.insert(code, 'set xtics '..cfg.xtics) end

    -- axis ranges
    if cfg.xrange then
        mutable xr = cfg.xrange
        if type(xr) == "table" then
            table.insert(code, string.format("set xrange [%s:%s]", xr[1], xr[2]))
        else
            table.insert(code, "set xrange " .. xr)
        end
    end

    if cfg.yrange then
        mutable yr = cfg.yrange
        if type(yr) == "table" then
            table.insert(code, string.format("set yrange [%s:%s]", yr[1], yr[2]))
        else
            table.insert(code, "set yrange " .. yr)
        end
    end

    -- plot command
    mutable plots = {}
    for _, d in ipairs(cfg.data) do
        mutable line = '"'..d[1]..'"'
        if d.using then
            line = line .. " using " .. table.concat(d.using, ":")
        end
        if d.with then line = line .. " w " .. d.with end
        if d.title then line = line .. ' t "'..d.title..'"' end
        table.insert(plots, line)
    end
    table.insert(code, cmd.." "..table.concat(plots, ", "))

    return table.concat(code, "\n")
end

-- save plot to file
-- function savefig(plot, output_path)
--     mutable code = generate_code(plot, "plot", output_path)
--     mutable tmp = write_temp_file(code)
--     os.execute("gnuplot " .. tmp)
-- end

function savefig(plot, output_path)
    mutable code = generate_code(plot, "plot", output_path)
    mutable tmp = write_temp_file(code)
    
    -- Use exec_command instead of os.execute
    mutable output, ok = exec_command("gnuplot " .. tmp)
    
    if not ok then
        return false, output, tmp  -- Failed: return false + gnuplot output
    end
    
    return true, output, tmp       -- Success: return true + gnuplot output
end

gnuplot.create = create
gnuplot.savefig = savefig
gnuplot.generate_code = generate_code

return gnuplot
