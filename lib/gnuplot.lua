-- mygnuplot_procedural.lua

exec_command = require("utils").exec_command

gnuplot = {}

temp_files = {}

function write_temp_file(content)
    fname = os.tmpname()
    f = io.open(fname, "w")
    f.write(f, content)
    f.close(f)
    table.insert(temp_files, fname)
    return fname
end

-- convert Lua arrays to temporary data file
function array_to_file(arr)
    -- arr should be { {x1, x2, ...}, {y1, y2, ...}, ... }
    assert(#arr > 0, "nput array is empty")
    n = #arr[1]  -- number of points
    lines = {}
    
    for i = 1, n do
        line = {}
        for j = 1, #arr do
            v = arr[j][i]
            if type(v) == "string" then
                v = v.gsub(v, '"', '')  -- remove quotes if present
            end
            line[j] = v != nil and tostring(v) or "a"
        end
        table.insert(lines, table.concat(line, " "))
    end
    
    -- write to temporary file
    tmpname = os.tmpname()
    f = assert(io.open(tmpname, "w"))
    f.write(f, table.concat(lines, "\n"))
    f.close(f)
    return tmpname
end

-- create a plot object (data + config)
function create(cfg)
    cfg = cfg or {}
    plot = {}
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
    cfg = plot.cfg
    code = {}

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
        xr = cfg.xrange
        if type(xr) == "table" then
            table.insert(code, string.format("set xrange [%s:%s]", xr[1], xr[2]))
        else
            table.insert(code, "set xrange " .. xr)
        end
    end

    if cfg.yrange then
        yr = cfg.yrange
        if type(yr) == "table" then
            table.insert(code, string.format("set yrange [%s:%s]", yr[1], yr[2]))
        else
            table.insert(code, "set yrange " .. yr)
        end
    end

    -- plot command
    plots = {}
    for _, d in ipairs(cfg.data) do
        line = '"'..d[1]..'"'
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
--     code = generate_code(plot, "plot", output_path)
--     tmp = write_temp_file(code)
--     os.execute("gnuplot " .. tmp)
-- end

function savefig(plot, output_path)
    code = generate_code(plot, "plot", output_path)
    tmp = write_temp_file(code)
    
    -- Use exec_command instead of os.execute
    output, ok = exec_command("gnuplot " .. tmp)
    
    if not ok then
        return false, output, tmp  -- Failed: return false + gnuplot output
    end
    
    return true, output, tmp       -- Success: return true + gnuplot output
end

gnuplot.create = create
gnuplot.savefig = savefig
gnuplot.generate_code = generate_code

return gnuplot
