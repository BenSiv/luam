# Table traversal order

In Lua 5.1 the order of `pairs` and `next` is whatever the hash table happens
to hold: stable for one build, but arbitrary, and adding one key can reorder
all the others. Luam defines it:

> **Integer keys in ascending order, then every other key in the order it was
> added.**

```lua
t = {}
t.name = "x"
t[3] = "c"
t[-1] = "neg"
t[1] = "a"
t["1"] = "string one"  -- a string: a separate key, never converted
t[0] = "zero"
t.id = 7
t[2.5] = "half"        -- not an integer: in the order it was added

for k, v in pairs(t) do print(type(k), k) end
-- number  -1
-- number  0
-- number  1
-- number  3
-- string  name
-- string  1
-- string  id
-- number  2.5
```

So records come out in the order they were written, lists in index order,
and JSON encoded with `dkjson` keeps the order its tables were built in
(including tables decoded from JSON).

## The rules

- **Integer keys** are numbers with no fractional part, negatives and zero
  included. They always come first, in ascending order, whether they live in
  the array part or the hash part.
- **Every other key** (strings, non-integer numbers, booleans, tables,
  functions, userdata) comes after them, in the order it was added.
- **Overwriting** an existing key keeps its place.
- **Deleting** a key (`t[k] = nil`) and adding it again moves it to the end.
  Integer keys have no "end": they stay in ascending order.
- **No conversion.** `t[1]` and `t["1"]` are different keys, as in Lua 5.1.
  The rule only says where each kind of key comes in the order.
- **During a traversal**, assigning to existing fields, including clearing
  them, is allowed and every key is visited once, as in Lua 5.1. Adding new
  keys during a traversal is still undefined.
- **`next(t, k)`** works from any key in the table, including one just
  cleared.
- **Weak tables**: entries the collector removes drop out; the rest keep
  their order.
- `#t` and `ipairs` are unchanged.

## How it works

A table keeps Lua 5.1's two parts. The array part holds integer keys
`1..n`; any integer key in the hash part is below 1 or above `n`. The hash
part's node block is followed by an `int` order array, one slot per node:

- non-integer keys take slots from the front, in the order they are added;
- integer keys take slots from the back. They are sorted lazily, before a
  traversal, only if a key was added out of ascending order since the last
  sort;
- each node records its slot in the padding of its key, so a node stays 40
  bytes on 64-bit;
- a replaced or moved key leaves a tombstone (-1) in its old slot. When the
  order array runs out of slots, the table is rebuilt without tombstones;
  if it filled up through tombstones, the rebuilt hash part has room for
  twice its live keys, so a table that keeps deleting and re-adding keys
  rebuilds at most once per as many insertions as it has keys.

Traversal then goes: integer keys below 1, the array part, integer keys
above it, then the other keys. The implementation is in `src/ltable.c`; the
rules are tested in `tst/test_table_order.lua`, including a check of 20000
random sets and deletes against a plain model of the rule.

Because the order no longer depends on the hash function, the hash can be
changed later (for example seeded per process, against hash flooding)
without changing any program's output.

## Cost

Memory: 4 more bytes per hash slot (the order array, about 10% of the hash
part) and 8 more bytes per table (72 instead of 64). Array parts are
unchanged.

Speed, best of 5 runs against the same commit without the change (64-bit
Linux, `-O2`; the machine varies by about ±10% between runs):

| Workload | Change |
|---|---|
| String-key lookup | about the same |
| `pairs` over 200k string keys | 5-15% faster |
| `pairs` over small records | about the same |
| Array fill, read, `pairs` | about the same to +9% |
| Creating small records (4-5 string keys) | about +10% |
| Building a 200k-key table | +13% |
| Inserting 100k sparse integer keys | +14% |
| Deleting and re-adding the same key, repeatedly | +36% (the key moves to the end each time) |
| Cache-like churn (new keys in, old keys out) | about 20% faster |
| Adding a key to a 100k-sparse-integer table, then `pairs`, repeated | about 3x: each traversal after an out-of-order addition re-sorts the integer keys (about 8 ms per 100k) |

The last row is the one real trade: a large table of sparse integer keys
that is modified and traversed in alternation pays for a sort per
traversal. Building such a table once and traversing it any number of times
sorts once.
