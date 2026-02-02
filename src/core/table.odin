// Lua tables (hash)
// Implementation of tables with array part and hash part
package core

import "base:runtime"
import "core:c"
import libc "core:c/libc"
import "core:mem"

// Max size of array part is 2^MAXBITS
MAXBITS :: 26
MAXASIZE :: 1 << MAXBITS

// Node accessors
// indexk removed (defined in opcodes.odin)

// Access node at index i
gnode :: #force_inline proc(t: ^Table, i: int) -> ^Node {
	return &mem.ptr_offset(t.node, i)^
}

gkey :: #force_inline proc(n: ^Node) -> ^TValue {
	return cast(^TValue)&n.i_key.nk
}

gval :: #force_inline proc(n: ^Node) -> ^TValue {
	return &n.i_val
}

gnextwoto :: #force_inline proc(x: u8) -> int {return 1 << uint(x)}

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
	i_val = {value = {gc = nil}, tt = LUA_TNIL},
	i_key = {nk = {value = {gc = nil}, tt = LUA_TNIL, next = nil}},
}
dummynode := &dummynode_

// FFI to C functions
foreign import lua_core "../../obj/liblua.a"

foreign lua_core {
	// luaD_throw_c defined in do.odin
	// luaD_call_c defined in do.odin
	@(link_name = "luaC_barrierback")
	luaC_barrierback_c :: proc(L: ^lua_State, t: ^Table) ---
	// luaM_realloc_ is defined in string.odin
	// luaM_malloc defined in func.odin
}

// Hash function for numbers
@(private)
hashnum :: proc(t: ^Table, n: lua_Number) -> ^Node {
	// Avoid problems with -0 and NaN
	if n == 0 || n != n {
		return gnode(t, 0)
	}

	// Hash the bytes of the number
	a: [numints]u32
	local_n := n
	mem.copy(&a, &local_n, size_of(lua_Number))

	sum := a[0]
	for i in 1 ..< numints {
		sum += a[i]
	}

	return hashpow2(t, sum)
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
	return hashpow2(t, u32(uintptr(p)))
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
		t.array = cast([^]TValue)luaM_realloc_(
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
		t.array = cast([^]TValue)luaM_realloc_(
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
	actual_size: int
	if size == 0 {
		t.node = dummynode
		t.lsizenode = 0
		actual_size = 0
	} else {
		lsize := ceillog2(u32(size))
		if lsize > MAXBITS {
			luaG_runerror_c(L, "table overflow")
		}
		actual_size = twoto(u8(lsize))
		t.node = cast(^Node)luaM_malloc(L, c.size_t(actual_size) * size_of(Node))
		for i in 0 ..< actual_size {
			n := gnode(t, i)
			set_gnext(n, nil)
			setnilvalue(gkey(n))
			setnilvalue(gval(n))
		}
		t.lsizenode = u8(lsize)
	}
	t.lastfree = gnode(t, actual_size)
}

// luaH_new is implicitly external but let's export it
@(export, link_name = "luaH_new")
luaH_new :: proc "c" (L: ^lua_State, narray: c.int, nhash: c.int) -> ^Table {
	context = runtime.default_context()
	t := cast(^Table)luaM_malloc(L, size_of(Table))
	luaC_link_c(L, obj2gco(t), LUA_TTABLE)
	t.metatable = nil
	t.flags = 0xFF // all tag methods absent initially
	t.array = nil
	t.sizearray = 0
	t.lsizenode = 0
	t.node = dummynode
	t.gclist = nil // Initialize missing field
	setarrayvector(L, t, int(narray))
	setnodevector(L, t, int(nhash))
	return t
}

// Free table
@(export, link_name = "luaH_free")
luaH_free :: proc "c" (L: ^lua_State, t: ^Table) {
	context = runtime.default_context()
	if t.node != dummynode {
		luaM_realloc_(L, t.node, c.size_t(sizenode(t)) * size_of(Node), 0)
	}
	if t.array != nil && t.sizearray > 0 {
		luaM_realloc_(L, t.array, c.size_t(t.sizearray) * size_of(TValue), 0)
	}
	luaM_realloc_(L, t, size_of(Table), 0)
}

// Get by integer key
@(export, link_name = "luaH_getnum")
luaH_getnum :: proc "c" (t: ^Table, key: c.int) -> ^TValue {
	context = runtime.default_context()
	// Check array part first
	if u32(key - 1) < u32(t.sizearray) {
		return &t.array[key - 1]
	}

	// Search hash part
	nk := lua_Number(key)
	n := hashnum(t, nk)

	if n == dummynode {
		return nilobject
	}

	count := 0
	nodes := t.node
	num_nodes := twoto(t.lsizenode)

	for n != nil {
		if count > 1000 {
			break
		}

		// Bounds check
		offset := (cast(uintptr)n - cast(uintptr)nodes) / size_of(Node)

		if offset >= uintptr(num_nodes) {
			break
		}

		count += 1
		k := gkey(n)

		if ttisnumber(k) && k.value.n == nk {
			return gval(n)
		}

		next_n := gnext(n)
		n = next_n
	}

	return nilobject
}

// Get by string key
@(export, link_name = "luaH_getstr")
luaH_getstr :: proc "c" (t: ^Table, key: ^TString) -> ^TValue {
	context = runtime.default_context()
	n := hashstr(t, key)
	for n != nil {
		k := gkey(n)
		if ttisstring(k) {
			if rawtsvalue(k) == key {
				fmt.printf("DEBUG: luaH_getstr found '%s'\n", getstr(key))
				return gval(n)
			}
			// Fallback check for debug - if hits, interning is broken
			s1 := getstr(rawtsvalue(k))
			s2 := getstr(key)
			if libc.strcmp(s1, s2) == 0 {
				fmt.printf(
					"CRITICAL: String interning failure! different pointers for '%s': %p vs %p\n",
					s1,
					rawtsvalue(k),
					key,
				)
				return gval(n)
			}
		}
		n = gnext(n)
	}
	return nilobject
}

// Main get function
@(export, link_name = "luaH_get")
luaH_get :: proc "c" (t: ^Table, key: ^TValue) -> ^TValue {
	context = runtime.default_context()
	switch key.tt {
	case LUA_TNIL:
		return nilobject
	case LUA_TSTRING:
		return luaH_getstr(t, rawtsvalue(key))
	case LUA_TNUMBER:
		n := key.value.n
		k := int(n)
		if lua_Number(k) == n {
			return luaH_getnum(t, c.int(k))
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

import "core:fmt"
import "core:strings"

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
			// fmt.printf("DEBUG: newkey moving intruder mp=%p to n=%p\n", mp, n)
			for gnext(othern) != mp {
				othern = gnext(othern)
			}
			set_gnext(othern, n)
			n^ = mp^
			set_gnext(mp, nil)
			setnilvalue(gval(mp))
		} else {
			// Colliding node is in its own main position
			// fmt.printf("DEBUG: newkey collision at mp=%p, n=%p is new home\n", mp, n)
			set_gnext(n, gnext(mp))
			set_gnext(mp, n)
			mp = n
		}
	}

	// Set key
	k := gkey(mp)
	k.value = key.value
	k.tt = key.tt
	/*
	if k.tt == LUA_TSTRING {
		fmt.printf("DEBUG: newkey set key '%s' in mp=%p\n", getstr(rawtsvalue(k)), mp)
	} else {
		fmt.printf("DEBUG: newkey set key in mp=%p tt=%d\n", mp, k.tt)
	}
	*/
	luaC_barriert(L, t, key)

	return gval(mp)
}

// Set by general key
@(export, link_name = "luaH_set")
luaH_set :: proc "c" (L: ^lua_State, t: ^Table, key: ^TValue) -> ^TValue {
	context = runtime.default_context()
	p := luaH_get(t, key)
	t.flags = 0
	if p != nilobject {
		return cast(^TValue)p
	}
	return newkey(L, t, key)
}

// Set by integer key
@(export, link_name = "luaH_setnum")
luaH_setnum :: proc "c" (L: ^lua_State, t: ^Table, key: c.int) -> ^TValue {
	context = runtime.default_context()
	p := luaH_getnum(t, key)
	if p != nilobject {
		return cast(^TValue)p
	}

	k: TValue
	setnvalue(&k, lua_Number(key))
	return newkey(L, t, &k)
}

// Set by string key
@(export, link_name = "luaH_setstr")
luaH_setstr :: proc "c" (L: ^lua_State, t: ^Table, key: ^TString) -> ^TValue {
	context = runtime.default_context()
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

// Count integer keys in array part
@(private)
numusearray :: proc(t: ^Table, nums: []int) -> int {
	lg := 0
	ttlg := 1 // 2^lg
	ause := 0 // summation of nums
	i := 1 // count to traverse all array keys

	for lg <= MAXBITS {
		lc := 0 // counter
		lim := ttlg
		if lim > int(t.sizearray) {
			lim = int(t.sizearray)
			if i > lim {
				break
			}
		}

		// Count elements in range (2^(lg-1), 2^lg]
		for i <= lim {
			if !ttisnil(&t.array[i - 1]) {
				lc += 1
			}
			i += 1
		}
		nums[lg] += lc
		ause += lc

		lg += 1
		ttlg *= 2
	}
	return ause
}

// Count integer keys in hash part
@(private)
numusehash :: proc(t: ^Table, nums: []int, pnasize: ^int) -> int {
	totaluse := 0
	ause := 0
	i := sizenode(t)

	for i > 0 {
		i -= 1
		n := gnode(t, i)
		if !ttisnil(gval(n)) {
			k := arrayindex(key2tval(n))
			if k > 0 && k <= MAXASIZE {
				nums[ceillog2(u32(k))] += 1
				ause += 1
			}
			totaluse += 1
		}
	}
	pnasize^ += ause
	return totaluse
}

// Compute optimal array size
@(private)
computesizes :: proc(nums: []int, narray: ^int) -> int {
	a := 0 // number of elements smaller than 2^i
	na := 0 // number of elements to go to array part
	n := 0 // optimal size for array part
	twotoi := 1

	for i := 0; twotoi / 2 < narray^; i += 1 {
		if nums[i] > 0 {
			a += nums[i]
			if a > twotoi / 2 { 	// more than half elements present?
				n = twotoi // optimal size (till now)
				na = a // all elements smaller than n will go to array part
			}
		}
		if a == narray^ {
			break
		}
		twotoi *= 2
	}
	narray^ = n
	return na
}

// Proper rehash with array growth analysis
@(private)
rehash :: proc(L: ^lua_State, t: ^Table, ek: ^TValue) {
	nums: [MAXBITS + 1]int // nums[i] = number of keys between 2^(i-1) and 2^i

	// Reset counts
	for i in 0 ..= MAXBITS {
		nums[i] = 0
	}

	// Count keys in array part
	nasize := numusearray(t, nums[:])
	totaluse := nasize

	// Count keys in hash part
	totaluse += numusehash(t, nums[:], &nasize)

	// Count extra key
	k := arrayindex(ek)
	if k > 0 && k <= MAXASIZE {
		nums[ceillog2(u32(k))] += 1
		nasize += 1
	}
	totaluse += 1

	// Compute new size for array part
	na := computesizes(nums[:], &nasize)

	// Resize the table to new computed sizes
	resize(L, t, nasize, totaluse - na)
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
				slot := luaH_setnum(L, t, c.int(i + 1))
				setobj(slot, &t.array[i])
			}
		}
		// Shrink
		t.array = cast([^]TValue)luaM_realloc_(
			L,
			t.array,
			c.size_t(oldasize) * size_of(TValue),
			c.size_t(nasize) * size_of(TValue),
		)
	}

	// Re-insert elements from old hash part
	old_count := twoto(u8(oldhsize))
	for i := old_count - 1; i >= 0; i -= 1 {
		old := &mem.ptr_offset(nold, int(i))^
		if !ttisnil(gval(old)) {
			slot := luaH_set(L, t, key2tval(old))
			setobj(slot, gval(old))
		}
	}

	// Free old hash part
	if nold != dummynode {
		luaM_realloc_(L, nold, c.size_t(old_count) * size_of(Node), 0)
	}
}

// Find boundary (# operator)
@(export, link_name = "luaH_getn")
luaH_getn :: proc "c" (t: ^Table) -> c.int {
	context = runtime.default_context()
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
		return c.int(i)
	}

	if t.node == dummynode {
		return c.int(j)
	}

	// Search in hash part
	// fmt.printf("DEBUG: luaH_getn t=%p sizearray=%d lsizenode=%d node=%p entering unbound_search\n", t, t.sizearray, t.lsizenode, t.node)
	res := c.int(unbound_search(t, u32(j)))
	return res
}

@(private)
unbound_search :: proc(t: ^Table, j: u32) -> int {
	i := j
	new_j := j + 1

	// Find bounds
	for !ttisnil(luaH_getnum(t, c.int(new_j))) {
		i = new_j
		new_j *= 2
		if new_j > u32(2147483647) / 2 { 	// Use literal for MAX_INT to be safe
			break
		}
	}
	// now i has boundary and new_j is outside
	for new_j - i > 1 {
		m := (i + new_j) / 2
		// fmt.printf("DEBUG: unbound_search binary loop i=%d new_j=%d m=%d\n", i, new_j, m)
		if ttisnil(luaH_getnum(t, c.int(m))) {
			new_j = m
		} else {
			i = m
		}
	}
	return int(i)
}

// Next for table iteration
@(export, link_name = "luaH_next")
luaH_next :: proc "c" (L: ^lua_State, t: ^Table, key: StkId) -> c.int {
	context = runtime.default_context()
	fmt.printf("DEBUG: luaH_next entry t=%p key=%p tt=%d\n", t, key, key.tt)
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
			fmt.printf(
				"DEBUG: luaH_next found hash entry at %d, key type %d, key addr %p, top_val addr %p\n",
				i,
				key2tval(n).tt,
				key,
				cast(^TValue)(cast(uintptr)key + size_of(TValue)),
			)
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
