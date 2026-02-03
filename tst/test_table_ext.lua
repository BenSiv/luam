print("esting table extensions...")

-- est table.new
if table.new != nil then
    t = table.new(10, 0)
    assert(type(t) == "table")
    assert(#t == 0) -- length is 0, but capacity is reserved
else
    print("Skipping table.new test")
end

-- est table.move
if table.move != nil then
    t1 = {1, 2, 3, 4, 5}
    t2 = {}

    -- Move t1[1..3] to t2[1..3]
    table.move(t1, 1, 3, 1, t2)
    assert(t2[1] == 1 and t2[2] == 2 and t2[3] == 3)
    assert(t2[4] == nil)

    -- Move within same table (overlap)
    -- t1 = {1, 2, 3, 4, 5} -> move 1..2 to 2..3 -> {1, 1, 2, 4, 5}
    table.move(t1, 1, 2, 2)
    assert(t1[1] == 1)
    assert(t1[2] == 1)
    assert(t1[3] == 2)
    assert(t1[4] == 4)
else
    print("Skipping table.move test")
end

print("able library tests passed!")
