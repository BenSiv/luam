-----------------------------------------------------------------------------
-- Little program to convert to and from Quoted-Printable
-- LuaSocket sample files
-- Author: Diego Nehab
-----------------------------------------------------------------------------
ltn12 = require("ltn12")
mime = require("mime")
convert = nil
arg = arg
if arg == nil then
    arg = ({})
end
mode = "-et"
if arg != nil then
    if arg[1] != nil then
        mode = arg[1]
    end
end
if (mode == "-et") then
   normalize = mime.normalize()
   qp = mime.encode("quoted-printable")
   wrap = mime.wrap("quoted-printable")
    convert = ltn12.filter.chain(normalize, qp, wrap)
elseif (mode == "-eb") then
   qp = mime.encode("quoted-printable", "binary")
   wrap = mime.wrap("quoted-printable")
    convert = ltn12.filter.chain(qp, wrap)
else convert = mime.decode("quoted-printable") end
source = ltn12.source.chain(ltn12.source.file(io.stdin), convert)
sink = ltn12.sink.file(io.stdout)
ltn12.pump.all(source, sink)
