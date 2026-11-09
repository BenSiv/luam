-- Context-aware HTML, attribute, JSON and JS escaping primitives.

html = {}

-- HTML body and attribute escaping.
function html.escape(s)
    s = tostring(s)
    s = string.gsub(s, "&", "&amp;")
    s = string.gsub(s, "<", "&lt;")
    s = string.gsub(s, ">", "&gt;")
    s = string.gsub(s, "\"", "&quot;")
    s = string.gsub(s, "'", "&#39;")
    return s
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
    s = string.gsub(s, "\\", "\\\\")
    s = string.gsub(s, "\"", "\\\"")
    s = string.gsub(s, "\r\n", "\\n")
    s = string.gsub(s, "\r", "\\n")
    s = string.gsub(s, "\n", "\\n")
    s = string.gsub(s, "<", "\\u003c")
    return s
end

return html
