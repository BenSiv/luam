-- mygnuplot_procedural.lua

const ext = require("external_tool")

gnuplot = {}

function write_temp_file(content)
    fname = os.tmpname()
    f = assert(io.open(fname, "w"))
    io.write(f, content)
    io.close(f)
    return fname
end

-- convert Lua arrays to temporary data file
function array_to_file(arr)
    -- arr should be { {x1, x2, ...}, {y1, y2, ...}, ... }
    assert(#arr > 0, "Input array is empty")
    n = #arr[1]  -- number of points
    lines = {}

    for i = 1, n do
        line = {}
        for j = 1, #arr do
            v = arr[j][i]
            if (type(v) == "string") then
                v = string.gsub(v, "\"", "")  -- remove quotes if present
            end
            if (v != nil) then
                line[j] = tostring(v)
            else
                line[j] = "a"
            end
        end
        table.insert(lines, table.concat(line, " "))
    end

    -- write to temporary file
    tmpname = os.tmpname()
    f = assert(io.open(tmpname, "w"))
    io.write(f, table.concat(lines, "\n"))
    io.close(f)
    return tmpname
end

-- Removes all temporary series data files created by `gnuplot.create`.
function cleanup(plot)
    if plot == nil or type(plot._temp_files) != "table" then
        return
    end
    for _, fname in ipairs(plot._temp_files) do
        os.remove(fname)
    end
    plot._temp_files = {}
end

-- create a plot object (data + config) without mutating caller's series tables
function create(cfg)
    if (cfg == nil) then
        cfg = {}
    end
    plot = {}
    plot.cfg = {}
    plot._temp_files = {}
    for k, v in pairs(cfg) do
        plot.cfg[k] = v
    end

    raw_data = cfg.data
    if (raw_data == nil) then
        raw_data = {}
    end
    plot_data = {}
    function build_series_files()
        for i, d in ipairs(raw_data) do
            d_copy = {}
            for dk, dv in pairs(d) do
                d_copy[dk] = dv
            end
            if (type(d_copy[1]) == "table") then
                data_path = array_to_file(d_copy[1])
                table.insert(plot._temp_files, data_path)
                d_copy[1] = data_path
                d_copy.file = true
            end
            plot_data[i] = d_copy
        end
    end
    ok_build, build_err = pcall(build_series_files)
    if not ok_build then
        cleanup(plot)
        error(build_err, 0)
    end
    plot.cfg.data = plot_data

    return plot
end

-- generate gnuplot commands
function generate_code(plot, cmd, output_path)
    cfg = plot.cfg
    code = {}

    -- terminal + output
    term_type = cfg.type
    if (term_type == nil) then
        term_type = "pngcairo"
    end
    term_width = cfg.width
    if (term_width == nil) then
        term_width = 800
    end
    term_height = cfg.height
    if (term_height == nil) then
        term_height = 600
    end
    table.insert(code, string.format("set terminal %s size %d,%d", term_type, term_width, term_height))
    if ((output_path != nil and output_path != false)) then
        table.insert(code, string.format("set output \"%s\"", output_path))
    end

    -- time series support
    if ((cfg.xformat != nil and cfg.xformat != false)) then
        table.insert(code, "set xdata time")
        table.insert(code, "set timefmt \"" .. cfg.xformat .. "\"")
        table.insert(code, "set format x \"" .. cfg.xformat .. "\"")
    end

    -- labels and grid
    if ((cfg.title != nil and cfg.title != false)) then table.insert(code, "set title \"" .. cfg.title .. "\"") end
    if ((cfg.xlabel != nil and cfg.xlabel != false)) then table.insert(code, "set xlabel \"" .. cfg.xlabel .. "\"") end
    if ((cfg.ylabel != nil and cfg.ylabel != false)) then table.insert(code, "set ylabel \"" .. cfg.ylabel .. "\"") end
    if ((cfg.grid != nil and cfg.grid != false)) then table.insert(code, "set grid") end
    if ((cfg.xtics != nil and cfg.xtics != false)) then table.insert(code, "set xtics " .. cfg.xtics) end

    -- axis ranges
    if ((cfg.xrange != nil and cfg.xrange != false)) then
        xr = cfg.xrange
        if (type(xr) == "table") then
            table.insert(code, string.format("set xrange [%s:%s]", xr[1], xr[2]))
        else
            table.insert(code, "set xrange " .. xr)
        end
    end

    if ((cfg.yrange != nil and cfg.yrange != false)) then
        yr = cfg.yrange
        if (type(yr) == "table") then
            table.insert(code, string.format("set yrange [%s:%s]", yr[1], yr[2]))
        else
            table.insert(code, "set yrange " .. yr)
        end
    end

    -- plot command
    plots = {}
    for _, d in ipairs(cfg.data) do
        line = "\"" .. d[1] .. "\""
        if ((d.using != nil and d.using != false)) then
            line = line .. " using " .. table.concat(d.using, ":")
        end
        if ((d.with != nil and d.with != false)) then line = line .. " w " .. d.with end
        if ((d.title != nil and d.title != false)) then line = line .. " t \"" .. d.title .. "\"" end
        table.insert(plots, line)
    end
    table.insert(code, cmd .. " " .. table.concat(plots, ", "))

    return table.concat(code, "\n")
end

function savefig(plot, output_path)
    code = generate_code(plot, "plot", output_path)
    tmp = write_temp_file(code)

    function run_gnuplot()
        out, ok, _ = ext.exec("gnuplot " .. tmp)
        return out, ok
    end
    call_ok, output, cmd_ok = pcall(run_gnuplot)

    if plot.cfg == nil or plot.cfg.keep_temp_files != true then
        os.remove(tmp)
        cleanup(plot)
    end

    if not call_ok then
        error(output, 0)
    end
    if ((cmd_ok == nil or cmd_ok == false)) then
        return false, output, tmp  -- Failed: return false + gnuplot output
    end

    return true, output, tmp       -- Success: return true + gnuplot output
end

gnuplot.create = create
gnuplot.savefig = savefig
gnuplot.generate_code = generate_code
gnuplot.cleanup = cleanup

return gnuplot
