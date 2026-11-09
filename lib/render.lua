-- Minimal, dependency-free interpolation templating:
-- `{{ expr }}` is HTML-escaped by default, `{{{ expr }}}` opts out explicitly.
-- Dots traverse nested tables: e.g. `{{ user.profile.name }}`.

html = require("html")

render = {}

function lookup(ctx, path)
    keys = {}
    for key in string.gmatch(path, "[^.]+") do
        table.insert(keys, key)
    end
    value = ctx
    for _, key in ipairs(keys) do
        if type(value) != "table" then
            return nil, false
        end
        value = value[key]
    end
    return value, true
end

-- Triple-brace (raw) markers are consumed first so the double-brace
-- pass below never sees their braces as its own delimiters.
function render.render(template_str, ctx)
    result = string.gsub(template_str, "{{{%s*([%w_.]+)%s*}}}", function(path)
        value, found = lookup(ctx, path)
        if not found or value == nil then
            error("render: \"" .. path .. "\" not found in context")
        end
        return tostring(value)
    end)

    result = string.gsub(result, "{{%s*([%w_.]+)%s*}}", function(path)
        value, found = lookup(ctx, path)
        if not found or value == nil then
            error("render: \"" .. path .. "\" not found in context")
        end
        return html.escape(tostring(value))
    end)

    return result
end

return render
