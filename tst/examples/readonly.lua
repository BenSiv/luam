-- make global variables readonly

f=function (t,i) error("cannot redefine global variable `"..i.."'",2) end
g={}
=getfenv()
setmetatable(g,{__index=,__newindex=f})
setfenv(1,g)

-- an example
rawset(g,"x",3)
x=2
y=1	-- cannot redefine `y'
