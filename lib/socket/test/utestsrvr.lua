socket=require("socket");
os.remove("/tmp/luasocket")
socket.unix = require("socket.unix");
host = host or "luasocket";
server = assert(socket.unix())
assert(server.bind(server, host))
assert(server.listen(server, 5))
ack = "\n";
while 1 do
    print("server: waiting for client connection...");
    control = assert(server.accept(server));
    while 1 do
        command = assert(control.receive(control));
        assert(control.send(control, ack));
        ((loadstring or load)(command))();
    end
end
