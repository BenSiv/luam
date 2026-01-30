package main

import "core:c"
import "core:c/libc"
import "lua"

// Implementation of os library functions using libc to match original C behavior

// os.clock
os_clock :: proc "c" (L: ^lua.State) -> c.int {
	// clock() returns clock_t which is usually long (i64 or i32)
	// CLOCKS_PER_SEC is usually 1000000
	c := libc.clock()
	// Manual float conversion
	t := f64(c) / f64(libc.CLOCKS_PER_SEC)
	lua.lua_pushnumber(L, t)
	return 1
}

// os.getenv
os_getenv :: proc "c" (L: ^lua.State) -> c.int {
	key := lua.luaL_checkstring(L, 1)
	val := libc.getenv(key)
	lua.lua_pushstring(L, val) // if val is nil, this might need check, but lua_pushstring handles nil/NULL?
	// usage in loslib.c: lua_pushstring(L, getenv(...));
	// lua_pushstring(NULL) pushes nil.
	return 1
}

// os.execute
os_execute :: proc "c" (L: ^lua.State) -> c.int {
	cmd := lua.luaL_optstring(L, 1, nil)
	status := libc.system(cmd)
	lua.lua_pushinteger(L, int(status))
	return 1
}

// os.exit
os_exit :: proc "c" (L: ^lua.State) -> c.int {
	// simplified implementation for now, ignoring arguments
	libc.exit(libc.EXIT_SUCCESS)
}

// os.remove
os_remove :: proc "c" (L: ^lua.State) -> c.int {
	filename := lua.luaL_checkstring(L, 1)
	status := libc.remove(filename)
	if status == 0 {
		lua.lua_pushboolean(L, 1)
		return 1
	} else {
		lua.lua_pushnil(L)
		lua.lua_pushstring(L, cstring("remove failed")) // Simplified error message
		lua.lua_pushinteger(L, int(status)) // treating errno as status for now
		return 3
	}
}

// os.rename
os_rename :: proc "c" (L: ^lua.State) -> c.int {
	fromname := lua.luaL_checkstring(L, 1)
	toname := lua.luaL_checkstring(L, 2)
	status := libc.rename(fromname, toname)
	if status == 0 {
		lua.lua_pushboolean(L, 1)
		return 1
	} else {
		lua.lua_pushnil(L)
		lua.lua_pushstring(L, cstring("rename failed")) // Simplified error message
		lua.lua_pushinteger(L, int(status))
		return 3
	}
}

// TODO: Implement rest (date, time, etc.) which are more complex

@(export)
luaopen_os_odin :: proc "c" (L: ^lua.State) -> c.int {
	syslib := [?]lua.Reg {
		{"clock", os_clock},
		{"execute", os_execute},
		{"exit", os_exit},
		{"getenv", os_getenv},
		{"remove", os_remove},
		{"rename", os_rename},
		// TODO: Add others
		{nil, nil},
	}

	lua.luaL_register(L, "os", &syslib[0])
	return 1
}
