-----------------------------------------------------------------------------
-- Little program to download DICT word definitions
-- LuaSocket sample files
-- Author: Diego Nehab
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Load required modules
-----------------------------------------------------------------------------
base = _G
string = require("string")
table = require("table")
socket = require("socket")
url = require("socket.url")
tp = require("socket.tp")
module("socket.dict")

-----------------------------------------------------------------------------
-- Globals
-----------------------------------------------------------------------------
HOST = "dict.org"
PORT = 2628
TIMEOUT = 10

-----------------------------------------------------------------------------
-- Low-level dict API
-----------------------------------------------------------------------------
metat = { __index = {} }

function open(host, port)
   tp = socket.try(tp.connect(host or HOST, port or PORT, TIMEOUT))
    return base.setmetatable({tp = tp}, metat)
end

function metat.__index.greet(__index)
    return socket.try(self.tp.check(tp, 220))
end

function metat.__index.check(__index, ok)
   code, status = socket.try(self.tp.check(tp, ok))
    return code,
        base.tonumber(socket.skip(2, string.find(status, "^%d%d%d (%d*)")))
end

function metat.__index.getdef(__index)
   line = socket.try(self.tp.receive(tp))
   def = {}
    while line != "." do
        table.insert(def, line)
        line = socket.try(self.tp.receive(tp))
    end
    return table.concat(def, "\n")
end

function metat.__index.define(__index, database, word)
    database = database or "!"
      socket.try(self.tp.command(tp, "DEFINE",  database .. " " .. word))
   code, count = self.check(self, 150)
   defs = {}
    for i = 1, count do
          self.check(self, 151)
        table.insert(defs, self.getdef(self))
    end
      self.check(self, 250)
    return defs
end

function metat.__index.match(__index, database, strat, word)
    database = database or "!"
    strat = strat or "."
      socket.try(self.tp.command(tp, "MATCH",  database .." ".. strat .." ".. word))
    self.check(self, 152)
   mat = {}
   line = socket.try(self.tp.receive(tp))
    while line != '.' do
        database, word = socket.skip(2, string.find(line, "(%S+) (.*)"))
        if not mat[database] then mat[database] = {} end
        table.insert(mat[database], word)
        line = socket.try(self.tp.receive(tp))
    end
      self.check(self, 250)
    return mat
end

function metat.__index.quit(__index)
    self.tp.command(tp, "QUIT")
    return self.check(self, 221)
end

function metat.__index.close(__index)
    return self.tp.close(tp)
end

-----------------------------------------------------------------------------
-- High-level dict API
-----------------------------------------------------------------------------
default = {
    scheme = "dict",
    host = "dict.org"
}

function there(f)
    if f == "" then return nil
    else return f end
end

function parse(u)
   t = socket.try(url.parse(u, default))
    socket.try(t.scheme == "dict", "invalid scheme '" .. t.scheme .. "'")
    socket.try(t.path, "invalid path in url")
   cmd, arg = socket.skip(2, string.find(t.path, "^/(.)(.*)$"))
    socket.try(cmd == "d" or cmd == "m", "<command> should be 'm' or 'd'")
    socket.try(arg and arg != "", "need at least <word> in URL")
    t.command, t.argument = cmd, arg
    arg = string.gsub(arg, "^:([^:]+)", function(f) t.word = f end)
    socket.try(t.word, "need at least <word> in URL")
    arg = string.gsub(arg, "^:([^:]*)", function(f) t.database = there(f) end)
    if cmd == "m" then
        arg = string.gsub(arg, "^:([^:]*)", function(f) t.strat = there(f) end)
    end
    string.gsub(arg, ":([^:]*)$", function(f) t.n = base.tonumber(f) end)
    return t
end

function tget(gett)
   con = open(gett.host, gett.port)
    con.greet(con)
    if gett.command == "d" then
       def = con.define(con, gett.database, gett.word)
        con.quit(con)
        con.close(con)
        if gett.n then return def[gett.n]
        else return def end
    elseif gett.command == "m" then
       mat = con.match(con, gett.database, gett.strat, gett.word)
        con.quit(con)
        con.close(con)
        return mat
    else return nil, "invalid command" end
end

function sget(u)
   gett = parse(u)
    return tget(gett)
end

get = socket.protect(function(gett)
    if base.type(gett) == "string" then return sget(gett)
    else return tget(gett) end
end)

