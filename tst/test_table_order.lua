-- Table iteration order: integer keys in ascending order, then every other
-- key in the order it was added. Overwriting a key keeps its place;
-- deleting it and adding it again moves it to the end. See
-- doc/table_order.md.

function keys_of(t)
    out = {}
    for k, _ in pairs(t) do
        table.insert(out, k)
    end
    return out
end

function show(list)
    parts = {}
    for _, k in ipairs(list) do
        table.insert(parts, type(k) .. ":" .. tostring(k))
    end
    return table.concat(parts, " ")
end

function check(t, expected, label)
    got = show(keys_of(t))
    want = show(expected)
    assert(got == want, label .. "\n  got:  " .. got .. "\n  want: " .. want)
end

-- Records keep source and insertion order
check({zeta = 1, alpha = 2, mid = 3}, {"zeta", "alpha", "mid"}, "constructor order")

t = {}
t.b = 1
t.a = 2
t.c = 3
check(t, {"b", "a", "c"}, "insertion order")

t.b = 9
check(t, {"b", "a", "c"}, "overwrite keeps position")

t.a = nil
check(t, {"b", "c"}, "delete")
t.a = 1
check(t, {"b", "c", "a"}, "delete and add again goes to the end")

-- Integers ascending (negatives and zero included), then the rest
t = {}
t.name = "x"
t[3] = "c"
t[-1] = "neg"
t[1] = "a"
t["1"] = "string one"
t[0] = "zero"
t.id = 7
t[2.5] = "half"
check(t, {-1, 0, 1, 3, "name", "1", "id", 2.5}, "mixed keys")

check({"a", "b", "c"}, {1, 2, 3}, "sequence")
check({x = 1, "a", y = 2, "b"}, {1, 2, "x", "y"}, "record with a list part")

t = {}
t[10] = true
t.s = true
t[1] = true
t[3] = true
t[2] = true
t[-5] = true
t[0] = true
t[2 ^ 40] = true
t[-(2 ^ 40)] = true
check(t, {-(2 ^ 40), -5, 0, 1, 2, 3, 10, 2 ^ 40, "s"}, "integers across the array part")

-- Sparse integers added in random order still come out ascending
math.randomseed(7)
t = {}
seen = {}
added = {}
while #added < 300 do
    k = math.random(-100000, 100000)
    if seen[k] == nil then
        seen[k] = true
        table.insert(added, k)
        t[k] = k
        t["s" .. k] = k
    end
end
expected = {}
for _, k in ipairs(added) do
    table.insert(expected, k)
end
table.sort(expected)
for _, k in ipairs(added) do
    table.insert(expected, "s" .. k)
end
check(t, expected, "sparse integers in random order")

-- Many string keys keep their order across every resize
t = {}
expected = {}
for i = 1, 10000 do
    t["k" .. i] = i
    table.insert(expected, "k" .. i)
end
check(t, expected, "10000 keys across resizes")

-- Model check: random sets and deletes against a plain model of the rule
function is_integer(k)
    return type(k) == "number" and math.floor(k) == k
end

function model_keys(live, others)
    ints = {}
    rest = {}
    for k, _ in pairs(live) do
        if is_integer(k) then
            table.insert(ints, k)
        end
    end
    table.sort(ints)
    for _, k in ipairs(others) do
        table.insert(rest, k)
    end
    for _, k in ipairs(rest) do
        table.insert(ints, k)
    end
    return ints
end

pool = {}
for i = 1, 40 do
    table.insert(pool, "s" .. i)
end
for i = -10, 60 do
    table.insert(pool, i)
end
for i = 1, 15 do
    table.insert(pool, i + 0.5)
end
table.insert(pool, true)
table.insert(pool, false)

math.randomseed(12345)
t = {}
live = {}
others = {}
for step = 1, 20000 do
    k = pool[math.random(1, #pool)]
    if math.random() < 0.6 then
        if live[k] == nil then
            live[k] = true
            if is_integer(k) == false then
                table.insert(others, k)
            end
        end
        t[k] = step
    else
        if live[k] != nil then
            live[k] = nil
            for i, o in ipairs(others) do
                if o == k then
                    table.remove(others, i)
                    break
                end
            end
        end
        t[k] = nil
    end
    if step % 7 == 0 then
        check(t, model_keys(live, others), "model check at step " .. step)
    end
end
check(t, model_keys(live, others), "model check at the end")

-- Traversal: clearing and overwriting while iterating visit every key once
t = {}
for i = 1, 500 do
    t["k" .. i] = i
    t[i * 3] = i
end
count = 0
for k, _ in pairs(t) do
    t[k] = nil
    count = count + 1
end
assert(count == 1000, "clearing traversal visited " .. count)
assert(next(t) == nil, "table not empty after clearing traversal")

t = {a = 1, b = 2, c = 3, [5] = 4}
count = 0
for k, v in pairs(t) do
    t[k] = v * 10
    count = count + 1
end
assert(count == 4, "overwriting traversal visited " .. count)
check(t, {5, "a", "b", "c"}, "overwriting traversal keeps order")

-- next() from an arbitrary key
t = {}
t.a = 1
t.b = 2
t.c = 3
t[-1] = 0
t[1] = 0
assert(next(t, "b") == "c", "next after b")
assert(next(t, -1) == 1, "next after -1")
assert(next(t, 1) == "a", "next after 1")
assert(next(t, "c") == nil, "next after the last key")
t.b = nil
assert(next(t, "b") == "c", "next after a key cleared mid-traversal")
ok, err = pcall(next, t, "nope")
assert(ok == false and string.find(err, "invalid key") != nil, "next with a missing key should fail")

-- Churn: deleting and re-adding one key in a full table stays O(1)
t = {}
for i = 1, 1000 do
    t["k" .. i] = i
end
started = os.clock()
for i = 1, 200000 do
    t.k500 = nil
    t.k500 = i
end
elapsed = os.clock() - started
assert(elapsed < 2, "churn took " .. elapsed .. " s")
order = keys_of(t)
assert(order[#order] == "k500" and order[1] == "k1" and order[499] == "k499" and order[500] == "k501",
       "churned key should be last, others in order")

-- Weak keys: collected entries drop out, survivors keep their order
weak = setmetatable({}, {__mode = "k"})
kept = {}
for i = 1, 100 do
    key = {}
    weak[key] = i
    if i % 2 == 0 then
        table.insert(kept, key)
    end
end
key = nil
collectgarbage()
collectgarbage()
survivors = keys_of(weak)
assert(#survivors == 50, "weak table kept " .. #survivors)
for i, k in ipairs(kept) do
    assert(survivors[i] == k, "weak survivor " .. i .. " out of order")
end

-- Length and ipairs are unchanged
t = {1, 2, 3}
t.x = 1
assert(#t == 3, "length")
n = 0
for _, v in ipairs(t) do
    n = n + v
end
assert(n == 6, "ipairs")

-- JSON output follows insertion order
json = dofile("lib/dkjson/init.lua")
t = {}
t.zeta = 1
t.alpha = 2
t.mid = {b = true, a = false}
assert(json.encode(t) == "{\"zeta\":1,\"alpha\":2,\"mid\":{\"b\":true,\"a\":false}}", "json order: " .. json.encode(t))
decoded = json.decode("{\"z\":1,\"y\":2,\"x\":3}")
assert(json.encode(decoded) == "{\"z\":1,\"y\":2,\"x\":3}", "json round trip order: " .. json.encode(decoded))

print("table order tests passed")
