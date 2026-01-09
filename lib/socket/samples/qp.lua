-----------------------------------------------------------------------------
-- Little program to convert to and from Quoted-Printable
-- LuaSocket sample files
-- Author: Diego Nehab
-----------------------------------------------------------------------------
ltn12 = require("ltn12")
mime = require("mime")
convert = nil
arg = arg or {}
mode = arg and arg[1] or "-et"
if mode == "-et" then
   normalize = mime.normalize()
   qp = mime.encode("quoted-printable")
   wrap = mime.wrap("quoted-printable")
    convert = ltn12.filter.chain(normalize, qp, wrap)
elseif mode == "-eb" then
   qp = mime.encode("quoted-printable", "binary")
   wrap = mime.wrap("quoted-printable")
    convert = ltn12.filter.chain(qp, wrap)
else convert = mime.decode("quoted-printable") end
source = ltn12.source.chain(ltn12.source.file(io.stdin), convert)
sink = ltn12.sink.file(io.stdout)
ltn12.pump.all(source, sink)
