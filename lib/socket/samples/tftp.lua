-----------------------------------------------------------------------------
-- TFTP support for the Lua language
-- LuaSocket toolkit.
-- Author: Diego Nehab
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Load required files
-----------------------------------------------------------------------------
base = _G
table = require("table")
math = require("math")
string = require("string")
socket = require("socket")
ltn12 = require("ltn12")
url = require("socket.url")
module("socket.tftp")

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
char = string.char
byte = string.byte

PORT = 69
OP_RRQ = 1
OP_WRQ = 2
OP_DATA = 3
OP_ACK = 4
OP_ERROR = 5
OP_INV = {"RRQ", "WRQ", "DATA", "ACK", "ERROR"}

-----------------------------------------------------------------------------
-- Packet creation functions
-----------------------------------------------------------------------------
function RRQ(source, mode)
    return char(0, OP_RRQ) .. source .. char(0) .. mode .. char(0)
end

function WRQ(source, mode)
    return char(0, OP_RRQ) .. source .. char(0) .. mode .. char(0)
end

function ACK(block)
   low, high = nil
    low = math.mod(block, 256)
    high = (block - low)/256
    return char(0, OP_ACK, high, low)
end

function get_OP(dgram)
   op = byte(dgram, 1)*256 + byte(dgram, 2)
    return op
end

-----------------------------------------------------------------------------
-- Packet analysis functions
-----------------------------------------------------------------------------
function split_DATA(dgram)
   block = byte(dgram, 3)*256 + byte(dgram, 4)
   data = string.sub(dgram, 5)
    return block, data
end

function get_ERROR(dgram)
   code = byte(dgram, 3)*256 + byte(dgram, 4)
   msg = nil
    _,_, msg = string.find(dgram, "(.*)\000", 5)
    return string.format("error code %d: %s", code, msg)
end

-----------------------------------------------------------------------------
-- The real work
-----------------------------------------------------------------------------
function tget(gett)
   retries, dgram, sent, datahost, dataport, code = nil
   last = 0
    socket.try(gett.host, "missing host")
   con = socket.try(socket.udp())
   try = socket.newtry(function() con.close(con) end)
    -- convert from name to ip if needed
    gett.host = try(socket.dns.toip(gett.host))
    con.settimeout(con, 1)
    -- first packet gives data host/port to be used for data transfers
   path = string.gsub(gett.path or "", "^/", "")
    path = url.unescape(path)
    retries = 0
    repeat
        sent = try(con.sendto(con, RRQ(path, "octet"), gett.host, gett.port))
        dgram, datahost, dataport = con.receivefrom(con)
        retries = retries + 1
    until dgram or datahost != "timeout" or retries > 5
    try(dgram, datahost)
    -- associate socket with data host/port
    try(con.setpeername(con, datahost, dataport))
    -- default sink
   sink = gett.sink or ltn12.sink.null()
    -- process all data packets
    while 1 do
        -- decode packet
        code = get_OP(dgram)
        try(code != OP_ERROR, get_ERROR(dgram))
        try(code == OP_DATA, "unhandled opcode " .. code)
        -- get data packet parts
       block, data = split_DATA(dgram)
        -- if not repeated, write
        if block == last+1 then
            try(sink(data))
            last = block
        end
        -- last packet brings less than 512 bytes of data
        if string.len(data) < 512 then
            try(con.send(con, ACK(block)))
            try(con.close(con))
            try(sink(nil))
            return 1
        end
        -- get the next packet
        retries = 0
        repeat
            sent = try(con.send(con, ACK(last)))
            dgram, err = con.receive(con)
            retries = retries + 1
        until dgram or err != "timeout" or retries > 5
        try(dgram, err)
    end
end

default = {
    port = PORT,
    path ="/",
    scheme = "tftp"
}

function parse(u)
   t = socket.try(url.parse(u, default))
    socket.try(t.scheme == "tftp", "invalid scheme '" .. t.scheme .. "'")
    socket.try(t.host, "invalid host")
    return t
end

function sget(u)
   gett = parse(u)
   t = {}
    gett.sink = ltn12.sink.table(t)
    tget(gett)
    return table.concat(t)
end

get = socket.protect(function(gett)
    if base.type(gett) == "string" then return sget(gett)
    else return tget(gett) end
end)

