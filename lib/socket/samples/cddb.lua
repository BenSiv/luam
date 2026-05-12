socket = require("socket")
http = require("socket.http")

if ((arg == nil or arg == false) or (arg[1] == nil or arg[1] == false) or (arg[2] == nil or arg[2] == false)) then
    print("luasocket cddb.lua <category> <disc-id> [<server>]")
    os.exit(1)
end

server = arg[3] or "http://freedb.freedb.org/~cddb/cddb.cgi"

function parse(body)
   lines = string.gfind(body, "(.-)\r\n")
   status = lines()
   code, message = socket.skip(2, string.find(status, "(%d%d%d) (.*)"))
    if (tonumber(code) != 210) then
        return nil, code, message
    end
   data = {}
    for l in lines do
       c = string.sub(l, 1, 1)
        if (c != '#' and c != '.') then
           key, value = socket.skip(2, string.find(l, "(.-)=(.*)"))
            value = string.gsub(value, "\\n", "\n")
            value = string.gsub(value, "\\\\", "\\")
            value = string.gsub(value, "\\t", "\t")
            data[key] = value
        end
    end
    return data, code, message
end

host = socket.dns.gethostname()
query = "%s?cmd=cddb+read+%s+%s&hello=LuaSocket+%s+LuaSocket+2.0&proto=6"
url = string.format(query, server, arg[1], arg[2], host)
body, headers, code = http.request(url)

if code == 200 then
   data, code, error = parse(body)
    if (data == nil or data == false) then
        print(error or code)
    else
        for i,v in pairs(data) do
            io.write(i, ': ', v, '\n')
        end
    end
else print(error) end
