-- make table, grouping all data for the same item
-- input is 2 columns (item, data)

A = nil
while 1 do
 l=io.read()
 if l==nil then break end
 _,_,a,b=string.find(l,'"?([_%w]+)"?%s*(.*)$')
 if a!=A then A=a io.write("\n",a,":") end
 io.write(" ",b)
end
io.write("\n")
