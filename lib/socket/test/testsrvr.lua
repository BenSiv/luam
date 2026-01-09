socket = require("socket");
host = host or "localhost";
port = port or "8383";
server = assert(socket.bind(host, port));
ack = "\n";
while 1 do
    print("server: waiting for client connection...");
    control = assert(server.accept(server));
    while 1 do
        command, emsg = control.receive(control);
        if emsg == "closed" then
            control.close(control)
            break
        end
        assert(command, emsg)
        assert(control.send(control, ack));
        print(command);
		((loadstring or load)(command))();
    end
end
