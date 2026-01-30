// Lua tables (hash)
// Migrated from ltable.c/h
// Implementation of tables with array part and hash part
package core

import "core:c"
import "core:mem"

// Max size of array part is 2^MAXBITS
MAXBITS :: 26
MAXASIZE :: 1 << MAXBITS

// Node accessors
gnode :: #force_inline proc(t: ^Table, i: int) -> ^Node {
	return &t.node[i]
}

gkey :: #force_inline proc(n: ^Node) -> ^TValue {
	return cast(^TValue)&n.i_key.nk
}

gval :: #force_inline proc(n: ^Node) -> ^TValue {
	return &n.i_val
}

gnext :: #force_inline proc(n: ^Node) -> ^Node {
	return n.i_key.nk.next
}

set_gnext :: #force_inline proc(n: ^Node, next: ^Node) {
	n.i_key.nk.next = next
}

key2tval :: #force_inline proc(n: ^Node) -> ^TValue {
	return &n.i_key.tvk
}

// Number of ints inside a lua_Number
numints :: size_of(lua_Number) / size_of(u32)

// Dummy node for empty hash parts
dummynode_: Node = {
	i_val = {{nil}, LUA_TNIL},
	i_key = {nk = {{nil}, LUA_TNIL, nil}},
}
dummynode :: &dummynode_

// FFI to C functions
@(private)
foreign import lua_core "system:lua"

@(private)
foreign lua_core {
	luaG_runerror_c :: proc(L: ^lua_State, fmt: cstring, #c_vararg args: ..any) ---
	luaC_link_c :: proc(L: ^lua_State, o: ^GCObject, tt: c.int) ---
	luaC_barriert_c :: proc(L: ^lua_State, t: ^Table, key: ^TValue) ---
	luaM_malloc_c :: proc(L: ^lua_State, size: c.size_t) -> rawptr ---
	luaM_realloc_c :: proc(L: ^lua_State, block: rawptr, osize: c.size_t, nsize: c.size_t) -> rawptr ---
}

// Hash function for numbers
@(private)
hashnum :: proc(t: ^Table, n: lua_Number) -> ^Node {
	// Avoid problems with -0
	if n == 0 {
		return gnode(t, 0)
	}

	// Hash the bytes of the number
	a: [numints]u32
	mem.copy(&a, &n, size_of(lua_Number))

	sum := a[0]
	for i in 1 ..< numints {
		sum += a[i]
	}

	// hashmod: avoid power of 2 for numbers
	sz := sizenode(t) - 1
	if sz < 1 {sz = 1}
	return gnode(t, int(sum) % sz)
}

// Hash macros converted to procs
hashpow2 :: #force_inline proc(t: ^Table, n: u32) -> ^Node {
	return gnode(t, lmod(uint(n), sizenode(t)))
}

hashstr :: #force_inline proc(t: ^Table, str: ^TString) -> ^Node {
	return hashpow2(t, str.tsv.hash)
}

hashboolean :: #force_inline proc(t: ^Table, p: c.int) -> ^Node {
	return hashpow2(t, u32(p))
}

hashpointer :: #force_inline proc(t: ^Table, p: rawptr) -> ^Node {
	sz := sizenode(t) - 1
	if sz < 1 {sz = 1}
	return gnode(t, int(cast(uintptr)p) % sz)
}

// Get raw TString from TValue
rawtsvalue :: #force_inline proc(o: ^TValue) -> ^TString {
	return &o.value.gc.ts
}

// Main position of an element (hash value index)
mainposition :: proc(t: ^Table, key: ^TValue) -> ^Node {
	switch key.tt {
	case LUA_TNUMBER:
		return hashnum(t, key.value.n)
	case LUA_TSTRING:
		return hashstr(t, rawtsvalue(key))
	case LUA_TBOOLEAN:
		return hashboolean(t, key.value.b)
	case LUA_TLIGHTUSERDATA:
		return hashpointer(t, key.value.p)
	case:
		return hashpointer(t, key.value.gc)
	}
}

// Check if key is appropriate for array part, return index or -1
arrayindex :: proc(key: ^TValue) -> int {
	if ttisnumber(key) {
		n := key.value.n
		k := int(n)
		if lua_Number(k) == n {
			return k
		}
	}
	return -1
}

// Set array vector
@(private)
setarrayvector :: proc(L: ^lua_State, t: ^Table, size: int) {
	old_size := int(t.sizearray)
	if size > old_size {
		// Grow array
		t.array = cast([^]TValue)luaM_realloc_c(
			L,
			t.array,
			c.size_t(old_size) * size_of(TValue),
			c.size_t(size) * size_of(TValue),
		)
		// Initialize new elements to nil
		for i in old_size ..< size {
			setnilvalue(&t.array[i])
		}
	} else if size < old_size {
		// Shrink array
		t.array = cast([^]TValue)luaM_realloc_c(
			L,
			t.array,
			c.size_t(old_size) * size_of(TValue),
			c.size_t(size) * size_of(TValue),
		)
	}
	t.sizearray = c.int(size)
}

// Set node vector
@(private)
setnodevector :: proc(L: ^lua_State, t: ^Table, size: int) {
	if size == 0 {
		t.node = dummynode
		t.lsizenode = 0
	} else {
		lsize := ceillog2(u32(size))
		if lsize > MAXBITS {
			luaG_runerror_c(L, "table overflow")
		}
		actual_size := twoto(u8(lsize))
		t.node = cast(^Node)luaM_malloc_c(L, c.size_t(actual_size) * size_of(Node))
		for i in 0 ..< actual_size {
			n := gnode(t, i)
			set_gnext(n, nil)
			setnilvalue(gkey(n))
			setnilvalue(gval(n))
		}
		t.lsizenode = u8(lsize)
	}
	t.lastfree = gnode(t, sizenode(t))
}

// Create new table
luaH_new :: proc(L: ^lua_State, narray: int, nhash: int) -> ^Table {
	t := cast(^Table)luaM_malloc_c(L, size_of(Table))
	luaC_link_c(L, obj2gco(t), LUA_TTABLE)
	t.metatable = nil
	t.flags = 0xFF // all tag methods absent initially
	t.array = nil
	t.sizearray = 0
	t.lsizenode = 0
	t.node = dummynode
	setarrayvector(L, t, narray)
	setnodevector(L, t, nhash)
	return t
}

// Free table
luaH_free :: proc(L: ^lua_State, t: ^Table) {
	if t.node != dummynode {
		luaM_realloc_c(L, t.node, c.size_t(sizenode(t)) * size_of(Node), 0)
	}
	if t.array != nil && t.sizearray > 0 {
		luaM_realloc_c(L, t.array, c.size_t(t.sizearray) * size_of(TValue), 0)
	}
	luaM_realloc_c(L, t, size_of(Table), 0)
}

// Get by integer key
luaH_getnum :: proc(t: ^Table, key: int) -> ^TValue {
	// Check array part first
	if u32(key - 1) < u32(t.sizearray) {
		return &t.array[key - 1]
	}

	// Search hash part
	nk := lua_Number(key)
	n := hashnum(t, nk)
	for n != nil {
		k := gkey(n)
		if ttisnumber(k) && k.value.n == nk {
			return gval(n)
		}
		n = gnext(n)
	}
	return nilobject
}

// Get by string key
luaH_getstr :: proc(t: ^Table, key: ^TString) -> ^TValue {
	n := hashstr(t, key)
	for n != nil {
		k := gkey(n)
		if ttisstring(k) && rawtsvalue(k) == key {
			return gval(n)
		}
		n = gnext(n)
	}
	return nilobject
}

// Main get function
luaH_get :: proc(t: ^Table, key: ^TValue) -> ^TValue {
	switch key.tt {
	case LUA_TNIL:
		return nilobject
	case LUA_TSTRING:
		return luaH_getstr(t, rawtsvalue(key))
	case LUA_TNUMBER:
		n := key.value.n
		k := int(n)
		if lua_Number(k) == n {
			return luaH_getnum(t, k)
		}
		// Fall through to generic hash lookup
		fallthrough
	case:
		node := mainposition(t, key)
		for node != nil {
			if rawequalObj(key2tval(node), key) {
				return gval(node)
			}
			node = gnext(node)
		}
		return nilobject
	}
}

// Get free position in hash part
@(private)
getfreepos :: proc(t: ^Table) -> ^Node {
	for cast(uintptr)t.lastfree > cast(uintptr)t.node {
		t.lastfree = cast(^Node)(cast(uintptr)t.lastfree - size_of(Node))
		if ttisnil(gkey(t.lastfree)) {
			return t.lastfree
		}
	}
	return nil
}

// Forward declaration for newkey
newkey :: proc(L: ^lua_State, t: ^Table, key: ^TValue) -> ^TValue

// Set by general key
luaH_set :: proc(L: ^lua_State, t: ^Table, key: ^TValue) -> ^TValue {
	p := luaH_get(t, key)
	t.flags = 0
	if p != nilobject {
		return cast(^TValue)p
	}

	if ttisnil(key) {
		luaG_runerror_c(L, "table index is nil")
	}
	// Note: NaN check would go here

	return newkey(L, t, key)
}

// Set by integer key
luaH_setnum :: proc(L: ^lua_State, t: ^Table, key: int) -> ^TValue {
	p := luaH_getnum(t, key)
	if p != nilobject {
		return cast(^TValue)p
	}

	k: TValue
	setnvalue(&k, lua_Number(key))
	return newkey(L, t, &k)
}

// Set by string key
luaH_setstr :: proc(L: ^lua_State, t: ^Table, key: ^TString) -> ^TValue {
	p := luaH_getstr(t, key)
	if p != nilobject {
		return cast(^TValue)p
	}

	k: TValue
	setgcvalue(&k, obj2gco(key), LUA_TSTRING)
	return newkey(L, t, &k)
}

// Resize array part
luaH_resizearray :: proc(L: ^lua_State, t: ^Table, nasize: int) {
	nsize := 0 if t.node == dummynode else sizenode(t)
	resize(L, t, nasize, nsize)
}

// Helper for resize - rehash part
@(private)
rehash :: proc(L: ^lua_State, t: ^Table, ek: ^TValue) {
	// Simplified rehash - just double the size
	old_size := sizenode(t)
	new_size := old_size * 2 if old_size > 0 else 1
	resize(L, t, int(t.sizearray), new_size)
}

// Resize table
@(private)
resize :: proc(L: ^lua_State, t: ^Table, nasize: int, nhsize: int) {
	oldasize := int(t.sizearray)
	oldhsize := int(t.lsizenode)
	nold := t.node

	// Grow array part if needed
	if nasize > oldasize {
		setarrayvector(L, t, nasize)
	}

	// Create new hash part
	setnodevector(L, t, nhsize)

	// Shrink array part if needed
	if nasize < oldasize {
		t.sizearray = c.int(nasize)
		// Re-insert elements from vanishing slice
		for i in nasize ..< oldasize {
			if !ttisnil(&t.array[i]) {
				slot := luaH_setnum(L, t, i + 1)
				setobj(slot, &t.array[i])
			}
		}
		// Shrink
		t.array = cast([^]TValue)luaM_realloc_c(
			L,
			t.array,
			c.size_t(oldasize) * size_of(TValue),
			c.size_t(nasize) * size_of(TValue),
		)
	}

	// Re-insert elements from old hash part
	old_count := twoto(u8(oldhsize))
	for i := old_count - 1; i >= 0; i -= 1 {
		old := &nold[i]
		if !ttisnil(gval(old)) {
			slot := luaH_set(L, t, key2tval(old))
			setobj(slot, gval(old))
		}
	}

	// Free old hash part
	if nold != dummynode {
		luaM_realloc_c(L, nold, c.size_t(old_count) * size_of(Node), 0)
	}
}

// Insert new key
newkey :: proc(L: ^lua_State, t: ^Table, key: ^TValue) -> ^TValue {
	mp := mainposition(t, key)

	if !ttisnil(gval(mp)) || mp == dummynode {
		n := getfreepos(t)
		if n == nil {
			rehash(L, t, key)
			return luaH_set(L, t, key)
		}

		othern := mainposition(t, key2tval(mp))
		if othern != mp {
			// Colliding node is out of its main position
			// Find previous node
			for gnext(othern) != mp {
				othern = gnext(othern)
			}
			set_gnext(othern, n)
			n^ = mp^
			set_gnext(mp, nil)
			setnilvalue(gval(mp))
		} else {
			// Colliding node is in its own main position
			set_gnext(n, gnext(mp))
			set_gnext(mp, n)
			mp = n
		}
	}

	// Set key
	k := gkey(mp)
	k.value = key.value
	k.tt = key.tt
	luaC_barriert_c(L, t, key)

	return gval(mp)
}

// Find boundary (# operator)
luaH_getn :: proc(t: ^Table) -> int {
	j := int(t.sizearray)
	if j > 0 && ttisnil(&t.array[j - 1]) {
		// Binary search in array part
		i := 0
		for j - i > 1 {
			m := (i + j) / 2
			if ttisnil(&t.array[m - 1]) {
				j = m
			} else {
				i = m
			}
		}
		return i
	}

	if t.node == dummynode {
		return j
	}

	// Search in hash part
	return unbound_search(t, u32(j))
}

@(private)
unbound_search :: proc(t: ^Table, j: u32) -> int {
	i := j
	new_j := j + 1

	// Find bounds
	for !ttisnil(luaH_getnum(t, int(new_j))) {
		i = new_j
		new_j *= 2
		if new_j > u32(MAX_INT) {
			// Overflow - linear search
			ii := u32(1)
			for !ttisnil(luaH_getnum(t, int(ii))) {
				ii += 1
			}
			return int(ii - 1)
		}
	}

	// Binary search between i and j
	for new_j - i > 1 {
		m := (i + new_j) / 2
		if ttisnil(luaH_getnum(t, int(m))) {
			new_j = m
		} else {
			i = m
		}
	}
	return int(i)
}

// Next for table iteration
luaH_next :: proc(L: ^lua_State, t: ^Table, key: StkId) -> int {
	i := findindex(L, t, key)

	// Search array part
	for i += 1; i < int(t.sizearray); i += 1 {
		if !ttisnil(&t.array[i]) {
			setnvalue(key, lua_Number(i + 1))
			setobj(cast(^TValue)(cast(uintptr)key + size_of(TValue)), &t.array[i])
			return 1
		}
	}

	// Search hash part
	for i -= int(t.sizearray); i < sizenode(t); i += 1 {
		n := gnode(t, i)
		if !ttisnil(gval(n)) {
			setobj(key, key2tval(n))
			setobj(cast(^TValue)(cast(uintptr)key + size_of(TValue)), gval(n))
			return 1
		}
	}

	return 0
}

@(private)
findindex :: proc(L: ^lua_State, t: ^Table, key: StkId) -> int {
	if ttisnil(key) {
		return -1
	}

	i := arrayindex(key)
	if i > 0 && i <= int(t.sizearray) {
		return i - 1
	}

	n := mainposition(t, key)
	for n != nil {
		if rawequalObj(key2tval(n), key) {
			idx := cast(int)((cast(uintptr)n - cast(uintptr)gnode(t, 0)) / size_of(Node))
			return idx + int(t.sizearray)
		}
		// Check for dead key
		k := gkey(n)
		if k.tt == LUA_TDEADKEY && iscollectable(key) && k.value.gc == key.value.gc {
			idx := cast(int)((cast(uintptr)n - cast(uintptr)gnode(t, 0)) / size_of(Node))
			return idx + int(t.sizearray)
		}
		n = gnext(n)
	}

	luaG_runerror_c(L, "invalid key to 'next'")
	return 0
}
