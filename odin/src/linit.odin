package main

import "core:c"
import "lua"

// Implementation of luaL_openlibs using the bindings
@(export)
luaL_openlibs :: proc "c" (L: ^lua.State) {

	// Using a dynamic array for the loop or manual unrolling
	// Since we can't easily create a static array of C structs compatible with C iteration in the same way,
	// we'll just manually call the open functions or use an array of our Odin struct.

	libs := [?]lua.Reg {
		{"", lua.luaopen_base},
		{"package", lua.luaopen_package},
		{"table", lua.luaopen_table},
		{"io", lua.luaopen_io},
		{"os", luaopen_os_odin},
		{"string", lua.luaopen_string},
		{"math", luaopen_math_odin},
		{"debug", lua.luaopen_debug},
		{"bit", lua.luaopen_bit},
		{"struct", lua.luaopen_struct},
	}

	for lib in libs {
		lua.pushcfunction(L, lib.func)
		lua.lua_pushstring(L, lib.name) // name is already cstring
		lua.lua_call(L, 1, 0)
	}
}
