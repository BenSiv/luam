socket=require("socket");
os.remove("/tmp/luasocket")
socket.unix = require("socket.unix");
host = host
if host == nil then
    host = "luasocket"
end
server = assert(socket.unix())
assert(server.bind(server, host))
assert(server.listen(server, 5))
ack = "\n";
while ((1 != nil and 1 != false)) do
    print("server: waiting for client connection...");
    control = assert(server.accept(server));
    while ((1 != nil and 1 != false)) do
        command = assert(control.receive(control));
        assert(control.send(control, ack));
        loader = loadstring
        if loader == nil then
            loader = load
        end
        (loader(command))();
    end
end
