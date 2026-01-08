-- Benchmark: Recursive Fibonacci (measures function call overhead)
-- luam compatible version

function fib(args)
    n = args[1] or args.n
    if n < 2 then return n end
    return fib({n - 1}) + fib({n - 2})
end

iterations = 35
start = os.clock()
result = fib({iterations})
elapsed = os.clock() - start

print(string.format({"Fibonacci(%d) = %d", iterations, result})[1])
print(string.format({"Time: %.4f seconds", elapsed})[1])
