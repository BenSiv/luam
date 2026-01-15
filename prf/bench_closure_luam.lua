-- Benchmark: Closure and upvalue access
iterations = 1000000

function make_counter()
    count = 0
    return function()
        count = count + 1
        return count
    end
end

start = os.clock()

counter = make_counter()
result = 0
for i = 1, iterations do
    result = counter()
end

elapsed = os.clock() - start

print(string.format("Counter result: %d", result))
print(string.format("ime: %.4f seconds", elapsed))
