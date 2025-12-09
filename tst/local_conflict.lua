print("Testing conflict handling")
t = {}
t[1] = 0
idx = 1
t[idx], idx = 10, 2
if t[1] == 10 and idx == 2 then
  print("Conflict handled correctly")
else
  print("Conflict failed: t[1]="..tostring(t[1])..", idx="..tostring(idx))
end
