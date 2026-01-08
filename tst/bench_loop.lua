-- Benchmark: Loop and arithmetic (measures basic VM operations)
local iterations = 10000000

local start = os.clock()

local sum = 0
for i = 1, iterations do
    sum = sum + i * 2 - 1
end

local elapsed = os.clock() - start

print(string.format("Loop sum: %d", sum))
print(string.format("Time: %.4f seconds", elapsed))
