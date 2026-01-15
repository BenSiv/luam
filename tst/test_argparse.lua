
package.path = "lib/?.lua;" .. package.path
argparse = require("argparse")

print("esting argparse...")

args = "-d --detach flag string false"
expected = argparse.def_args(args)
assert(#expected == 2, "def_args failed (count of args)") 
-- expected[1] is the defined arg, expected[2] is help

parsed = argparse.parse_args({"-d"}, expected)
assert(parsed.detach == true, "parse_args failed for flag")

print("argparse tests passed")
