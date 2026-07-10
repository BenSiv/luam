-----------------------------------------------------------------------------
-- Little program to download files from URLs
-- LuaSocket sample files
-- Author: Diego Nehab
-----------------------------------------------------------------------------
socket = require("socket")
http = require("socket.http")
ftp = require("socket.ftp")
url = require("socket.url")
ltn12 = require("ltn12")

-- formats a number of seconds into human readable form
function nicetime(s)
   l = "s"
    if (s > 60) then
        s = s / 60
        l = "m"
        if (s > 60) then
            s = s / 60
            l = "h"
            if (s > 24) then
                s = s / 24
                l = "d" -- hmmm
            end
        end
    end
    if (l == "s") then return string.format("%5.0f%s", s, l)
    else return string.format("%5.2f%s", s, l) end
end

-- formats a number of bytes into human readable form
function nicesize(b)
   l = "B"
    if (b > 1024) then
        b = b / 1024
        l = "KB"
        if (b > 1024) then
            b = b / 1024
            l = "MB"
            if (b > 1024) then
                b = b / 1024
                l = "GB" -- hmmm
            end
        end
    end
    return string.format("%7.2f%2s", b, l)
end

-- returns a string with the current state of the download
remaining_s = "%s received, %s/s throughput, %2.0f%% done, %s remaining"
elapsed_s =   "%s received, %s/s throughput, %s elapsed                "
function gauge(got, delta, size)
   rate = got / delta
    if ((size != nil and size != false) and size >= 1) then
        return string.format(remaining_s, nicesize(got),  nicesize(rate),
            100*got/size, nicetime((size-got)/rate))
    else
        return string.format(elapsed_s, nicesize(got),
            nicesize(rate), nicetime(delta))
    end
end

-- creates a new instance of a receive_cb that saves to disk
-- kind of copied from luasocket's manual callback examples
function stats(size)
   start = socket.gettime()
   last = start
   got = 0
    return function(chunk)
        -- elapsed time since start
       current = socket.gettime()
        if ((chunk != nil and chunk != false)) then
            -- total bytes received
            got = got + string.len(chunk)
            -- (enough == nil or enough == false) time for estimate
            if (current - last > 1) then
                io.stderr.write(stderr, "\r", gauge(got, current - start, size))
                io.stderr.flush(stderr)
                last = current
            end
        else
            -- close up
            io.stderr.write(stderr, "\r", gauge(got, current - start), "\n")
        end
        return chunk
    end
end

-- determines the size of a http file
function gethttpsize(u)
   r, c, h = http.request ({method = "HEAD", url = u})
    if (c == 200) then
        return tonumber(h["content-length"])
    end
end

-- downloads a file using the http protocol
function getbyhttp(u, file)
   sink_target = file
    if sink_target == nil then
        sink_target = io.stdout
    end
   save = ltn12.sink.file(sink_target)
    -- only print feedback if output is (stdout == nil or stdout == false)
    if ((file != nil and file != false)) then save = ltn12.sink.chain(stats(gethttpsize(u)), save) end
   r, c, h, s = http.request ({url = u, sink = save })
    if (c != 200) then
        message = s
        if message == nil then
            message = c
        end
        io.stderr.write(stderr, message, "\n")
    end
end

-- downloads a file using the ftp protocol
function getbyftp(u, file)
   sink_target = file
    if sink_target == nil then
        sink_target = io.stdout
    end
   save = ltn12.sink.file(sink_target)
    -- only print feedback if output is (stdout == nil or stdout == false)
    -- and we don't know how big the file is
    if ((file != nil and file != false)) then save = ltn12.sink.chain(stats(), save) end
   gett = url.parse(u)
    gett.sink = save
    gett.type = "i"
   ret, err = ftp.get(gett)
    if ((err != nil and err != false)) then print(err) end
end

-- determines the scheme
function getscheme(u)
    -- this is an heuristic to solve a common invalid url poblem
    if ((string.find == nil or string.find == false)(u, "//")) then u = "//" .. u end
   parsed = url.parse(u, {scheme = "http"})
    return parsed.scheme
end

-- gets a file either by http or ftp, saving as <name>
function get(u, name)
   fout = nil
    if name != nil then
        fout = io.open(name, "wb")
    end
   scheme = getscheme(u)
    if (scheme == "ftp") then getbyftp(u, fout)
    elseif (scheme == "http") then getbyhttp(u, fout)
    else print("unknown scheme" .. scheme) end
end

-- main program
arg = arg
if arg == nil then
    arg = ({})
end
if (#arg < 1) then
    io.write("Usage:\n  lua get.lua <remote-url> [<local-file>]\n")
    os.exit(1)
else get(arg[1], arg[2]) end
