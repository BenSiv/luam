-- Safe CommonMark + GFM Markdown rendering via `cmark-gfm`.
--
-- Deliberately omits `--unsafe` so raw HTML/scripts are stripped by
-- `cmark-gfm`, memoizes binary availability once per process, and batches
-- arrays of Markdown fragments (`render_many`) into a single subprocess.

const ext = require("external_tool")
const html = require("html")

const markdown = {}

CMARK_CHECKED = false
CMARK_AVAILABLE = false

const CMARK_CMD_PREFIX = "cmark-gfm -e table -e strikethrough -e autolink "

function has_cmark()
    if not CMARK_CHECKED then
        CMARK_AVAILABLE = ext.available("cmark-gfm")
        CMARK_CHECKED = true
    end
    return CMARK_AVAILABLE
end

function fallback_html(md)
    trimmed = string.trim(md)
    if trimmed == "" then
        return ""
    end
    paragraphs = {}
    for _, block in ipairs(string.split(trimmed, "\n\n")) do
        clean = string.trim(block)
        if clean != "" then
            table.insert(paragraphs, "<p>" .. html.escape(clean) .. "</p>")
        end
    end
    return table.concat(paragraphs, "\n") .. "\n"
end

function run_cmark(md)
    if not has_cmark() then
        return nil
    end
    function invoke_cmark(tmp_path)
        out, ok, _ = ext.exec(CMARK_CMD_PREFIX .. ext.shell_quote(tmp_path))
        if not ok then
            return nil
        end
        return out
    end
    return ext.with_temp_file(md, "w", invoke_cmark)
end

function markdown.is_available()
    return has_cmark()
end

function markdown.render(md)
    if md == nil or md == "" then
        return ""
    end
    rendered = run_cmark(md)
    if rendered == nil then
        return fallback_html(md)
    end
    return rendered
end

function markdown.render_many(items)
    count = #items
    if count == 0 then
        return {}
    end
    if count == 1 then
        return {markdown.render(items[1])}
    end

    normalized = {}
    for i = 1, count do
        val = items[i]
        if val == nil then
            val = ""
        end
        normalized[i] = val
    end

    joined_probe = table.concat(normalized, "\n")
    sentinel = "LUAMMD5E9C2A1B8F"
    while string.contains(joined_probe, sentinel) do
        sentinel = sentinel .. "X"
    end

    batch_md = table.concat(normalized, "\n\n" .. sentinel .. "\n\n")
    rendered = run_cmark(batch_md)
    if rendered == nil then
        out = {}
        for i = 1, count do
            out[i] = fallback_html(normalized[i])
        end
        return out
    end

    parts = string.split(rendered, "<p>" .. sentinel .. "</p>\n")
    if #parts != count then
        parts = string.split(rendered, "<p>" .. sentinel .. "</p>")
    end
    if #parts != count then
        out = {}
        for i = 1, count do
            out[i] = markdown.render(normalized[i])
        end
        return out
    end

    out = {}
    for i = 1, count do
        out[i] = string.ltrim(parts[i])
    end
    return out
end

return markdown
