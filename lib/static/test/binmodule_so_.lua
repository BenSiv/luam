binmodule = require("binmodule_so")
if ((binmodule != nil and binmodule != false)) then
  os.exit(0)
else
  print("binmodule not found")
  os.exit(1)
end
