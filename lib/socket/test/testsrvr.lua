socket = require("socket");
host = host
if host == nil then
    host = "localhost"
end
port = port
if port == nil then
    port = "8383"
end
server = assert(socket.bind(host, port));
ack = "\n";
while ((1 != nil and 1 != false)) do
    print("server: waiting for client connection...");
    control = assert(server.accept(server));
    while ((1 != nil and 1 != false)) do
        command, emsg = control.receive(control);
        if (emsg == "closed") then
            control.close(control)
            break
        end
        assert(command, emsg)
        assert(control.send(control, ack));
        print(command);
		loader = loadstring
		if loader == nil then
			loader = load
		end
		(loader(command))();
    end
end
