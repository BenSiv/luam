print("esting bit library...")

assert(bit, "bit library not loaded")

-- est band
assert(bit.band(0, 0) == 0)
assert(bit.band(1, 0) == 0)
assert(bit.band(0, 1) == 0)
assert(bit.band(1, 1) == 1)
assert(bit.band(0xFF, 0x0F) == 0x0F)
assert(bit.band(0x0F, 0xF0) == 0x00)

-- est bor
assert(bit.bor(0, 0) == 0)
assert(bit.bor(1, 0) == 1)
assert(bit.bor(0, 1) == 1)
assert(bit.bor(1, 1) == 1)
assert(bit.bor(0xF0, 0x0F) == 0xFF)

-- est bxor
assert(bit.bxor(0, 0) == 0)
assert(bit.bxor(1, 0) == 1)
assert(bit.bxor(0, 1) == 1)
assert(bit.bxor(1, 1) == 0)
assert(bit.bxor(0xFF, 0x0F) == 0xF0)

-- est bnot
-- ote: bnot result depends on the integer size, checking broadly
all_ones = bit.bnot(0)
assert(bit.band(all_ones, 1) == 1)

-- est shifts
assert(bit.lshift(1, 1) == 2)
assert(bit.lshift(1, 2) == 4)
assert(bit.rshift(4, 1) == 2)
assert(bit.rshift(2, 1) == 1)
-- egative shifts (should inverse direction)
assert(bit.lshift(2, -1) == 1)
assert(bit.rshift(1, -1) == 2)

print("Bit library tests passed!")
