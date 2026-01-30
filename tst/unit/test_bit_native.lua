const bit = require("bit")

print(">>> Testing bit library... <<<")

-- Test band
assert(bit.band(0xFF, 0x0F) == 0x0F, "band failed")
assert(bit.band(0xFF, 0x00) == 0x00, "band failed")
assert(bit.band(0xAA, 0x55) == 0x00, "band failed")

-- Test bor
assert(bit.bor(0xF0, 0x0F) == 0xFF, "bor failed")
assert(bit.bor(0xAA, 0x55) == 0xFF, "bor failed")
assert(bit.bor(0x00, 0x00) == 0x00, "bor failed")

-- Test bxor
assert(bit.bxor(0xFF, 0x0F) == 0xF0, "bxor failed")
assert(bit.bxor(0xAA, 0x55) == 0xFF, "bxor failed")
assert(bit.bxor(0xFF, 0xFF) == 0x00, "bxor failed")

-- Test bnot
assert(bit.band(bit.bnot(0x00), 0xFFFFFFFF) == 0xFFFFFFFF, "bnot failed")
assert(bit.band(bit.bnot(0xFFFFFFFF), 0xFFFFFFFF) == 0, "bnot failed")

-- Test lshift
assert(bit.lshift(1, 4) == 16, "lshift failed")
assert(bit.lshift(0xF, 4) == 0xF0, "lshift failed")
assert(bit.lshift(0xF, -4) == 0, "lshift (right) failed")

-- Test rshift
assert(bit.rshift(16, 4) == 1, "rshift failed")
assert(bit.rshift(0xF0, 4) == 0xF, "rshift failed")
assert(bit.rshift(0xF, -4) == 0xF0, "rshift (left) failed")

print(">>> bit library tests PASSED! <<<")
