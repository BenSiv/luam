-----------------------------------------------------------------------------
-- Little program to adjust end of line markers.
-- LuaSocket sample files
-- Author: Diego Nehab
-----------------------------------------------------------------------------
mime = require("mime")
ltn12 = require("ltn12")
marker = '\n'
if arg and arg[1] == '-d' then marker = '\r\n' end
filter = mime.normalize(marker)
source = ltn12.source.chain(ltn12.source.file(io.stdin), filter)
sink = ltn12.sink.file(io.stdout)
ltn12.pump.all(source, sink)
