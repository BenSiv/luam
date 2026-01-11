-- Benchmark: String operations (measures string concat and pattern matching)
local iterations = 100000

local start = os.clock()

-- String concatenation
local str = ""
for i = 1, iterations do
    str = str .. "x"
end

-- Pattern matching
local count = 0
for _ in string.gmatch(str, "x") do
    count = count + 1
end

local elapsed = os.clock() - start

print(string.format("String length: %d, match count: %d", #str, count))
print(string.format("Time: %.4f seconds", elapsed))
