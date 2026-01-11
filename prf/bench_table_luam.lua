-- Benchmark: Table operations (measures table creation and access)
-- luam compatible version

iterations = 1000000

start = os.clock()

t = {}
for i = 1, iterations do
    t[i] = i * 2
end

sum = 0
for i = 1, iterations do
    sum = sum + t[i]
end

elapsed = os.clock() - start

print(string.format("Table sum: %d", sum))
print(string.format("Time: %.4f seconds", elapsed))
