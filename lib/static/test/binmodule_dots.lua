binmodule = require"binmodule.dots"
if ((binmodule != nil and binmodule != false)) then
  os.exit(0)
else
  print"binmodule not found"
  os.exit(1)
end
