-- load our favourite library
dispatch = require("dispatch")
handler = dispatch.newhandler()

-- make sure the user knows how to invoke us
if #arg < 1 then
    print("Usage")
    print("    lua forward.lua <iport:ohost:oport> ...")
    os.exit(1)
end

-- function to move data from one socket to the other
function move(foo, bar)
   live = nil
    while 1 do
       data, error, partial = foo.receive(foo, 2048)
        live = data or error == "timeout"
        data = data or partial
       result, error = bar.send(bar, data)
        if not live or not result then
            foo.close(foo)
            bar.close(bar)
            break
        end
    end
end

-- for each tunnel, start a new server
for i, v in ipairs(arg) do
    -- capture forwarding parameters
   _, _, iport, ohost, oport = string.find(v, "([^:]+):([^:]+):([^:]+)")
    assert(iport, "invalid arguments")
    -- create our server socket
   server = assert(handler.tcp())
    assert(server.setoption(server, "reuseaddr", true))
    assert(server.bind(server, "*", iport))
    assert(server.listen(server, 32))
    -- handler for the server object loops accepting new connections
    handler.start(handler, function()
        while 1 do
           client = assert(server.accept(server))
            assert(client.settimeout(client, 0))
            -- for each new connection, start a new client handler
            handler.start(handler, function()
                -- handler tries to connect to peer
               peer = assert(handler.tcp())
                assert(peer.settimeout(peer, 0))
                assert(peer.connect(peer, ohost, oport))
                -- if sucessful, starts a new handler to send data from
                -- client to peer
                handler.start(handler, function()
                    move(client, peer)
                end)
                -- afte starting new handler, enter in loop sending data from
                -- peer to client
                move(peer, client)
            end)
        end
    end)
end

-- simply loop stepping the server
while 1 do
    handler.step(handler)
end
