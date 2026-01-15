-- Benchmark: Closure and upvalue access
local iterations = 1000000

local function make_counter()
    local count = 0
    return function()
        count = count + 1
        return count
    end
end

local start = os.clock()

local counter = make_counter()
local result = 0
for i = 1, iterations do
    result = counter()
end

local elapsed = os.clock() - start

print(string.format("Counter result: %d", result))
print(string.format("ime: %.4f seconds", elapsed))
