-----------------------------------------------------------------------------
-- Little program to convert to and from Base64
-- LuaSocket sample files
-- Author: Diego Nehab
-----------------------------------------------------------------------------
ltn12 = require("ltn12")
mime = require("mime")
source = ltn12.source.file(io.stdin)
sink = ltn12.sink.file(io.stdout)
convert = nil
if arg and arg[1] == '-d' then
    convert = mime.decode("base64")
else
   base64 = mime.encode("base64")
   wrap = mime.wrap()
    convert = ltn12.filter.chain(base64, wrap)
end
sink = ltn12.sink.chain(convert, sink)
ltn12.pump.all(source, sink)
