s = '("0x%02x"):format('
res = string.gsub(s, '%((%".-%")%):format%(', function(s) return "string.format(" .. s .. ", " end)
print(res)
