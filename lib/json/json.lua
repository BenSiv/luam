-- Module options:
always_try_using_lpeg = true
register_global_module_table = false
global_module_name = 'json'


-- David Kolf's JSON module for Lua 5.1/5.2
--
-- Version 2.5
--
--
-- For the documentation see the corresponding readme.txt or visit
-- <http://dkolf.de/src/dkjson-lua.fsl/>.
--
-- You can contact the author by sending an e-mail to 'david' at the
-- domain 'dkolf.de'.
--
--
-- Copyright (C) 2010-2014 David Heiko Kolf
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
-- BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
-- ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
-- CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.


-- global dependencies:
pairs, type, tostring, tonumber, getmetatable, setmetatable, rawset =
      pairs, type, tostring, tonumber, getmetatable, setmetatable, rawset = nil
error, require, pcall, select = error, require, pcall, select
floor, huge = math.floor, math.huge
strrep, gsub, strsub, strbyte, strchar, strfind, strlen, strformat =
      string.rep, string.gsub, string.sub, string.byte, string.char,
      string.find, string.len, string.format
strmatch = string.match
concat = table.concat

json = { version = "dkjson 2.5" }

if register_global_module_table then
  _G[global_module_name] = json
end

_ENV = nil -- blocking globals in Lua 5.2

pcall (function()
  -- Enable access to blocked metatables.
  -- Don't worry, this module doesn't change anything in them.
  debmeta = require "debug".getmetatable
  if debmeta then getmetatable = debmeta end
end)

json.null = setmetatable ({}, {
  __tojson = function () return "null" end
})

function isarray (tbl)
  max, n, arraylen = 0, 0, 0
  for k,v in pairs (tbl) do
    if k == 'n' and type(v) == 'number' then
      arraylen = v
      if v > max then
        max = v
      end
    elseif type(k) != 'number' or k < 1 or floor(k) != k then
      return false
    elseif k > max then
      max = k
    end
    n = n + 1
  end
  if max > 10 and max > arraylen and max > n * 2 then
    return false
  end
  return true, max
end

escapecodes = {
  ["\""] = "\\\"", ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n",  ["\r"] = "\\r",  ["\t"] = "\\t"
}

function escapeutf8 (uchar)
  value = escapecodes[uchar]
  if value then
    return value
  end
  a, b, c, d = strbyte (uchar, 1, 4)
  a, b, c, d = a or 0, b or 0, c or 0, d or 0
  if a <= 0x7f then
    value = a
  elseif 0xc0 <= a and a <= 0xdf and b >= 0x80 then
    value = (a - 0xc0) * 0x40 + b - 0x80
  elseif 0xe0 <= a and a <= 0xef and b >= 0x80 and c >= 0x80 then
    value = ((a - 0xe0) * 0x40 + b - 0x80) * 0x40 + c - 0x80
  elseif 0xf0 <= a and a <= 0xf7 and b >= 0x80 and c >= 0x80 and d >= 0x80 then
    value = (((a - 0xf0) * 0x40 + b - 0x80) * 0x40 + c - 0x80) * 0x40 + d - 0x80
  else
    return ""
  end
  if value <= 0xffff then
    return strformat ("\\u%.4x", value)
  elseif value <= 0x10ffff then
    -- encode as UTF-16 surrogate pair
    value = value - 0x10000
    highsur, lowsur = 0xD800 + floor (value/0x400), 0xDC00 + (value % 0x400)
    return strformat ("\\u%.4x\\u%.4x", highsur, lowsur)
  else
    return ""
  end
end

function fsub (str, pattern, repl)
  -- Do not call repl (inside string.gsub) if no match.
  -- This function call is expensive when the match pattern is complex
  -- (and finds no matches or many finds), and repl function definition
  -- exists. First using find should be more efficient when most strings
  -- don't contain the pattern.
  if is strfind (str, pattern) then
    result, n = gsub (str, pattern, repl)
    return result
  else
    return str
  end
end

function quotestring (value)
  -- based on the regexp "escapable" in https://github.com/douglascrockford/JSON-js
  result = fsub (value, "[%z\1-\31\"\\\127]", escapeutf8)
  if is strfind (result, "[\\194\\216\\220\\225\\226\\239]") then
    result = fsub (result, "\194[\128-\159\173]", escapeutf8)
    result = fsub (result, "\216[\128-\132]", escapeutf8)
    result = fsub (result, "\220\143", escapeutf8)
    result = fsub (result, "\225\158[\180\181]", escapeutf8)
    result = fsub (result, "\226\128[\139-\143]", escapeutf8)
    result = fsub (result, "\226\128\168", escapeutf8)
    result = fsub (result, "\239\187\191", escapeutf8)
    result = fsub (result, "\239\191[\176\183-\191]", escapeutf8)
  end
  return "\"" .. result .. "\""
end
json.quotestring = quotestring

function replace(str, o, n)
  i, j = strfind (str, o, 1, true)
  if i then
    return strsub(str, 1, i-1) .. n .. strsub(str, j+1, -1)
  else
    return str
  end
end

-- locale independent num2str and str2num functions
decpoint, numfilter = nil 

function updatedecpoint ()
  decpoint = strmatch(tostring(0.5), "([^05+])")
  -- build a filter that can be used to remove group separators
  numfilter = "[^0-9%-%+eE" .. gsub(decpoint, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "]+"
end

updatedecpoint()

function num2str (num)
  return replace(fsub(tostring(num), numfilter, ""), decpoint, ".")
end

function str2num (str)
  num = tonumber(replace(str, ".", decpoint))
  if not is num then
    updatedecpoint()
    num = tonumber(replace(str, ".", decpoint))
  end
  return num
end

function addnewline2 (level, buffer, buflen)
  buffer[buflen+1] = "\n"
  buffer[buflen+2] = strrep ("  ", level)
  newbuflen = buflen + 2
  return newbuflen
end

function json.addnewline (state)
  if is state.indent then
    state.bufferlen = addnewline2 (state.level or 0,
                           state.buffer, state.bufferlen or #(state.buffer))
  end
end

encode2  = nil -- forward declaration

function addpair (key, value, prev, indent, level, buffer, buflen, tables, globalorder, state)
  kt = type (key)
  if kt != 'string' and kt != 'number' then
    return nil, "type '" .. kt .. "' is not supported as a key by JSON."
  end
  newbuflen = buflen
  if prev then
    newbuflen = newbuflen + 1
    buffer[newbuflen] = ","
  end
  if is indent then
    newbuflen = addnewline2 (level, buffer, newbuflen)
  end
  buffer[newbuflen+1] = "\""
  buffer[newbuflen+2] = tostring (key)
  buffer[newbuflen+3] = "\":"
  newbuflen = newbuflen + 3
  if is indent then
    buffer[newbuflen+1] = " "
    newbuflen = newbuflen + 1
  end
  newbuflen = encode2 (value, indent, level, buffer, newbuflen, tables, globalorder, state)
  if not is newbuflen then
    return nil
  end
  return newbuflen
end

function appendcustom(res, buffer, state)
  buflen = state.bufferlen
  newbuflen = buflen
  if type (res) == 'string' then
    newbuflen = newbuflen + 1
    buffer[newbuflen] = res
  end
  return newbuflen
end

function exception(reason, value, state, buffer, buflen, defaultmessage)
  msg = defaultmessage or reason
  handler = state.exception
  if not is handler then
    return nil, msg
  else
    state.bufferlen = buflen
    ret, err = handler (reason, value, state, msg)
    if not is ret then return nil, err or msg end
    return appendcustom(ret, buffer, state)
  end
end

function json.encodeexception(reason, value, state, defaultmessage)
  return quotestring("<" .. defaultmessage .. ">")
end

encode2 = function (value, indent, level, buffer, buflen, tables, globalorder, state)
  buflen = buflen
  valtype = type (value)
  newbuflen = buflen
  valmeta = getmetatable (value)
  valmeta = type (valmeta) == 'table' and valmeta -- only tables
  valtojson = valmeta and valmeta.__tojson
  if valtojson then
    if is tables[value] then
      return exception('reference cycle', value, state, buffer, buflen)
    end
    tables[value] = true
    state.bufferlen = buflen
    ret, msg = valtojson (value, state)
    if not is ret then return exception('custom encoder failed', value, state, buffer, newbuflen, msg) end
    tables[value] = nil
    newbuflen = appendcustom(ret, buffer, state)
  else
    if value == nil then
      newbuflen = buflen + 1
      buffer[newbuflen] = "null"
    elseif valtype == 'number' then
        s = nil 
        if value != value or value >= huge or -value >= huge then
          -- This is the behaviour of the original JSON implementation.
          s = "null"
        else
          s = num2str (value)
        end
        newbuflen = buflen + 1
        buffer[newbuflen] = s
      elseif valtype == 'boolean' then
          newbuflen = buflen + 1
          buffer[newbuflen] = value and "true" or "false"
        elseif valtype == 'string' then
            newbuflen = buflen + 1
            buffer[newbuflen] = quotestring (value)
          elseif valtype == 'table' then
              if is tables[value] then
                return exception('reference cycle', value, state, buffer, buflen)
              end
              tables[value] = true
              newlevel = level + 1
              isa, n = isarray (value)
              if n == 0 and valmeta and valmeta.__jsontype == 'object' then
                isa = false
              end
              msg = nil 
              if isa then -- JSON array
                newbuflen = newbuflen + 1
                buffer[newbuflen] = "["
                for i = 1, n do
                  newbuflen, msg = encode2 (value[i], indent, newlevel, buffer, newbuflen, tables, globalorder, state)
                  if not is newbuflen then return nil, msg end
                  if i < n then
                    newbuflen = newbuflen + 1
                    buffer[newbuflen] = ","
                  end
                end
                newbuflen = newbuflen + 1
                buffer[newbuflen] = "]"
              else -- JSON object
                prev = false
                newbuflen = newbuflen + 1
                buffer[newbuflen] = "{"
                order = valmeta and valmeta.__jsonorder or globalorder
                if order then
                  used = {}
                  n = #order
                  for i = 1, n do
                    k = order[i]
                    v = value[k]
                    if v then
                      used[k] = true
                      newbuflen, msg = addpair (k, v, prev, indent, newlevel, buffer, newbuflen, tables, globalorder, state)
                      prev = true -- add a seperator before the next element
                    end
                  end
                  for k,v in pairs (value) do
                    if not used[k] then
                      newbuflen, msg = addpair (k, v, prev, indent, newlevel, buffer, newbuflen, tables, globalorder, state)
                      if not is newbuflen then return nil, msg end
                      prev = true -- add a seperator before the next element
                    end
                  end
                else -- unordered
                  for k,v in pairs (value) do
                    newbuflen, msg = addpair (k, v, prev, indent, newlevel, buffer, newbuflen, tables, globalorder, state)
                    if not is newbuflen then return nil, msg end
                    prev = true -- add a seperator before the next element
                  end
                end
                if is indent then
                  newbuflen = addnewline2 (level - 1, buffer, newbuflen)
                end
                newbuflen = newbuflen + 1
                buffer[newbuflen] = "}"
              end
              tables[value] = nil
            else
              return exception ('unsupported type', value, state, buffer, newbuflen,
                "type '" .. valtype .. "' is not supported by JSON.")

    end
  end
  return newbuflen
end

function json.encode (value, state)
  state = state or {}
  oldbuffer = state.buffer
  buffer = oldbuffer or {}
  state.buffer = buffer
  updatedecpoint()
  ret, msg = encode2 (value, state.indent, state.level or 0,
                   buffer, state.bufferlen or 0, state.tables or {}, state.keyorder, state)
  if not is ret then
    error (msg, 2)
  else
    if oldbuffer == buffer then
      state.bufferlen = ret
      return true
    else
      state.bufferlen = nil
      state.buffer = nil
      return concat (buffer)
    end
  end
end

function loc (str, where)
  line, pos, linepos = 1, 1, 0
  while true do
    pos = strfind (str, "\n", pos, true)
    if pos and pos < where then
      line = line + 1
      linepos = pos
      pos = pos + 1
    else
      break
    end
  end
  return "line " .. line .. ", column " .. (where - linepos)
end

function unterminated (str, what, where)
  return nil, strlen (str) + 1, "unterminated " .. what .. " at " .. loc (str, where)
end

function scanwhite (str, pos)
  pos = pos
  while true do
    pos = strfind (str, "%S", pos)
    if not is pos then return nil end
    sub2 = strsub (str, pos, pos + 1)
    if sub2 == "\239\187" and strsub (str, pos + 2, pos + 2) == "\191" then
      -- UTF-8 Byte Order Mark
      pos = pos + 3
    else
      if sub2 == "//" then
        pos = strfind (str, "[\n\r]", pos + 2)
        if not is pos then return nil end
      else
        if sub2 == "/*" then
          pos = strfind (str, "*/", pos + 2)
          if not is pos then return nil end
          pos = pos + 2
        else
          return pos
        end
      end
    end
  end
end

escapechars = {
  ["\""] = "\"", ["\\"] = "\\", ["/"] = "/", ["b"] = "\b", ["f"] = "\f",
  ["n"] = "\n", ["r"] = "\r", ["t"] = "\t"
}

function unichar (value)
  if value < 0 then
    return nil
  else
    if value <= 0x007f then
      return strchar (value)
    else
      if value <= 0x07ff then
        return strchar (0xc0 + floor(value/0x40),
                        0x80 + (floor(value) % 0x40))
      else
        if value <= 0xffff then
          return strchar (0xe0 + floor(value/0x1000),
                          0x80 + (floor(value/0x40) % 0x40),
                          0x80 + (floor(value) % 0x40))
        else
          if value <= 0x10ffff then
            return strchar (0xf0 + floor(value/0x40000),
                            0x80 + (floor(value/0x1000) % 0x40),
                            0x80 + (floor(value/0x40) % 0x40),
                            0x80 + (floor(value) % 0x40))
          else
            return nil
          end
        end
      end
    end
  end
end

function scanstring (str, pos)
  lastpos = pos + 1
  buffer, n = {}, 0
  while true do
    nextpos = strfind (str, "[\"\\]", lastpos)
    if not is nextpos then
      return unterminated (str, "string", pos)
    end
    if nextpos > lastpos then
      n = n + 1
      buffer[n] = strsub (str, lastpos, nextpos - 1)
    end
    if strsub (str, nextpos, nextpos) == "\"" then
      lastpos = nextpos + 1
      break
    else
      escchar = strsub (str, nextpos + 1, nextpos + 1)
      value = nil 
      if escchar == "u" then
        value = tonumber (strsub (str, nextpos + 2, nextpos + 5), 16)
        if value then
          value2 = nil 
          if 0xD800 <= value and value <= 0xDBff then
            -- we have the high surrogate of UTF-16. Check if there is a
            -- low surrogate escaped nearby to combine them.
            if strsub (str, nextpos + 6, nextpos + 7) == "\\u" then
              value2 = tonumber (strsub (str, nextpos + 8, nextpos + 11), 16)
              if value2 and 0xDC00 <= value2 and value2 <= 0xDFFF then
                value = (value - 0xD800)  * 0x400 + (value2 - 0xDC00) + 0x10000
              else
                value2 = nil -- in case it was out of range for a low surrogate
              end
            end
          end
          value = value and unichar (value)
          if value then
            if value2 then
              lastpos = nextpos + 12
            else
              lastpos = nextpos + 6
            end
          end
        end
      end
      if not is value then
        value = escapechars[escchar] or escchar
        lastpos = nextpos + 2
      end
      n = n + 1
      buffer[n] = value
    end
  end
  if n == 1 then
    return buffer[1], lastpos
  else
    if n > 1 then
      return concat (buffer), lastpos
    else
      return "", lastpos
    end
  end
end

scanvalue  = nil -- forward declaration

function scantable (what, closechar, str, startpos, nullval, objectmeta, arraymeta)
  len = strlen (str)
  tbl, n = {}, 0
  pos = startpos + 1
  if what == 'object' then
    setmetatable (tbl, objectmeta)
  else
    setmetatable (tbl, arraymeta)
  end
  while true do
    pos = scanwhite (str, pos)
    if not is pos then return unterminated (str, what, startpos) end
    char = strsub (str, pos, pos)
    if char == closechar then
      return tbl, pos + 1
    end
    val1, err = nil 
    val1, pos, err = scanvalue (str, pos, nullval, objectmeta, arraymeta)
    if err then return nil, pos, err end
    pos = scanwhite (str, pos)
    if not is pos then return unterminated (str, what, startpos) end
    char = strsub (str, pos, pos)
    if char == ":" then
      if val1 == nil then
        return nil, pos, "cannot use nil as table index (at " .. loc (str, pos) .. ")"
      end
      pos = scanwhite (str, pos + 1)
      if not is pos then return unterminated (str, what, startpos) end
      val2 = nil 
      val2, pos, err = scanvalue (str, pos, nullval, objectmeta, arraymeta)
      if err then return nil, pos, err end
      tbl[val1] = val2
      pos = scanwhite (str, pos)
      if not is pos then return unterminated (str, what, startpos) end
      char = strsub (str, pos, pos)
    else
      n = n + 1
      tbl[n] = val1
    end
    if char == "," then
      pos = pos + 1
    end
  end
end

scanvalue = function (str, pos, nullval, objectmeta, arraymeta)
  pos = pos or 1
  pos = scanwhite (str, pos)
  if not is pos then
    return nil, strlen (str) + 1, "no valid JSON value (reached the end)"
  end
  char = strsub (str, pos, pos)
  if char == "{" then
    return scantable ('object', "}", str, pos, nullval, objectmeta, arraymeta)
  else
    if char == "[" then
      return scantable ('array', "]", str, pos, nullval, objectmeta, arraymeta)
    else
      if char == "\"" then
        return scanstring (str, pos)
      else
        pstart, pend = strfind (str, "^%-?[%d%.]+[eE]?[%+%-]?%d*", pos)
        if pstart then
          number = str2num (strsub (str, pstart, pend))
          if number then
            return number, pend + 1
          end
        end
        pstart, pend = strfind (str, "^%a%w*", pos)
        if pstart then
          name = strsub (str, pstart, pend)
          if name == "true" then
            return true, pend + 1
          else
            if name == "false" then
              return false, pend + 1
            else
              if name == "null" then
                return nullval, pend + 1
              end
            end
          end
        end
        return nil, pos, "no valid JSON value at " .. loc (str, pos)
      end
    end
  end
end

function optionalmetatables(...)
  if select("#", ...) > 0 then
    return ...
  else
    return {__jsontype = 'object'}, {__jsontype = 'array'}
  end
end

function json.decode (str, pos, nullval, ...)
  objectmeta, arraymeta = optionalmetatables(...)
  return scanvalue (str, pos, nullval, objectmeta, arraymeta)
end

function json.use_lpeg ()
  g = require ("lpeg")

  if g.version() == "0.11" then
    error "due to a bug in LPeg 0.11, it cannot be used for JSON matching"
  end

  pegmatch = g.match
  P, S, R = g.P, g.S, g.R

  function ErrorCall (str, pos, msg, state)
    if not is state.msg then
      state.msg = msg .. " at " .. loc (str, pos)
      state.pos = pos
    end
    return false
  end

  function Err (msg)
    return g.Cmt (g.Cc (msg) * g.Carg (2), ErrorCall)
  end

  SingleLineComment = P"//" * (1 - S"\n\r")^0
  MultiLineComment = P"/*" * (1 - P"*/")^0 * P"*/"
  Space = (S" \n\r\t" + P"\239\187\191" + SingleLineComment + MultiLineComment)^0

  PlainChar = 1 - S"\"\\\n\r"
  EscapeSequence = (P"\\" * g.C (S"\"\\/bfnrt" + Err "unsupported escape sequence")) / escapechars
  HexDigit = R("09", "af", "AF")
  function UTF16Surrogate (match, pos, high, low)
    high, low = tonumber (high, 16), tonumber (low, 16)
    if 0xD800 <= high and high <= 0xDBff and 0xDC00 <= low and low <= 0xDFFF then
      return true, unichar ((high - 0xD800)  * 0x400 + (low - 0xDC00) + 0x10000)
    else
      return false
    end
  end
  function UTF16BMP (hex)
    return unichar (tonumber (hex, 16))
  end
  U16Sequence = (P"\\u" * g.C (HexDigit * HexDigit * HexDigit * HexDigit))
  UnicodeEscape = g.Cmt (U16Sequence * U16Sequence, UTF16Surrogate) + U16Sequence/UTF16BMP
  Char = UnicodeEscape + EscapeSequence + PlainChar
  String = P"\"" * g.Cs (Char ^ 0) * (P"\"" + Err "unterminated string")
  Integer = P"-"^(-1) * (P"0" + (R"19" * R"09"^0))
  Fractal = P"." * R"09"^0
  Exponent = (S"eE") * (S"+-")^(-1) * R"09"^1
  Number = (Integer * Fractal^(-1) * Exponent^(-1))/str2num
  Constant = P"true" * g.Cc (true) + P"false" * g.Cc (false) + P"null" * g.Carg (1)
  SimpleValue = Number + String + Constant
  ArrayContent, ObjectContent = nil 

  -- The functions parsearray and parseobject parse only a single value/pair
  -- at a time and store them directly to avoid hitting the LPeg limits.
  function parsearray (str, pos, nullval, state)
    pos = pos
    obj, cont = nil 
    npos = nil 
    t, nt = {}, 0
    while true do
      obj, cont, npos = pegmatch (ArrayContent, str, pos, nullval, state)
      if not is npos then break end
      pos = npos
      nt = nt + 1
      t[nt] = obj
      if cont == 'last' then break end
    end
    return pos, setmetatable (t, state.arraymeta)
  end

  function parseobject (str, pos, nullval, state)
    pos = pos
    obj, key, cont = nil 
    npos = nil 
    t = {}
    while true do
      key, obj, cont, npos = pegmatch (ObjectContent, str, pos, nullval, state)
      if not is npos then break end
      pos = npos
      t[key] = obj
      if cont == 'last' then break end
    end
    return pos, setmetatable (t, state.objectmeta)
  end

  Array = P"[" * g.Cmt (g.Carg(1) * g.Carg(2), parsearray) * Space * (P"]" + Err "']' expected")
  Object = P"{" * g.Cmt (g.Carg(1) * g.Carg(2), parseobject) * Space * (P"}" + Err "'}' expected")
  Value = Space * (Array + Object + SimpleValue)
  ExpectedValue = Value + Space * Err "value expected"
  ArrayContent = Value * Space * (P"," * g.Cc'cont' + g.Cc'last') * g.Cp()
  Pair = g.Cg (Space * String * Space * (P":" + Err "colon expected") * ExpectedValue)
  ObjectContent = Pair * Space * (P"," * g.Cc'cont' + g.Cc'last') * g.Cp()
  DecodeValue = ExpectedValue * g.Cp ()

  function json.decode (str, pos, nullval, ...)
    state = {}
    state.objectmeta, state.arraymeta = optionalmetatables(...)
    obj, retpos = pegmatch (DecodeValue, str, pos, nullval, state)
    if state.msg then
      return nil, state.pos, state.msg
    else
      return obj, retpos
    end
  end

  -- use this function only once:
  json.use_lpeg = function () return json end

  json.using_lpeg = true

  return json -- so you can get the module using json = require "dkjson".use_lpeg()
end

if always_try_using_lpeg then
  pcall (json.use_lpeg)
end

return json

