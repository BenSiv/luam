-- Benchmark Suite for Lua 5.1

local function fib(n)
  if n < 2 then return n end
  return fib(n-1) + fib(n-2)
end

local function mandelbrot()
  local xmin, xmax, ymin, ymax = -2.0, 0.5, -1.0, 1.0
  local width, height = 80, 24
  local max_iter = 100
  local dx = (xmax - xmin) / width
  local dy = (ymax - ymin) / height

  local y = ymin
  while y < ymax do
    local x = xmin
    while x < xmax do
      local u, v = 0.0, 0.0
      local u2, v2 = 0.0, 0.0
      local k = 0
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

local function table_access()
  local t = {}
  for i = 1, 1000000 do
    t[i] = i
  end
  local sum = 0
  for i = 1, 1000000 do
    sum = sum + t[i]
  end
end

local function run_bench(name, func, iter)
  local start = os.clock()
  for i = 1, iter do
    func()
  end
  local elapsed = os.clock() - start
  print(string.format("%-15s: %.4fs", name, elapsed))
end

print("unning Lua 5.1 Benchmarks...")
run_bench("Fibonacci(30)", function() fib(30) end, 5)
run_bench("Mandelbrot", mandelbrot, 5)
run_bench("able ccess", table_access, 5)
