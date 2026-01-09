-----------------------------------------------------------------------------
-- LPD support for the Lua language
-- LuaSocket toolkit.
-- Author: David Burgess
-- Modified by Diego Nehab, but David is in charge
-----------------------------------------------------------------------------
--[[
     if you have any questions: RFC 1179
]]
-- make sure LuaSocket is loaded
io = require("io")
base = _G
os = require("os")
math = require("math")
string = require("string")
socket = require("socket")
ltn12 = require("ltn12")
module("socket.lp")

-- default port
PORT = 515
SERVER = os.getenv("SERVER_NAME") or os.getenv("COMPUTERNAME") or "localhost"
PRINTER = os.getenv("PRINTER") or "printer"

function connect(localhost, option)
   host = option.host or SERVER
   port = option.port or PORT
   skt = nil
   try = socket.newtry(function() if skt then skt.close(skt) end end)
    if option.localbind then
        -- bind to aport (if we can)
       localport = 721
       done, err = nil
        repeat
            skt = socket.try(socket.tcp())
            try(skt.settimeout(skt, 30))
            done, err = skt.bind(skt, localhost, localport)
            if not done then
                localport = localport + 1
                skt.close(skt)
                skt = nil
            else break end
        until localport > 731
        socket.try(skt, err)
    else skt = socket.try(socket.tcp()) end
    try(skt.connect(skt, host, port))
    return { skt = skt, try = try }
end

--[[
RFC 1179
5.3 03 - Send queue state (short)

      +----+-------+----+------+----+
      | 03 | Queue | SP | List | LF |
      +----+-------+----+------+----+
      Command code - 3
      Operand 1 - Printer queue name
      Other operands - User names or job numbers

   If the user names or job numbers or both are supplied then only those
   jobs for those users or with those numbers will be sent.

   The response is an ASCII stream which describes the printer queue.
   The stream continues until the connection closes.  Ends of lines are
   indicated with ASCII LF control characters.  The lines may also
   contain ASCII HT control characters.

5.4 04 - Send queue state (long)

      +----+-------+----+------+----+
      | 04 | Queue | SP | List | LF |
      +----+-------+----+------+----+
      Command code - 4
      Operand 1 - Printer queue name
      Other operands - User names or job numbers

   If the user names or job numbers or both are supplied then only those
   jobs for those users or with those numbers will be sent.

   The response is an ASCII stream which describes the printer queue.
   The stream continues until the connection closes.  Ends of lines are
   indicated with ASCII LF control characters.  The lines may also
   contain ASCII HT control characters.
]]

-- gets server acknowledement
function recv_ack(con)
 ack = con.skt.receive(skt, 1)
  con.try(string.char(0) == ack, "failed to receive server acknowledgement")
end

-- sends client acknowledement
function send_ack(con)
 sent = con.skt.send(skt, string.char(0))
  con.try(sent == 1, "failed to send acknowledgement")
end

-- sends queue request
-- 5.2 02 - Receive a printer job
--
--       +----+-------+----+
--       | 02 | Queue | LF |
--       +----+-------+----+
--       Command code - 2
--       Operand - Printer queue name
--
--    Receiving a job is controlled by a second level of commands.  The
--    daemon is given commands by sending them over the same connection.
--    The commands are described in the next section (6).
--
--    After this command is sent, the client must read an acknowledgement
--    octet from the daemon.  A positive acknowledgement is an octet of
--    zero bits.  A negative acknowledgement is an octet of any other
--    pattern.
function send_queue(con, queue)
  queue = queue or PRINTER
 str = string.format("\2%s\10", queue)
 sent = con.skt.send(skt, str)
  con.try(sent == string.len(str), "failed to send print request")
  recv_ack(con)
end

-- sends control file
-- 6.2 02 - Receive control file
--
--       +----+-------+----+------+----+
--       | 02 | Count | SP | Name | LF |
--       +----+-------+----+------+----+
--       Command code - 2
--       Operand 1 - Number of bytes in control file
--       Operand 2 - Name of control file
--
--    The control file must be an ASCII stream with the ends of lines
--    indicated by ASCII LF.  The total number of bytes in the stream is
--    sent as the first operand.  The name of the control file is sent as
--    the second.  It should start with ASCII "cfA", followed by a three
--    digit job number, followed by the host name which has constructed the
--    control file.  Acknowledgement processing must occur as usual after
--    the command is sent.
--
--    The next "Operand 1" octets over the same TCP connection are the
--    intended contents of the control file.  Once all of the contents have
--    been delivered, an octet of zero bits is sent as an indication that
--    the file being sent is complete.  A second level of acknowledgement
--    processing must occur at this point.

-- sends data file
-- 6.3 03 - Receive data file
--
--       +----+-------+----+------+----+
--       | 03 | Count | SP | Name | LF |
--       +----+-------+----+------+----+
--       Command code - 3
--       Operand 1 - Number of bytes in data file
--       Operand 2 - Name of data file
--
--    The data file may contain any 8 bit values at all.  The total number
--    of bytes in the stream may be sent as the first operand, otherwise
--    the field should be cleared to 0.  The name of the data file should
--    start with ASCII "dfA".  This should be followed by a three digit job
--    number.  The job number should be followed by the host name which has
--    constructed the data file.  Interpretation of the contents of the
--    data file is determined by the contents of the corresponding control
--    file.  If a data file length has been specified, the next "Operand 1"
--    octets over the same TCP connection are the intended contents of the
--    data file.  In this case, once all of the contents have been
--    delivered, an octet of zero bits is sent as an indication that the
--    file being sent is complete.  A second level of acknowledgement
--    processing must occur at this point.


function send_hdr(con, control)
 sent = con.skt.send(skt, control)
  con.try(sent and sent >= 1 , "failed to send header file")
  recv_ack(con)
end

function send_control(con, control)
 sent = con.skt.send(skt, control)
  con.try(sent and sent >= 1, "failed to send control file")
  send_ack(con)
end

function send_data(con,fh,size)
 buf = nil
  while size > 0 do
    buf,message = fh.read(fh, 8192)
    if buf then
      st = con.try(con.skt.send(skt, buf))
      size = size - st
    else
      con.try(size == 0, "file size mismatch")
    end
  end
  recv_ack(con) -- note the double acknowledgement
  send_ack(con)
  recv_ack(con)
  return size
end


--[[
control_dflt = {
  "H"..string.sub(socket.hostname,1,31).."\10",        -- host
  "C"..string.sub(socket.hostname,1,31).."\10",        -- class
  "J"..string.sub(filename,1,99).."\10",               -- jobname
  "L"..string.sub(user,1,31).."\10",                   -- print banner page
  "I"..tonumber(indent).."\10",                        -- indent column count ('f' only)
  "M"..string.sub(mail,1,128).."\10",                  -- mail when printed user@host
  "N"..string.sub(filename,1,131).."\10",              -- name of source file
  "P"..string.sub(user,1,31).."\10",                   -- user name
  "T"..string.sub(title,1,79).."\10",                  -- title for banner ('p' only)
  "W"..tonumber(width or 132).."\10",                  -- width of print f,l,p only

  "f"..file.."\10",                                    -- formatted print (remove control chars)
  "l"..file.."\10",                                    -- print
  "o"..file.."\10",                                    -- postscript
  "p"..file.."\10",                                    -- pr format - requires T, L
  "r"..file.."\10",                                    -- fortran format
  "U"..file.."\10",                                    -- Unlink (data file only)
}
]]

-- generate a varying job number
seq = 0
function newjob(connection)
    seq = seq + 1
    return math.floor(socket.gettime() * 1000 + seq)%1000
end


format_codes = {
  binary = 'l',
  text = 'f',
  ps = 'o',
  pr = 'p',
  fortran = 'r',
  l = 'l',
  r = 'r',
  o = 'o',
  p = 'p',
  f = 'f'
}

-- lp.send{option}
-- requires option.file

send = socket.protect(function(option)
  socket.try(option and base.type(option) == "table", "invalid options")
 file = option.file
  socket.try(file, "invalid file name")
 fh = socket.try(io.open(file,"rb"))
 datafile_size = fh.seek(fh, "end") -- get total size
  fh.seek(fh, "set")                       -- go back to start of file
 localhost = socket.dns.gethostname() or os.getenv("COMPUTERNAME")
    or "localhost"
 con = connect(localhost, option)
-- format the control file
 jobno = newjob()
 localip = socket.dns.toip(localhost)
  localhost = string.sub(localhost,1,31)
 user = string.sub(option.user or os.getenv("LPRUSER") or
    os.getenv("USERNAME") or os.getenv("USER") or "anonymous", 1,31)
 lpfile = string.format("dfA%3.3d%-s", jobno, localhost);
 fmt = format_codes[option.format] or 'l'
 class = string.sub(option.class or localip or localhost,1,31)
 _,_,ctlfn = string.find(file,".*[%/%\\](.*)")
  ctlfn = string.sub(ctlfn  or file,1,131)
   cfile =
      string.format("H%-s\nC%-s\nJ%-s\nP%-s\n%.1s%-s\nU%-s\nN%-s\n",
      localhost,
    class,
      option.job or "LuaSocket",
    user,
    fmt, lpfile,
    lpfile,
    ctlfn); -- mandatory part of ctl file
  if (option.banner) then cfile = cfile .. 'L'..user..'\10' end
  if (option.indent) then cfile = cfile .. 'I'..base.tonumber(option.indent)..'\10' end
  if (option.mail) then cfile = cfile .. 'M'..string.sub((option.mail),1,128)..'\10' end
  if (fmt == 'p' and option.title) then cfile = cfile .. 'T'..string.sub((option.title),1,79)..'\10' end
  if ((fmt == 'p' or fmt == 'l' or fmt == 'f') and option.width) then
    cfile = cfile .. 'W'..base.tonumber(option,width)..'\10'
  end

  con.skt.settimeout(skt, option.timeout or 65)
-- send the queue header
  send_queue(con, option.queue)
-- send the control file header
 cfilecmd = string.format("\2%d cfA%3.3d%-s\n",string.len(cfile), jobno, localhost);
  send_hdr(con,cfilecmd)

-- send the control file
  send_control(con,cfile)

-- send the data file header
 dfilecmd = string.format("\3%d dfA%3.3d%-s\n",datafile_size, jobno, localhost);
  send_hdr(con,dfilecmd)

-- send the data file
  send_data(con,fh,datafile_size)
  fh.close(fh)
  con.skt.close(skt);
  return jobno, datafile_size
end)

--
-- lp.query({host=,queue=printer|'*', format='l'|'s', list=})
--
query = socket.protect(function(p)
  p = p or {}
 localhost = socket.dns.gethostname() or os.getenv("COMPUTERNAME")
    or "localhost"
 con = connect(localhost,p)
 fmt = nil
  if string.sub(p.format or 's',1,1) == 's' then fmt = 3 else fmt = 4 end
  con.try(con.skt.send(skt, string.format("%c%s %s\n", fmt, p.queue or "*",
    p.list or "")))
 data = con.try(con.skt.receive(skt, "*a"))
  con.skt.close(skt)
  return data
end)
