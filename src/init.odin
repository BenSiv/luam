package main

import "base:runtime"
import "core:c"
import "core:fmt"
import "lib"
import "lua"

// Implementation of luaL_openlibs using the bindings
@(export)
luaL_openlibs :: proc "c" (L: ^lua.State) {
	context = runtime.default_context()
	// Using a dynamic array for the loop or manual unrolling
	// Since we can't easily create a static array of C structs compatible with C iteration in the same way,
	// we'll just manually call the open functions or use an array of our Odin struct.

	libs := [?]lua.Reg {
		{"", lib.open_base},
		{"package", lib.open_package},
		{"table", lib.open_table},
		{"io", lib.open_io},
		{"os", lib.open_os},
		{"string", lib.open_string},
		{"math", lib.open_math},
		{"debug", lib.open_debug},
		{"bit", lib.open_bit},
		{"struct", lua.luaopen_struct},
	}

	for lib_item in libs {
		lua.pushcfunction(L, lib_item.func)
		lua.lua_pushstring(L, lib_item.name) // name is already cstring
		lua.lua_call(L, 1, 0)
	}
}
