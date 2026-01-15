-- Benchmark: able operations (measures table creation and access)
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

print(string.format("able sum: %d", sum))
print(string.format("ime: %.4f seconds", elapsed))
