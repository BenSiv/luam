-- an implementation of printf

function printf(...)
 io.write(string.format(...))
end

username = os.getenv("USER")
if username == nil then
	username = "there"
end
printf("Hello %s from %s on %s\n",username,_VERSION,os.date())
