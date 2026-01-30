
package.path = "lib/?.lua;" .. package.path
dlm = require("delimited_files")

print("esting delimited_files...")

parts = dlm.dlm_split("a,b,c", ",")
assert(#parts == 3, "dlm_split failed")

tmp_file = "test.csv"
file = io.open(tmp_file, "w")
io.write(file, "col1,col2\nval1,val2\n")
io.close(file)

data = dlm.readdlm(tmp_file, ",", true)
assert(data[1].col1 == "val1", "readdlm failed")

os.remove(tmp_file)

print("delimited_files tests passed")
