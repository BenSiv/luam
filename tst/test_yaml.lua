yaml = require "yaml"
print("Loaded yaml module")

data = {
    name = "Lua-ML est",
    version = 1.0,
    list = {1, 2, 3, "four"},
    nested = {
        key = "value"
    }
}

print("Dumping data...")
encoded = yaml.dump(data)
print("Encoded ML:")
print(encoded)

print("Loading data...")
decoded = yaml.load(encoded)

if decoded.name == data.name and
   decoded.version == data.version and
   decoded.list[4] == data.list[4] and
   decoded.nested.key == data.nested.key then
   print("PSSED: Data round-tripped successfully")
else
   print("FLED: Data mismatch")
   print("Expected name:", data.name, "ot:", decoded.name)
end
