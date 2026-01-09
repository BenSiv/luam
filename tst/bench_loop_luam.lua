-- Benchmark: Loop and arithmetic (measures basic VM operations)
-- luam compatible version

iterations = 10000000

start = os.clock()

sum = 0
for i = 1, iterations do
    sum = sum + i * 2 - 1
end

elapsed = os.clock() - start

print(string.format("Loop sum: %d", sum))
print(string.format("Time: %.4f seconds", elapsed))
