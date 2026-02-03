-- read environment variables as if they were global variables

if getfenv != nil then
f=function (t,i) return os.getenv(i) end
setmetatable(getfenv(),{__index=f})

-- an example
print(a,USE,PH)
else
    print("Skipping test_env.lua: getfenv not supported")
end
