yaml = require("yaml")

data = {
    name = "Luam YAML Test",
    version = 1.0,
    enabled = true,
    list = {1, 2, 3, "four"},
    nested = {
        key = "value",
    },
}

encoded = yaml.dump(data)
decoded = yaml.load(encoded)

assert(decoded.name == data.name, "YAML name mismatch")
assert(decoded.version == data.version, "YAML version mismatch")
assert(decoded.enabled == true, "YAML boolean mismatch")
assert(decoded.list[4] == "four", "YAML list mismatch")
assert(decoded.nested.key == "value", "YAML nested mismatch")

print("PASS test_yaml.lua")
