print("esting struct library...")

assert(string.pack, "string.pack not found")
assert(string.unpack, "string.unpack not found")

-- est Little Endian nteger (i4)
packed = string.pack("<i", 0x12345678)
assert(#packed == 4)
b1, b2, b3, b4 = string.byte(packed, 1, 4)
-- Little endian: 78 56 34 12
print("Bytes:", b1, b2, b3, b4)
assert(b1 == 0x78)
assert(b4 == 0x12)

val, pos = string.unpack("<i", packed)
print("al:", val, "Pos:", pos)
assert(val == 0x12345678)
assert(pos == 5)

-- est Big Endian nteger (i4)
packed2 = string.pack(">i", 0x11223344)
print("Packed Length:", #packed2)
b1, b2, b3, b4 = string.byte(packed2, 1, 4)
-- Big endian: 11 22 33 44
print("Big Endian Bytes:", b1, b2, b3, b4)
assert(b1 == 0x11)
assert(b4 == 0x44)

val, pos = string.unpack(">i", packed2)
assert(val == 0x11223344)

-- est String with header (s)
str = "hello"
-- pack("s") -> 4-byte length + string
packed = string.pack("<s", str)
assert(#packed == 4 + 5)
val, pos = string.unpack("<s", packed)
assert(val == str)
assert(pos == 10)

print("Struct library tests passed!")
