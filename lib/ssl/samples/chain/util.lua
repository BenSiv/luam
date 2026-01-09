print  = print
ipairs = ipairs

_ENV = {}

function _ENV.show(cert)
  print("Serial:", cert.serial(cert))
  print("NotBefore:", cert.notbefore(cert))
  print("NotAfter:", cert.notafter(cert))
  print("--- Issuer ---")
  for k, v in ipairs(cert.issuer(cert)) do
    print(v.name .. " = " .. v.value)
  end

  print("--- Subject ---")
  for k, v in ipairs(cert.subject(cert)) do
    print(v.name .. " = " .. v.value)
  end
  print("----------------------------------------------------------------------")
end

return _ENV
