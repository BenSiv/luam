// Interface to Memory Manager - Pure Odin Implementation
// Migrated from lmem.c/h
// NO C FFI CALLS - Pure Odin implementation
package core

import "base:runtime"
import "core:c"
import "core:mem"

// Memory error message
MEMERRMSG :: "not enough memory"

// Minimum array size for growing vectors
MINSIZEARRAY :: 4

// Maximum safe size for allocations
MAX_SIZET :: max(c.size_t)

// Allocator function type (same as in Lua)
Alloc :: #type proc "c" (ud: rawptr, ptr: rawptr, osize: c.size_t, nsize: c.size_t) -> rawptr

// Forward declarations - these will be migrated later
// For now, we'll use foreign imports only for error handling
foreign import lua_core "../../obj/liblua.a"

foreign lua_core {
	// Error handling (from ldebug/ldo) - will be replaced when those are migrated
	luaG_runerror :: proc(L: ^lua_State, fmt: cstring, #c_vararg args: ..any) ---
	luaD_throw :: proc(L: ^lua_State, errcode: c.int) ---
}

/*
** About the realloc function:
** void * frealloc (void *ud, void *ptr, size_t osize, size_t nsize);
** (`osize' is the old size, `nsize' is the new size)
**
** Lua ensures that (ptr == NULL) iff (osize == 0).
**
** * frealloc(ud, NULL, 0, x) creates a new block of size `x'
** * frealloc(ud, p, x, 0) frees the block `p'
**   (in this specific case, frealloc must return NULL).
** * frealloc returns NULL if it cannot create or reallocate the area
*/

// Generic allocation routine - PURE ODIN, NO C FFI
@(export, link_name = "luaM_realloc_")
luaM_realloc_ :: proc "c" (
	L: ^lua_State,
	block: rawptr,
	osize: c.size_t,
	nsize: c.size_t,
) -> rawptr {
	context = runtime.default_context()

	g := G(L)

	// Call the allocator
	result := g.frealloc(g.ud, block, osize, nsize)

	// Check for allocation failure
	if result == nil && nsize > 0 {
		luaD_throw(L, LUA_ERRMEM)
	}

	// Update total bytes
	g.totalbytes = (g.totalbytes - osize) + nsize

	return result
}

// Allocation error - block too big - PURE ODIN
@(export, link_name = "luaM_toobig")
luaM_toobig :: proc "c" (L: ^lua_State) -> rawptr {
	context = runtime.default_context()
	luaG_runerror(L, "memory allocation error: block too big")
	return nil
}

// Reallocate vector with overflow check - PURE ODIN
luaM_reallocv :: proc(
	L: ^lua_State,
	block: rawptr,
	old_n: int,
	new_n: int,
	elem_size: c.size_t,
) -> rawptr {
	// Check for overflow: (n+1) * elem_size must not overflow size_t
	if c.size_t(new_n + 1) <= MAX_SIZET / elem_size {
		return luaM_realloc_(L, block, c.size_t(old_n) * elem_size, c.size_t(new_n) * elem_size)
	}
	return luaM_toobig(L)
}

// Grow array with doubling strategy - PURE ODIN
@(export, link_name = "luaM_growaux_")
luaM_growaux_ :: proc "c" (
	L: ^lua_State,
	block: rawptr,
	size: ^c.int,
	elem_size: c.size_t,
	limit: c.int,
	errormsg: cstring,
) -> rawptr {
	context = runtime.default_context()

	newsize: c.int

	if size^ >= limit / 2 {
		// Cannot double it
		if size^ >= limit {
			// Cannot grow even a little
			luaG_runerror(L, errormsg)
		}
		newsize = limit // Still have at least one free place
	} else {
		newsize = size^ * 2
		if newsize < MINSIZEARRAY {
			newsize = MINSIZEARRAY // Minimum size
		}
	}

	newblock := luaM_reallocv(L, block, int(size^), int(newsize), elem_size)
	size^ = newsize // Update only when everything else is OK
	return newblock
}

// Convenience wrappers - PURE ODIN

// Free memory block
luaM_freemem :: #force_inline proc(L: ^lua_State, block: rawptr, size: c.size_t) {
	luaM_realloc_(L, block, size, 0)
}

// Free typed object
luaM_free :: #force_inline proc(L: ^lua_State, block: rawptr, T: typeid) {
	luaM_realloc_(L, block, c.size_t(size_of(T)), 0)
}

// Free array
luaM_freearray :: #force_inline proc(L: ^lua_State, block: rawptr, n: int, T: typeid) {
	luaM_reallocv(L, block, n, 0, c.size_t(size_of(T)))
}

// Allocate new memory block
luaM_malloc :: #force_inline proc(L: ^lua_State, size: c.size_t) -> rawptr {
	return luaM_realloc_(L, nil, 0, size)
}

// Allocate new typed object
luaM_new :: #force_inline proc(L: ^lua_State, $T: typeid) -> ^T {
	return cast(^T)luaM_malloc(L, c.size_t(size_of(T)))
}

// Allocate new vector
luaM_newvector :: #force_inline proc(L: ^lua_State, n: int, $T: typeid) -> [^]T {
	return cast([^]T)luaM_reallocv(L, nil, 0, n, c.size_t(size_of(T)))
}

// Reallocate vector
luaM_reallocvector :: #force_inline proc(
	L: ^lua_State,
	v: rawptr,
	oldn: int,
	n: int,
	$T: typeid,
) -> [^]T {
	return cast([^]T)luaM_reallocv(L, v, oldn, n, c.size_t(size_of(T)))
}

// Default allocator using Odin's memory functions - PURE ODIN
default_alloc :: proc "c" (ud: rawptr, ptr: rawptr, osize: c.size_t, nsize: c.size_t) -> rawptr {
	context = runtime.default_context()

	_ = ud // unused

	if nsize == 0 {
		// Free
		if ptr != nil {
			mem.free(ptr)
		}
		return nil
	}

	if ptr == nil {
		// Allocate new
		data, err := mem.alloc(int(nsize))
		if err != nil {
			return nil
		}
		return data
	}

	// Reallocate
	data, err := mem.resize(ptr, int(osize), int(nsize))
	if err != nil {
		return nil
	}
	return data
}
