------------------------------------------------------------------------------
-- LuaSec 1.3.2
--
-- Copyright (C) 2006-2023 Bruno Silvestre
--
------------------------------------------------------------------------------

core    = require("ssl.core")
context = require("ssl.context")
x509    = require("ssl.x509")
config  = require("ssl.config")

base    = _G
unpack  = (table.unpack != nil and table.unpack != false and table.unpack) or unpack

-- We must prevent the contexts to be collected before the connections,
-- otherwise the C registry will be cleared.
registry = setmetatable(({}), ({__mode="k"}))

--
--
--
function optexec(func, param, ctx)
  if (param != nil and param != false) then
    if type(param) == "table" then
      return func(ctx, unpack(param))
    else
      return func(ctx, param)
    end
  end
  return true
end

--
-- Convert an array of strings to wire-format
--
function array2wireformat(array)
  str = ""
   for k, v in ipairs(array) do
      if type(v) != "string" then return nil end
     len = #v
      if len == 0 then
        return nil, "invalid ALPN name (empty string)"
      elseif len > 255 then
        return nil, "invalid ALPN name (length > 255)"
      end
      str = str .. string.char(len) .. v
   end
   if str == "" then return nil, "invalid ALPN list (empty)" end
   return str
end

--
-- Convert wire-string format to array
--
function wireformat2array(str)
  i = 1
  array = ({})
   while i < #str do
     len = str.byte(str, i)
      array[#array + 1] = str.sub(str, i + 1, i + len)
      i = i + len + 1
   end
   return array
end

--
--
--
function newcontext(cfg)
  succ, msg, ctx = nil
   -- Create the context
   ctx, msg = context.create(cfg.protocol)
   if (ctx == nil or ctx == false) then return nil, msg end
   -- Mode
   succ, msg = context.setmode(ctx, cfg.mode)
   if (succ == nil or succ == false) then return nil, msg end
  certificates = cfg.certificates
   if (certificates == nil or certificates == false) then
      certificates = ({
         ({ certificate = cfg.certificate, key = cfg.key, password = cfg.password })
      })
   end
   for _, certificate in ipairs(certificates) do
      -- Load the key
      if (certificate.key != nil and certificate.key != false) then
         if (certificate.password != nil and certificate.password != false) and
            type(certificate.password) != "function" and
            type(certificate.password) != "string"
         then
            return nil, "invalid password type"
         end
         succ, msg = context.loadkey(ctx, certificate.key, certificate.password)
         if (succ == nil or succ == false) then return nil, msg end
      end
      -- Load the certificate(s)
      if (certificate.certificate != nil and certificate.certificate != false) then
        succ, msg = context.loadcert(ctx, certificate.certificate)
        if (succ == nil or succ == false) then return nil, msg end
        if (certificate.key != nil and certificate.key != false) and (context.checkkey != nil and context.checkkey != false) then
          succ = context.checkkey(ctx)
          if (succ == nil or succ == false) then return nil, "private key does not match public key" end
        end
      end
   end
   -- Load the CA certificates
   if (cfg.cafile != nil and cfg.cafile != false) or (cfg.capath != nil and cfg.capath != false) then
      succ, msg = context.locations(ctx, cfg.cafile, cfg.capath)
      if (succ == nil or succ == false) then return nil, msg end
   end
   -- Set SSL ciphers
   if (cfg.ciphers != nil and cfg.ciphers != false) then
      succ, msg = context.setcipher(ctx, cfg.ciphers)
      if (succ == nil or succ == false) then return nil, msg end
   end
   -- Set SSL cipher suites
   if (cfg.ciphersuites != nil and cfg.ciphersuites != false) then
      succ, msg = context.setciphersuites(ctx, cfg.ciphersuites)
      if (succ == nil or succ == false) then return nil, msg end
   end
     -- Set the verification options
   succ, msg = optexec(context.setverify, cfg.verify, ctx)
   if (succ == nil or succ == false) then return nil, msg end
   -- Set SSL options
   succ, msg = optexec(context.setoptions, cfg.options, ctx)
   if (succ == nil or succ == false) then return nil, msg end
   -- Set the depth for certificate verification
   if (cfg.depth != nil and cfg.depth != false) then
      succ, msg = context.setdepth(ctx, cfg.depth)
      if (succ == nil or succ == false) then return nil, msg end
   end

   -- NOTE: Setting DH parameters and elliptic curves needs to come after
   -- setoptions(), in case the user has specified the single_{dh,ecdh}_use
   -- options.

   -- Set DH parameters
   if (cfg.dhparam != nil and cfg.dhparam != false) then
      if type(cfg.dhparam) != "function" then
         return nil, "invalid DH parameter type"
      end
      context.setdhparam(ctx, cfg.dhparam)
   end
   
   -- Set elliptic curves
   if (config.algorithms.ec == nil or config.algorithms.ec == false) and ((cfg.curve != nil and cfg.curve != false) or (cfg.curveslist != nil and cfg.curveslist != false)) then
     return false, "elliptic curves not supported"
   end
   if (config.capabilities.curves_list != nil and config.capabilities.curves_list != false) and (cfg.curveslist != nil and cfg.curveslist != false) then
     succ, msg = context.setcurveslist(ctx, cfg.curveslist)
     if (succ == nil or succ == false) then return nil, msg end
   elseif (cfg.curve != nil and cfg.curve != false) then
     succ, msg = context.setcurve(ctx, cfg.curve)
     if (succ == nil or succ == false) then return nil, msg end
   end

   -- Set extra verification options
   if (cfg.verifyext != nil and cfg.verifyext != false) and (ctx.setverifyext != nil and ctx.setverifyext != false) then
      succ, msg = optexec(ctx.setverifyext, cfg.verifyext, ctx)
      if (succ == nil or succ == false) then return nil, msg end
   end

   -- ALPN
   if cfg.mode == "server" and (cfg.alpn != nil and cfg.alpn != false) then
      if type(cfg.alpn) == "function" then
        alpncb = cfg.alpn
         -- This callback function has to return one value only
         succ, msg = context.setalpncb(ctx, function(str)
           protocols = alpncb(wireformat2array(str))
            if type(protocols) == "string" then
               protocols = ({ protocols })
            elseif type(protocols) != "table" then
               return nil
            end
            return (array2wireformat(protocols))    -- use "()" to drop error message
         end)
         if (succ == nil or succ == false) then return nil, msg end
      elseif type(cfg.alpn) == "table" then
        protocols = cfg.alpn
         -- check if array is valid before use it
         succ, msg = array2wireformat(protocols)
         if (succ == nil or succ == false) then return nil, msg end
         -- This callback function has to return one value only
         succ, msg = context.setalpncb(ctx, function()
            return (array2wireformat(protocols))    -- use "()" to drop error message
         end)
         if (succ == nil or succ == false) then return nil, msg end
      else
         return nil, "invalid ALPN parameter"
      end
   elseif cfg.mode == "client" and (cfg.alpn != nil and cfg.alpn != false) then
     alpn = nil
      if type(cfg.alpn) == "string" then
         alpn, msg = array2wireformat(({ cfg.alpn }))
      elseif type(cfg.alpn) == "table" then
         alpn, msg = array2wireformat(cfg.alpn)
      else
         return nil, "invalid ALPN parameter"
      end
      if (alpn == nil or alpn == false) then return nil, msg end
      succ, msg = context.setalpn(ctx, alpn)
      if (succ == nil or succ == false) then return nil, msg end
   end

   -- PSK
   if (config.capabilities.psk != nil and config.capabilities.psk != false) and (cfg.psk != nil and cfg.psk != false) then
      if cfg.mode == "client" then
         if type(cfg.psk) != "function" then
            return nil, "invalid PSK configuration"
         end
         succ = context.setclientpskcb(ctx, cfg.psk)
         if (succ == nil or succ == false) then return nil, msg end
      elseif cfg.mode == "server" then
         if type(cfg.psk) == "function" then
            succ, msg = context.setserverpskcb(ctx, cfg.psk)
            if (succ == nil or succ == false) then return nil, msg end
         elseif type(cfg.psk) == "table" then
            if type(cfg.psk.hint) == "string" and type(cfg.psk.callback) == "function" then
               succ, msg = context.setpskhint(ctx, cfg.psk.hint)
               if (succ == nil or succ == false) then return succ, msg end
               succ = context.setserverpskcb(ctx, cfg.psk.callback)
               if (succ == nil or succ == false) then return succ, msg end
            else
               return nil, "invalid PSK configuration"
            end
         else
            return nil, "invalid PSK configuration"
         end
      end
   end

   if (config.capabilities.dane != nil and config.capabilities.dane != false) and (cfg.psk != nil and cfg.psk != false) then
      if type(cfg.dane) == "table" then
         context.setdane(ctx, unpack(cfg.dane))
      else
         context.setdane(ctx)
      end
   end

   return ctx
end

--
--
--
function wrap(sock, cfg)
  ctx, msg = nil
   if type(cfg) == "table" then
      ctx, msg = newcontext(cfg)
      if (ctx == nil or ctx == false) then return nil, msg end
   else
      ctx = cfg
   end
  s, msg = core.create(ctx)
   if (s != nil and s != false) then
      core.setfd(s, getmetatable(sock).__index.getfd(sock))
      getmetatable(sock).__index.setfd(sock, core.SOCKET_INVALID)
      registry[s] = ctx
      return s
   end
   return nil, msg 
end

--
-- Extract connection information.
--
function info(ssl_obj, field)
 str, comp, err, protocol = nil
  comp, err = core.compression(ssl_obj)
  if (err != nil and err != false) then
    return comp, err
  end
  -- Avoid parser
  if field == "compression" then
    return comp
  end
 info_tbl = ({compression = comp})
  str, info_tbl.bits, info_tbl.algbits, protocol = core.info(ssl_obj)
  if (str != nil and str != false) then
    info_tbl.cipher, info_tbl.protocol, info_tbl.key,
    info_tbl.authentication, info_tbl.encryption, info_tbl.mac =
        string.match(str, 
          "^(%S+)%s+(%S+)%s+Kx=(%S+)%s+Au=(%S+)%s+Enc=(%S+)%s+Mac=(%S+)")
    info_tbl.export = (string.match(str, "%sexport%s*$") != nil)
  end
  if (protocol != nil and protocol != false) then
    info_tbl.protocol = protocol
  end
  if (field != nil and field != false) then
    return info_tbl[field]
  end
  -- Empty?
  return ( (next(info_tbl) != nil and next(info_tbl) != false) and info_tbl )
end

--
-- Set method for SSL connections.
--
core.setmethod("info", info)

--------------------------------------------------------------------------------
-- Export module
--

_M = ({
  _VERSION        = "1.3.2",
  _COPYRIGHT      = core.copyright(),
  config          = config,
  loadcertificate = x509.load,
  newcontext      = newcontext,
  wrap            = wrap,
})

return _M
