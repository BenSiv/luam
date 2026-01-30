package lib

import "../lua"
import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:mem"

// Implementation of os library functions using libc to match original C behavior

// os.clock
os_clock :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	c := libc.clock()
	t := f64(c) / f64(libc.CLOCKS_PER_SEC)
	lua.lua_pushnumber(L, t)
	return 1
}

os_pushresult :: proc "c" (L: ^lua.State, i: c.int, filename: cstring) -> c.int {
	context = runtime.default_context()
	en := int(libc.errno()^)
	if i != 0 {
		lua.lua_pushboolean(L, 1)
		return 1
	} else {
		lua.lua_pushnil(L)
		lua.lua_pushfstring(L, "%s: error %d", filename, en)
		lua.lua_pushinteger(L, en)
		return 3
	}
}

// os.getenv
os_getenv :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	key := lua.luaL_checkstring(L, 1)
	val := libc.getenv(key)
	lua.lua_pushstring(L, val) // if val is nil, this might need check, but lua_pushstring handles nil/NULL?
	// usage in loslib.c: lua_pushstring(L, getenv(...));
	// lua_pushstring(NULL) pushes nil.
	return 1
}

// os.execute
os_execute :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cmd := lua.luaL_optstring(L, 1, nil)
	status := libc.system(cmd)
	lua.lua_pushinteger(L, int(status))
	return 1
}

// os.exit
os_exit :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	status: c.int
	if lua.lua_isboolean(L, 1) {
		status = lua.lua_toboolean(L, 1) != 0 ? libc.EXIT_SUCCESS : libc.EXIT_FAILURE
	} else {
		status = c.int(lua.luaL_optinteger(L, 1, int(libc.EXIT_SUCCESS)))
	}
	if lua.lua_toboolean(L, 2) != 0 {
		lua.lua_close(L)
	}
	libc.exit(status)
}

// os.remove
os_remove :: proc "c" (L: ^lua.State) -> c.int {
	filename := lua.luaL_checkstring(L, 1)
	return os_pushresult(L, libc.remove(filename) == 0 ? 1 : 0, filename)
}

// os.rename
os_rename :: proc "c" (L: ^lua.State) -> c.int {
	fromname := lua.luaL_checkstring(L, 1)
	toname := lua.luaL_checkstring(L, 2)
	return os_pushresult(L, libc.rename(fromname, toname) == 0 ? 1 : 0, fromname)
}

// Helper for date/time table
setfield :: proc "c" (L: ^lua.State, key: cstring, value: int) {
	lua.lua_pushinteger(L, value)
	lua.lua_setfield(L, -2, key)
}

setboolfield :: proc "c" (L: ^lua.State, key: cstring, value: int) {
	if value < 0 {return}
	lua.lua_pushboolean(L, c.int(value != 0 ? 1 : 0))
	lua.lua_setfield(L, -2, key)
}

getfield :: proc "c" (L: ^lua.State, key: cstring, d: int) -> int {
	context = runtime.default_context()
	lua.lua_getfield(L, -1, key)
	res: int
	if lua.lua_isnumber(L, -1) {
		res = int(lua.lua_tointeger(L, -1))
	} else {
		if d < 0 {
			lua.luaL_error(L, "field '%s' missing in date table", key)
		}
		res = d
	}
	lua.lua_pop(L, 1)
	return res
}

getboolfield :: proc "c" (L: ^lua.State, key: cstring) -> int {
	lua.lua_getfield(L, -1, key)
	res := -1
	if !lua.lua_isnil(L, -1) {
		res = lua.lua_toboolean(L, -1) != 0 ? 1 : 0
	}
	lua.lua_pop(L, 1)
	return res
}

os_date :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	s_raw := lua.luaL_optstring(L, 1, "%c")
	s_ptr := ([^]u8)(s_raw)
	t := libc.time_t(lua.luaL_optnumber(L, 2, f64(libc.time(nil))))
	stm: ^libc.tm
	if s_ptr[0] == '!' {
		stm = libc.gmtime(&t)
		s_ptr = mem.ptr_offset(s_ptr, 1)
	} else {
		stm = libc.localtime(&t)
	}

	if stm == nil {
		lua.lua_pushnil(L)
	} else if libc.strcmp((cstring)(s_ptr), "*t") == 0 {
		lua.lua_createtable(L, 0, 9)
		setfield(L, "sec", int(stm.tm_sec))
		setfield(L, "min", int(stm.tm_min))
		setfield(L, "hour", int(stm.tm_hour))
		setfield(L, "day", int(stm.tm_mday))
		setfield(L, "month", int(stm.tm_mon + 1))
		setfield(L, "year", int(stm.tm_year + 1900))
		setfield(L, "wday", int(stm.tm_wday + 1))
		setfield(L, "yday", int(stm.tm_yday + 1))
		setboolfield(L, "isdst", int(stm.tm_isdst))
	} else {
		cc := [3]u8{'%', 0, 0}
		b: lua.Buffer
		lua.luaL_buffinit(L, &b)
		for s_ptr[0] != 0 {
			if s_ptr[0] != '%' || s_ptr[1] == 0 {
				lua.luaL_addchar(&b, s_ptr[0])
				s_ptr = mem.ptr_offset(s_ptr, 1)
			} else {
				buff: [200]u8
				cc[1] = s_ptr[1]
				s_ptr = mem.ptr_offset(s_ptr, 2)
				reslen := libc.strftime(
					([^]c.char)(&buff[0]),
					size_of(buff),
					(cstring)(&cc[0]),
					stm,
				)
				lua.luaL_addlstring(&b, (cstring)(&buff[0]), c.size_t(reslen))
			}
		}
		lua.luaL_pushresult(&b)
	}
	return 1
}

os_time :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	t: libc.time_t
	if lua.lua_isnoneornil(L, 1) {
		t = libc.time(nil)
	} else {
		ts: libc.tm
		lua.luaL_checktype(L, 1, lua.LUA_TTABLE)
		lua.lua_settop(L, 1)
		ts.tm_sec = c.int(getfield(L, "sec", 0))
		ts.tm_min = c.int(getfield(L, "min", 0))
		ts.tm_hour = c.int(getfield(L, "hour", 12))
		ts.tm_mday = c.int(getfield(L, "day", -1))
		ts.tm_mon = c.int(getfield(L, "month", -1) - 1)
		ts.tm_year = c.int(getfield(L, "year", -1) - 1900)
		ts.tm_isdst = c.int(getboolfield(L, "isdst"))
		t = libc.mktime(&ts)
	}
	if t == -1 {
		lua.lua_pushnil(L)
	} else {
		lua.lua_pushnumber(L, f64(t))
	}
	return 1
}

os_difftime :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.lua_pushnumber(
		L,
		f64(
			libc.difftime(
				libc.time_t(lua.luaL_checknumber(L, 1)),
				libc.time_t(lua.luaL_optnumber(L, 2, 0)),
			),
		),
	)
	return 1
}

os_setlocale :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	// Simplified setlocale
	l := lua.luaL_optstring(L, 1, nil)
	// Lua 5.1 supports categories like "all", "collate", etc.
	// We'll just support "all" (LC_ALL) for now to keep it simple
	// libc.LC_ALL is usually 6 on Linux, but varies.
	// Let's assume LC_ALL for now.
	lua.lua_pushstring(L, libc.setlocale(libc.Locale_Category.ALL, l))
	return 1
}

os_tmpname :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	buff: [1024]u8
	res := libc.tmpnam(([^]c.char)(&buff[0]))
	if res == nil {
		return lua.luaL_error(L, "unable to generate a unique filename")
	}
	lua.lua_pushstring(L, (cstring)(res))
	return 1
}

@(export)
open_os :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	oslib := [?]lua.Reg {
		{"exit", os_exit},
		{"getenv", os_getenv},
		{"remove", os_remove},
		{"rename", os_rename},
		{"execute", os_execute},
		{"clock", os_clock},
		{"time", os_time},
		{"date", os_date},
		{"difftime", os_difftime},
		{"setlocale", os_setlocale},
		{"tmpname", os_tmpname},
		{nil, nil},
	}

	lua.luaL_register(L, "os", &oslib[0])
	return 1
}
