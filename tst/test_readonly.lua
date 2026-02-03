-- make global variables readonly

if getfenv != nil then
f=function (t,i) error("cannot redefine global variable `"..i.."'",2) end
g={}
t=getfenv()
setmetatable(g,{__index=t,__newindex=f})
setfenv(1,g)

-- an example
rawset(g,"x",3)
x=2
y=1	-- cannot redefine `y'
else
    print("Skipping test_readonly.lua: getfenv not supported")
end
