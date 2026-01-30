package lua

import "core:c"

// Basic types
State :: distinct rawptr
CFunction :: #type proc "c" (L: ^State) -> c.int

// Constants
LUA_MULTRET :: -1

// Dynamic library bindings
foreign import liblua "system:c"

@(default_calling_convention = "c")
foreign liblua {
	lua_pushcclosure :: proc(L: ^State, fn: CFunction, n: c.int) ---
	lua_pushstring :: proc(L: ^State, s: cstring) ---
	lua_call :: proc(L: ^State, nargs: c.int, nresults: c.int) ---

	// Standard Library Open Functions
	luaopen_base :: proc(L: ^State) -> c.int ---
	luaopen_package :: proc(L: ^State) -> c.int ---
	luaopen_table :: proc(L: ^State) -> c.int ---
	luaopen_io :: proc(L: ^State) -> c.int ---
	luaopen_os :: proc(L: ^State) -> c.int ---
	luaopen_string :: proc(L: ^State) -> c.int ---
	luaopen_math :: proc(L: ^State) -> c.int ---
	luaopen_debug :: proc(L: ^State) -> c.int ---

	// Custom Libraries (bit, struct)
	luaopen_bit :: proc(L: ^State) -> c.int ---
	luaopen_struct :: proc(L: ^State) -> c.int ---

	// Stack manipulation
	lua_gettop :: proc(L: ^State) -> c.int ---
	lua_setfield :: proc(L: ^State, idx: c.int, k: cstring) ---
	lua_getfield :: proc(L: ^State, idx: c.int, k: cstring) ---
	lua_type :: proc(L: ^State, idx: c.int) -> c.int ---

	// Push functions
	lua_pushnumber :: proc(L: ^State, n: Number) ---
	lua_pushinteger :: proc(L: ^State, n: Integer) ---
	lua_pushnil :: proc(L: ^State) ---
	lua_pushboolean :: proc(L: ^State, b: c.int) ---

	// Lauxlib
	luaL_register :: proc(L: ^State, libname: cstring, l: ^Reg) ---
	luaL_checknumber :: proc(L: ^State, numArg: c.int) -> Number ---
	luaL_checkinteger :: proc(L: ^State, numArg: c.int) -> Integer ---
	// luaL_optstring and luaL_checkstring are macros in C that call these:
	luaL_optlstring :: proc(L: ^State, narg: c.int, d: cstring, l: ^c.size_t) -> cstring ---
	luaL_checklstring :: proc(L: ^State, narg: c.int, l: ^c.size_t) -> cstring ---

	luaL_checktype :: proc(L: ^State, narg: c.int, t: c.int) ---
	luaL_argerror :: proc(L: ^State, narg: c.int, extramsg: cstring) -> c.int ---
	luaL_error :: proc(L: ^State, fmt: cstring) -> c.int ---
}

// Helper wrappers for C macros
luaL_checkstring :: proc "c" (L: ^State, narg: c.int) -> cstring {
	return luaL_checklstring(L, narg, nil)
}

luaL_optstring :: proc "c" (L: ^State, narg: c.int, d: cstring) -> cstring {
	return luaL_optlstring(L, narg, d, nil)
}

// Lua Types
Number :: f64
Integer :: int // usually ptrdiff_t

// Library registration struct
Reg :: struct {
	name: cstring,
	func: CFunction,
}

// Helper wrappers
pushcfunction :: proc "c" (L: ^State, fn: CFunction) {
	lua_pushcclosure(L, fn, 0)
}
