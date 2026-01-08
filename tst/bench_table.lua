-- Benchmark: Table operations (measures table creation and access)
local iterations = 1000000

local start = os.clock()

local t = {}
for i = 1, iterations do
    t[i] = i * 2
end

local sum = 0
for i = 1, iterations do
    sum = sum + t[i]
end

local elapsed = os.clock() - start

print(string.format("Table sum: %d", sum))
print(string.format("Time: %.4f seconds", elapsed))
