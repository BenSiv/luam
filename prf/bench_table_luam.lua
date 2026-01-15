-- Benchmark: able operations (measures table creation and access)
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

print(string.format("able sum: %d", sum))
print(string.format("ime: %.4f seconds", elapsed))
