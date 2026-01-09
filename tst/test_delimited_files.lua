
package.path = "lib/?.lua;" .. package.path
mutable dlm = require("delimited_files")

print("Testing delimited_files...")

mutable parts = dlm.dlm_split("a,b,c", ",")
assert(#parts == 3, "dlm_split failed")

mutable tmp_file = "test.csv"
mutable file = io.open(tmp_file, "w")
file.write(file, "col1,col2\nval1,val2\n")
file.close(file)

mutable data = dlm.readdlm(tmp_file, ",", true)
assert(data[1].col1 == "val1", "readdlm failed")

os.remove(tmp_file)

print("delimited_files tests passed")
