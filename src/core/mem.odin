// Interface to Memory Manager
// Migrated from lmem.c/h
// Note: Some functions still delegate to C until ldebug/ldo are migrated
package core

import "core:c"

// Memory error message
// MEMERRMSG defined in mem.odin

// Minimum array size for growing vectors
MINSIZEARRAY :: 4

// Maximum safe size for allocations
MAX_SIZET :: max(c.size_t)

// Allocator function type (same as in Lua)
Alloc :: #type proc "c" (ud: rawptr, ptr: rawptr, osize: c.size_t, nsize: c.size_t) -> rawptr

// Forward declarations for types from other modules (will be replaced when migrated)
// For now, use opaque pointers
State :: struct {} // Placeholder for lua_State
// Global_State defined in state.odin

// Helper to get global state from lua_State
// This is a macro in C: #define G(L) (L->l_G)
// Will be updated when lstate is migrated

// LUA_ERRMEM from lua.h
// LUA_ERRMEM defined in state.odin or similar? No, standard Lua defines LUA_ERRMEM in lua.h
// Check if defined in state.odin
// Removing duplicate here if it causes conflicts

// These functions will call into C until ldebug/ldo are migrated
foreign import lua_core "system:lua"

foreign lua_core {
	// Error handling (from ldebug/ldo) - will be replaced when those are migrated
	luaG_runerror :: proc(L: ^State, fmt: cstring, #c_vararg args: ..any) ---
	luaD_throw :: proc(L: ^State, errcode: c.int) ---
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

// Generic allocation routine
realloc_ :: proc(
	L: ^State,
	g: rawptr, // Changed from ^Global_State to rawptr
	block: rawptr,
	osize: c.size_t,
	nsize: c.size_t,
) -> rawptr {
	// Call the allocator
	// This will need to be updated when Global_State is properly defined and accessible
	// For now, assuming g can be cast to a pointer to a struct with frealloc and ud
	// This is a temporary workaround until lstate is migrated
	_g := cast(^struct {
		frealloc:   Alloc,
		ud:         rawptr,
		totalbytes: c.size_t,
	})g
	result := _g.frealloc(_g.ud, block, osize, nsize)

	// Check for allocation failure
	if result == nil && nsize > 0 {
		luaD_throw(L, LUA_ERRMEM)
	}

	// Update total bytes
	// This will also need to be updated
	_g.totalbytes = (_g.totalbytes - osize) + nsize

	return result
}

// Allocation error - block too big
toobig :: proc(L: ^State) -> rawptr {
	luaG_runerror(L, "memory allocation error: block too big")
	return nil
}

// Reallocate vector with overflow check
reallocv :: proc(
	L: ^State,
	g: rawptr, // Changed from ^Global_State to rawptr
	block: rawptr,
	old_n: int,
	new_n: int,
	elem_size: c.size_t,
) -> rawptr {
	// Check for overflow: (n+1) * elem_size must not overflow size_t
	if c.size_t(new_n + 1) <= MAX_SIZET / elem_size {
		return realloc_(L, g, block, c.size_t(old_n) * elem_size, c.size_t(new_n) * elem_size)
	}
	return toobig(L)
}

// Grow array with doubling strategy
growaux :: proc(
	L: ^State,
	g: rawptr, // Changed from ^Global_State to rawptr
	block: rawptr,
	size: ^int,
	elem_size: c.size_t,
	limit: int,
	errormsg: cstring,
) -> rawptr {
	newsize: int

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

	newblock := reallocv(L, g, block, size^, newsize, elem_size)
	size^ = newsize // Update only when everything else is OK
	return newblock
}

// Convenience wrappers

// Free memory block
freemem :: #force_inline proc(L: ^State, g: rawptr, block: rawptr, size: c.size_t) { 	// Changed from ^Global_State to rawptr
	realloc_(L, g, block, size, 0)
}

// Allocate new memory block
malloc :: #force_inline proc(L: ^State, g: rawptr, size: c.size_t) -> rawptr { 	// Changed from ^Global_State to rawptr
	return realloc_(L, g, nil, 0, size)
}
