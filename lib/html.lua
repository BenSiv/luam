-- Context-aware HTML, attribute, JSON and JS escaping primitives.

html = {}

HTML_ESCAPE_MAP = {
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ["\""] = "&quot;",
    ["'"] = "&#39;",
}

JS_ESCAPE_MAP = {
    ["\\"] = "\\\\",
    ["\""] = "\\\"",
    ["\r"] = "\\n",
    ["\n"] = "\\n",
    ["<"] = "\\u003c",
}

-- HTML body and attribute escaping.
function html.escape(s)
    return (string.gsub(tostring(s), "[&<>\"']", HTML_ESCAPE_MAP))
end

-- Backward compatibility alias for daat
html.html_escape = html.escape

-- Escapes an already JSON-encoded string for safe embedding inside an inline <script> tag.
-- Prevents literal "</script>" in JSON strings from closing the surrounding script block.
function html.json_for_script(json_string)
    return (string.gsub(json_string, "<", "\\u003c"))
end

-- Escapes a plain string for safe embedding directly into a JavaScript string literal.
function html.js_string_literal(s)
    s = tostring(s)
    if string.find(s, "\r", 1, true) != nil then
        s = string.gsub(s, "\r\n", "\n")
    end
    return (string.gsub(s, "[\\\"\r\n<]", JS_ESCAPE_MAP))
end

return html
