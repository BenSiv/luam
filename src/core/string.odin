// String table (keeps all strings handled by Lua)
// Migrated from lstring.c/h
// Note: Some functions need C FFI for memory allocation until lmem is fully integrated
package core

import "core:c"
import "core:mem"

// Size of a string object including its content
sizestring :: #force_inline proc(s: ^TString) -> c.size_t {
	return size_of(TString) + (s.tsv.len + 1) * size_of(u8)
}

// Size of a userdata object including its content
sizeudata :: #force_inline proc(u: ^Udata) -> c.size_t {
	return size_of(Udata) + u.uv.len
}

// Fix a string (mark it as non-collectable)
luaS_fix :: #force_inline proc(s: ^TString) {
	s.tsv.marked |= (1 << FIXEDBIT)
}

// FFI to C memory functions (needed until full integration)
@(private)
foreign import lua_core "system:lua"

@(private)
foreign lua_core {
	luaM_malloc_c :: proc(L: ^lua_State, size: c.size_t) -> rawptr ---
	luaM_toobig_c :: proc(L: ^lua_State) -> rawptr ---
	luaM_realloc__c :: proc(L: ^lua_State, block: rawptr, osize: c.size_t, nsize: c.size_t) -> rawptr ---
}

// Maximum allocation size
MAX_SIZET :: max(c.size_t)
MAX_INT :: max(c.int)

// lmod - hash modulo for power-of-2 sizes
str_lmod :: #force_inline proc(s: u32, size: c.int) -> c.int {
	return c.int(s) & (size - 1)
}

// Change white status of GC object
changewhite :: #force_inline proc(x: ^GCObject) {
	x.gch.marked ~= 3 // toggle between WHITE0 and WHITE1
}

// Resize string table
luaS_resize :: proc(L: ^lua_State, newsize: c.int) {
	g := G(L)

	// Cannot resize during GC traverse
	if g.gcstate == GCSsweepstring {
		return
	}

	tb := &g.strt

	// Allocate new hash table
	newhash := cast([^]^GCObject)luaM_malloc_c(L, c.size_t(newsize) * size_of(^GCObject))

	// Initialize new buckets
	for i in 0 ..< newsize {
		newhash[i] = nil
	}

	// Rehash existing strings
	for i in 0 ..< tb.size {
		p := tb.hash[i]
		for p != nil {
			next := p.gch.next // save next
			h := rawgco2ts(p).tsv.hash
			h1 := str_lmod(h, newsize) // new position
			p.gch.next = newhash[h1] // chain it
			newhash[h1] = p
			p = next
		}
	}

	// Free old hash table
	if tb.hash != nil && tb.size > 0 {
		luaM_realloc__c(L, tb.hash, c.size_t(tb.size) * size_of(^GCObject), 0)
	}

	tb.size = newsize
	tb.hash = newhash
}

// Create new string (internal)
@(private)
newlstr :: proc(L: ^lua_State, str: [^]u8, l: c.size_t, h: u32) -> ^TString {
	g := G(L)

	// Check for overflow
	if l + 1 > (MAX_SIZET - size_of(TString)) / size_of(u8) {
		luaM_toobig_c(L)
	}

	// Allocate string object
	ts := cast(^TString)luaM_malloc_c(L, (l + 1) * size_of(u8) + size_of(TString))

	// Initialize header
	ts.tsv.len = l
	ts.tsv.hash = h
	ts.tsv.marked = luaC_white(g)
	ts.tsv.tt = LUA_TSTRING
	ts.tsv.reserved = 0

	// Copy string content (stored after TString header)
	dest := cast([^]u8)(cast(uintptr)ts + size_of(TString))
	mem.copy(dest, str, int(l))
	dest[l] = 0 // null terminator

	// Add to string table
	tb := &g.strt
	bucket := str_lmod(h, tb.size)
	ts.tsv.next = tb.hash[bucket]
	tb.hash[bucket] = obj2gco(ts)
	tb.nuse += 1

	// Resize if too crowded
	if tb.nuse > u32(tb.size) && tb.size <= MAX_INT / 2 {
		luaS_resize(L, tb.size * 2)
	}

	return ts
}

// Create or find interned string
luaS_newlstr :: proc(L: ^lua_State, str: cstring, l: c.size_t) -> ^TString {
	g := G(L)
	str_data := cast([^]u8)str

	// Compute hash
	h := u32(l) // seed
	step := (l >> 5) + 1 // if string is too long, don't hash all chars
	l1 := l
	for l1 >= step {
		h = h ~ ((h << 5) + (h >> 2) + u32(str_data[l1 - 1]))
		l1 -= step
	}

	// Search for existing string
	bucket := str_lmod(h, g.strt.size)
	o := g.strt.hash[bucket]
	for o != nil {
		ts := rawgco2ts(o)
		if ts.tsv.len == l {
			// Compare string contents
			existing := cast([^]u8)(cast(uintptr)ts + size_of(TString))
			match := true
			for i in 0 ..< int(l) {
				if existing[i] != str_data[i] {
					match = false
					break
				}
			}
			if match {
				// String may be dead - resurrect it
				if isdead(g, o) {
					changewhite(o)
				}
				return ts
			}
		}
		o = o.gch.next
	}

	// Not found - create new string
	return newlstr(L, str_data, l, h)
}

// Convenience: create string from null-terminated cstring
luaS_new :: #force_inline proc(L: ^lua_State, s: cstring) -> ^TString {
	l: c.size_t = 0
	ptr := cast([^]u8)s
	for ptr[l] != 0 {
		l += 1
	}
	return luaS_newlstr(L, s, l)
}

// Create new userdata
luaS_newudata :: proc(L: ^lua_State, s: c.size_t, e: ^Table) -> ^Udata {
	g := G(L)

	// Check for overflow
	if s > MAX_SIZET - size_of(Udata) {
		luaM_toobig_c(L)
	}

	// Allocate userdata
	u := cast(^Udata)luaM_malloc_c(L, s + size_of(Udata))

	// Initialize header
	u.uv.marked = luaC_white(g)
	u.uv.tt = LUA_TUSERDATA
	u.uv.len = s
	u.uv.metatable = nil
	u.uv.env = e

	// Chain on udata list (after main thread)
	u.uv.next = g.mainthread.next
	g.mainthread.next = obj2gco(u)

	return u
}
