-- Benchmark: Table operations (measures table creation and access)
-- luam compatible version

iterations = 1000000

start = os.clock()

mutable t = {}
for i = 1, iterations do
    t[i] = i * 2
end

mutable sum = 0
for i = 1, iterations do
    sum = sum + t[i]
end

elapsed = os.clock() - start

print(string.format({"Table sum: %d", sum})[1])
print(string.format({"Time: %.4f seconds", elapsed})[1])
