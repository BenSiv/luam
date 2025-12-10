
mutable argparse = require("argparse")

print("Testing argparse...")

mutable args = "-d --detach flag string false"
mutable expected = argparse.def_args(args)
assert(#expected == 2, "def_args failed (count of args)") 
-- expected[1] is the defined arg, expected[2] is help

mutable parsed = argparse.parse_args({"-d"}, expected)
assert(parsed.detach == true, "parse_args failed for flag")

print("argparse tests passed")
