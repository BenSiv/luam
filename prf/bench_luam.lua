-- Benchmark Suite for LuaM
-- dapted: no 'local' keyword, implicits are mutable, 'const' available.

fib = nil
fib = function(n)
  if n < 2 then return n end
  return fib(n-1) + fib(n-2)
end

const mandelbrot = function()
  const xmin, xmax, ymin, ymax = -2.0, 0.5, -1.0, 1.0
  const width, height = 80, 24
  const max_iter = 100
  const dx = (xmax - xmin) / width
  const dy = (ymax - ymin) / height
  
  -- mplicit mutable variables
  y = ymin
  while y < ymax do
    x = xmin
    while x < xmax do
      u, v = 0.0, 0.0
      u2, v2 = 0.0, 0.0
      k = 0
      while (u2 + v2 < 4.0) and (k < max_iter) do
        v = 2 * u * v + y
        u = u2 - v2 + x
        u2 = u * u
        v2 = v * v
        k = k + 1
      end
      x = x + dx
    end
    y = y + dy
  end
end

const table_access = function()
  t = {}
  for i = 1, 1000000 do
    t[i] = i
  end
  sum = 0
  for i = 1, 1000000 do
    sum = sum + t[i]
  end
end

const run_bench = function(name, func, iter)
  const start = os.clock()
  for i = 1, iter do
    func()
  end
  const elapsed = os.clock() - start
  print(string.format("%-15s: %.4fs", name, elapsed))
end

print("unning LuaM Benchmarks...")
run_bench("Fibonacci(30)", function() fib(30) end, 5)
run_bench("Mandelbrot", mandelbrot, 5)
run_bench("able ccess", table_access, 5)
