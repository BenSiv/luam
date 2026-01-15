-- Benchmark: ecursive Fibonacci (measures function call overhead)
local function fib(n)
    if n < 2 then return n end
    return fib(n - 1) + fib(n - 2)
end

local iterations = 35
local start = os.clock()
local result = fib(iterations)
local elapsed = os.clock() - start

print(string.format("Fibonacci(%d) = %d", iterations, result))
print(string.format("ime: %.4f seconds", elapsed))
