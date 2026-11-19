-- Zero-dependency CLI flag parser, subcommand router, and dedented help
-- formatter. Replaces `argparse.lua` without pulling in `dataframes` or `utils`.

const cli = {}

function normalize_help(text)
    if text == nil then
        return ""
    end
    return string.trim(string.dedent(text))
end

function format_flag_list(flags)
    if flags == nil or #flags == 0 then
        return ""
    end
    rows = {}
    max_left = 0
    for _, f in ipairs(flags) do
        parts = {}
        if f.short != nil and f.short != "" then
            table.insert(parts, "-" .. f.short)
        end
        if f.long != nil and f.long != "" then
            table.insert(parts, "--" .. f.long)
        end
        left = "  " .. table.concat(parts, ", ")
        kind = f.kind
        if kind == nil then
            kind = "string"
        end
        if kind != "boolean" then
            meta = f.metavar
            if meta == nil or meta == "" then
                meta = "<" .. kind .. ">"
            end
            left = left .. " " .. meta
        end
        if #left > max_left then
            max_left = #left
        end
        desc = f.desc
        if desc == nil then
            desc = ""
        end
        table.insert(rows, {left = left, desc = desc})
    end
    lines = {"Options:"}
    for _, r in ipairs(rows) do
        if r.desc != "" then
            pad = string.rep(" ", max_left - #r.left + 2)
            table.insert(lines, r.left .. pad .. r.desc)
        else
            table.insert(lines, r.left)
        end
    end
    return table.concat(lines, "\n")
end

-- Builds fast lookup maps for a flag specification list.
-- Each entry: {short="e", long="entry", kind="string"|"number"|"boolean"|"list",
--              default=..., required=bool, desc="...", key="..."}
function index_flags(flag_specs)
    by_token = {}
    ordered = {}
    if flag_specs != nil then
        for _, spec in ipairs(flag_specs) do
            entry = {
                short = spec.short,
                long = spec.long,
                kind = spec.kind,
                default = spec.default,
                required = spec.required == true,
                desc = spec.desc,
                metavar = spec.metavar,
                key = spec.key,
            }
            if entry.kind == nil then
                entry.kind = "string"
            end
            if entry.key == nil then
                if entry.long != nil and entry.long != "" then
                    entry.key = string.gsub(entry.long, "%-", "_")
                elseif entry.short != nil and entry.short != "" then
                    entry.key = entry.short
                end
            end
            if entry.short != nil and entry.short != "" then
                by_token["-" .. entry.short] = entry
            end
            if entry.long != nil and entry.long != "" then
                by_token["--" .. entry.long] = entry
            end
            table.insert(ordered, entry)
        end
    end
    return by_token, ordered
end

function convert_flag_value(raw, entry, flag_label)
    if entry.kind == "number" then
        num = tonumber(raw)
        if num == nil then
            return nil, "option '" .. flag_label .. "' expects a number, got '" .. tostring(raw) .. "'"
        end
        return num, nil
    end
    return raw, nil
end

-- Parses `argv` (array of strings, indices 1..#argv) against `flag_specs`.
-- Returns `opts, positionals, err`:
--   - If `-h` or `--help` is encountered (outside `--`), sets `opts.help = true`
--     and returns immediately without enforcing `required` flags.
--   - If `allow_version == true` and `--version` is encountered, sets
--     `opts.version = true` and returns immediately.
--   - On error, returns `nil, nil, err_string`.
function cli.parse_flags(argv, flag_specs, opts_cfg)
    by_token, ordered = index_flags(flag_specs)
    allow_version = opts_cfg != nil and opts_cfg.allow_version == true
    stop_on_positional = opts_cfg != nil and opts_cfg.stop_on_positional == true

    values = {}
    for _, entry in ipairs(ordered) do
        if entry.kind == "boolean" then
            if entry.default != nil then
                values[entry.key] = entry.default
            else
                values[entry.key] = false
            end
        elseif entry.kind == "list" then
            values[entry.key] = {}
        elseif entry.default != nil then
            values[entry.key] = entry.default
        end
    end

    positionals = {}
    i = 1
    n = 0
    if argv != nil then
        n = #argv
    end
    end_of_flags = false

    while i <= n do
        token = argv[i]
        if end_of_flags then
            table.insert(positionals, token)
            i = i + 1
        elseif token == "--" then
            end_of_flags = true
            i = i + 1
        elseif token == "-h" or token == "--help" then
            values.help = true
            return values, positionals, nil
        elseif allow_version and token == "--version" then
            values.version = true
            return values, positionals, nil
        elseif string.starts_with(token, "--") and #token > 2 then
            eq_pos = string.index_of(token, "=")
            flag_name = token
            inline_val = nil
            if eq_pos != nil then
                flag_name = string.sub(token, 1, eq_pos - 1)
                inline_val = string.sub(token, eq_pos + 1)
            end
            entry = by_token[flag_name]
            if entry == nil then
                return nil, nil, "unknown option '" .. flag_name .. "'"
            end
            if entry.kind == "boolean" then
                if inline_val != nil then
                    if inline_val == "true" or inline_val == "1" then
                        values[entry.key] = true
                    elseif inline_val == "false" or inline_val == "0" then
                        values[entry.key] = false
                    else
                        return nil, nil, "boolean option '" .. flag_name .. "' expects true or false"
                    end
                else
                    values[entry.key] = true
                end
                i = i + 1
            else
                raw_val = inline_val
                if raw_val == nil then
                    if i + 1 > n then
                        return nil, nil, "missing value for option '" .. flag_name .. "'"
                    end
                    i = i + 1
                    raw_val = argv[i]
                end
                conv, err = convert_flag_value(raw_val, entry, flag_name)
                if err != nil then
                    return nil, nil, err
                end
                if entry.kind == "list" then
                    table.insert(values[entry.key], conv)
                else
                    values[entry.key] = conv
                end
                i = i + 1
            end
        elseif string.starts_with(token, "-") and #token > 1 then
            entry = by_token[token]
            if entry == nil then
                return nil, nil, "unknown option '" .. token .. "'"
            end
            if entry.kind == "boolean" then
                values[entry.key] = true
                i = i + 1
            else
                if i + 1 > n then
                    return nil, nil, "missing value for option '" .. token .. "'"
                end
                i = i + 1
                conv, err = convert_flag_value(argv[i], entry, token)
                if err != nil then
                    return nil, nil, err
                end
                if entry.kind == "list" then
                    table.insert(values[entry.key], conv)
                else
                    values[entry.key] = conv
                end
                i = i + 1
            end
        else
            table.insert(positionals, token)
            i = i + 1
            if stop_on_positional then
                while i <= n do
                    table.insert(positionals, argv[i])
                    i = i + 1
                end
            end
        end
    end

    for _, entry in ipairs(ordered) do
        if entry.required then
            v = values[entry.key]
            if v == nil or (entry.kind == "list" and #v == 0) then
                label = entry.long
                if label != nil and label != "" then
                    label = "--" .. label
                else
                    label = "-" .. tostring(entry.short)
                end
                return nil, nil, "missing required option '" .. label .. "'"
            end
        end
    end

    return values, positionals, nil
end

function cli.render_help(help_text, flag_specs)
    body = normalize_help(help_text)
    flags_block = format_flag_list(flag_specs)
    if body != "" and flags_block != "" then
        return body .. "\n\n" .. flags_block
    end
    if body != "" then
        return body
    end
    return flags_block
end

function slice_argv(argv, start_idx)
    out = {}
    if argv == nil then
        return out
    end
    i = start_idx
    while i <= #argv do
        table.insert(out, argv[i])
        i = i + 1
    end
    return out
end

-- Dispatches a multi-command CLI specification (`app`):
--   app = {
--     name = "tool",
--     version = "0.1.0",             -- optional string
--     help = "...",                  -- top-level help text
--     flags = {...},                 -- optional flags when no subcommands or default run
--     run = function(opts, args),    -- optional handler when no subcommands
--     commands = {
--       build = {
--         help = "...",
--         flags = {...},
--         run = function(opts, args),
--         commands = { ... },        -- optional nested subcommands
--       },
--     },
--   }
-- Returns `(exit_code, output_or_err)` when `app.no_exit == true`, else exits/returns handler result.
function cli.run(app, argv)
    args_in = argv
    if args_in == nil then
        args_in = arg
    end

    function finish(code, msg, to_stderr)
        if msg != nil and msg != "" and app.silent != true then
            stream = io.stdout
            if to_stderr == true then
                stream = io.stderr
            end
            io.write(stream, msg .. "\n")
        end
        if app.no_exit == true then
            return code, msg
        end
        os.exit(code)
    end

    if app.commands == nil then
        opts, pos, err = cli.parse_flags(args_in, app.flags, {allow_version = app.version != nil})
        if err != nil then
            return finish(1, "Error: " .. err .. "\n\n" .. cli.render_help(app.help, app.flags), true)
        end
        if opts.help == true then
            return finish(0, cli.render_help(app.help, app.flags), false)
        end
        if opts.version == true and app.version != nil then
            return finish(0, app.version, false)
        end
        if app.run != nil then
            return app.run(opts, pos)
        end
        return 0, nil
    end

    node = app
    idx = 1
    n = 0
    if args_in != nil then
        n = #args_in
    end

    -- Top-level empty / help / version handling
    if n == 0 then
        if node.run != nil then
            return node.run({}, {})
        end
        return finish(1, cli.render_help(node.help, node.flags), true)
    end

    first = args_in[1]
    if first == "-h" or first == "--help" then
        return finish(0, cli.render_help(node.help, node.flags), false)
    end
    if (first == "--version" or first == "-V" or (first == "version" and node.commands["version"] == nil)) and app.version != nil then
        return finish(0, app.version, false)
    end
    if first == "help" and node.commands["help"] == nil then
        if n == 1 then
            return finish(0, cli.render_help(node.help, node.flags), false)
        end
        target = node
        j = 2
        while j <= n and target.commands != nil and target.commands[args_in[j]] != nil do
            target = target.commands[args_in[j]]
            j = j + 1
        end
        if target == node then
            return finish(1, "Unknown command '" .. tostring(args_in[2]) .. "'\n\n" .. cli.render_help(node.help, node.flags), true)
        end
        return finish(0, cli.render_help(target.help, target.flags), false)
    end

    -- Walk nested subcommands
    cmd_path = {app.name}
    while idx <= n and node.commands != nil do
        tok = args_in[idx]
        if tok == "-h" or tok == "--help" then
            return finish(0, cli.render_help(node.help, node.flags), false)
        end
        sub = node.commands[tok]
        if sub == nil then
            if idx == 1 then
                return finish(1, "Unknown command '" .. tok .. "'\n\n" .. cli.render_help(node.help, node.flags), true)
            end
            break
        end
        table.insert(cmd_path, tok)
        node = sub
        idx = idx + 1
    end

    rest = slice_argv(args_in, idx)
    if node.commands != nil and node.run == nil and (#rest == 0 or rest[1] == "-h" or rest[1] == "--help") then
        code_out = 0
        if #rest == 0 then
            code_out = 1
        end
        return finish(code_out, cli.render_help(node.help, node.flags), code_out != 0)
    end
    if node.commands != nil and node.run == nil and #rest > 0 then
        return finish(1, "Unknown subcommand '" .. tostring(rest[1]) .. "' for '" .. table.concat(cmd_path, " ") .. "'\n\n" .. cli.render_help(node.help, node.flags), true)
    end

    if node.raw_args == true then
        for _, rtok in ipairs(rest) do
            if rtok == "-h" or rtok == "--help" then
                return finish(0, cli.render_help(node.help, node.flags), false)
            end
            if rtok == "--" then
                break
            end
        end
        return node.run({}, rest)
    end

    opts, pos, err = cli.parse_flags(rest, node.flags, {allow_version = false})
    if err != nil then
        return finish(1, "Error: " .. err .. "\n\n" .. cli.render_help(node.help, node.flags), true)
    end
    if opts.help == true then
        return finish(0, cli.render_help(node.help, node.flags), false)
    end
    return node.run(opts, pos)
end

return cli
