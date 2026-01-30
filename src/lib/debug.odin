package lib

import "../lua"
import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:mem"

// KEY_HOOK is used as a lightuserdata key in the registry
KEY_HOOK: byte = 'h'

@(private)
getthread :: proc "c" (L: ^lua.State, arg: ^c.int) -> ^lua.State {
	if lua.lua_isthread(L, 1) {
		arg^ = 1
		return lua.lua_tothread(L, 1)
	} else {
		arg^ = 0
		return L
	}
}

@(private)
treatstackoption :: proc "c" (L: ^lua.State, L1: ^lua.State, fname: cstring) {
	if L == L1 {
		lua.lua_pushvalue(L, -2)
		lua.lua_remove(L, -3)
	} else {
		lua.lua_xmove(L1, L, 1)
	}
	lua.lua_setfield(L, -2, fname)
}

db_getregistry :: proc "c" (L: ^lua.State) -> c.int {
	lua.lua_pushvalue(L, lua.LUA_REGISTRYINDEX)
	return 1
}

db_getmetatable :: proc "c" (L: ^lua.State) -> c.int {
	lua.luaL_checkany(L, 1)
	if lua.lua_getmetatable(L, 1) == 0 {
		lua.lua_pushnil(L)
	}
	return 1
}

db_setmetatable :: proc "c" (L: ^lua.State) -> c.int {
	t := lua.lua_type(L, 2)
	lua.luaL_argcheck(
		L,
		c.int(t == lua.LUA_TNIL || t == lua.LUA_TTABLE),
		2,
		"nil or table expected",
	)
	lua.lua_settop(L, 2)
	lua.lua_pushboolean(L, lua.lua_setmetatable(L, 1))
	return 1
}

db_getfenv :: proc "c" (L: ^lua.State) -> c.int {
	lua.luaL_checkany(L, 1)
	lua.lua_getfenv(L, 1)
	return 1
}

db_setfenv :: proc "c" (L: ^lua.State) -> c.int {
	lua.luaL_checktype(L, 2, lua.LUA_TTABLE)
	lua.lua_settop(L, 2)
	if lua.lua_setfenv(L, 1) == 0 {
		lua.luaL_error(L, "setfenv cannot change environment of given object")
	}
	return 1
}

db_getinfo :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	ar: lua.Debug
	arg: c.int
	L1 := getthread(L, &arg)
	options := lua.luaL_optstring(L, arg + 2, "flnSu")
	if lua.lua_isnumber(L, arg + 1) {
		if lua.lua_getstack(L1, c.int(lua.lua_tointeger(L, arg + 1)), &ar) == 0 {
			lua.lua_pushnil(L)
			return 1
		}
	} else if lua.lua_isfunction(L, arg + 1) {
		lua.lua_pushfstring(L, ">%s", options)
		options = lua.lua_tostring(L, -1)
		lua.lua_pushvalue(L, arg + 1)
		lua.lua_xmove(L, L1, 1)
	} else {
		return lua.luaL_argerror(L, arg + 1, "function or level expected")
	}

	if lua.lua_getinfo(L1, options, &ar) == 0 {
		return lua.luaL_argerror(L, arg + 2, "invalid option")
	}

	lua.lua_createtable(L, 0, 2)
	if libc.strchr(options, 'S') != nil {
		lua.lua_pushstring(L, ar.source)
		lua.lua_setfield(L, -2, "source")
		lua.lua_pushstring(L, cstring(&ar.short_src[0]))
		lua.lua_setfield(L, -2, "short_src")
		lua.lua_pushinteger(L, int(ar.linedefined))
		lua.lua_setfield(L, -2, "linedefined")
		lua.lua_pushinteger(L, int(ar.lastlinedefined))
		lua.lua_setfield(L, -2, "lastlinedefined")
		lua.lua_pushstring(L, ar.what)
		lua.lua_setfield(L, -2, "what")
	}
	if libc.strchr(options, 'l') != nil {
		lua.lua_pushinteger(L, int(ar.currentline))
		lua.lua_setfield(L, -2, "currentline")
	}
	if libc.strchr(options, 'u') != nil {
		lua.lua_pushinteger(L, int(ar.nups))
		lua.lua_setfield(L, -2, "nups")
	}
	if libc.strchr(options, 'n') != nil {
		lua.lua_pushstring(L, ar.name)
		lua.lua_setfield(L, -2, "name")
		lua.lua_pushstring(L, ar.namewhat)
		lua.lua_setfield(L, -2, "namewhat")
	}
	if libc.strchr(options, 'L') != nil {
		treatstackoption(L, L1, "activelines")
	}
	if libc.strchr(options, 'f') != nil {
		treatstackoption(L, L1, "func")
	}
	return 1
}

db_getlocal :: proc "c" (L: ^lua.State) -> c.int {
	arg: c.int
	L1 := getthread(L, &arg)
	ar: lua.Debug
	if lua.lua_getstack(L1, lua.luaL_checkint(L, arg + 1), &ar) == 0 {
		return lua.luaL_argerror(L, arg + 1, "level out of range")
	}
	name := lua.lua_getlocal(L1, &ar, lua.luaL_checkint(L, arg + 2))
	if name != nil {
		lua.lua_xmove(L1, L, 1)
		lua.lua_pushstring(L, name)
		lua.lua_pushvalue(L, -2)
		return 2
	} else {
		lua.lua_pushnil(L)
		return 1
	}
}

db_setlocal :: proc "c" (L: ^lua.State) -> c.int {
	arg: c.int
	L1 := getthread(L, &arg)
	ar: lua.Debug
	if lua.lua_getstack(L1, lua.luaL_checkint(L, arg + 1), &ar) == 0 {
		return lua.luaL_argerror(L, arg + 1, "level out of range")
	}
	lua.luaL_checkany(L, arg + 3)
	lua.lua_settop(L, arg + 3)
	lua.lua_xmove(L, L1, 1)
	lua.lua_pushstring(L, lua.lua_setlocal(L1, &ar, lua.luaL_checkint(L, arg + 2)))
	return 1
}

@(private)
auxupvalue :: proc "c" (L: ^lua.State, get: c.int) -> c.int {
	n := lua.luaL_checkint(L, 2)
	lua.luaL_checktype(L, 1, lua.LUA_TFUNCTION)
	if lua.lua_iscfunction(L, 1) {
		return 0
	}
	name := lua.lua_getupvalue(L, 1, n) if get != 0 else lua.lua_setupvalue(L, 1, n)
	if name == nil do return 0
	lua.lua_pushstring(L, name)
	lua.lua_insert(L, -(get + 1))
	return get + 1
}

db_getupvalue :: proc "c" (L: ^lua.State) -> c.int {
	return auxupvalue(L, 1)
}

db_setupvalue :: proc "c" (L: ^lua.State) -> c.int {
	lua.luaL_checkany(L, 3)
	return auxupvalue(L, 0)
}

@(private)
hookf :: proc "c" (L: ^lua.State, ar: ^lua.Debug) {
	context = runtime.default_context()
	hooknames := [?]cstring{"call", "return", "line", "count", "tail return"}
	lua.lua_pushlightuserdata(L, &KEY_HOOK)
	lua.lua_rawget(L, lua.LUA_REGISTRYINDEX)
	lua.lua_pushlightuserdata(L, L)
	lua.lua_rawget(L, -2)
	if lua.lua_isfunction(L, -1) {
		lua.lua_pushstring(L, hooknames[int(ar.event)])
		if ar.currentline >= 0 {
			lua.lua_pushinteger(L, int(ar.currentline))
		} else {
			lua.lua_pushnil(L)
		}
		lua.lua_getinfo(L, "lS", ar)
		lua.lua_call(L, 2, 0)
	}
}

@(private)
makemask :: proc "c" (smask: cstring, count: c.int) -> c.int {
	mask: c.int = 0
	if libc.strchr(smask, 'c') != nil do mask |= lua.LUA_MASKCALL
	if libc.strchr(smask, 'r') != nil do mask |= lua.LUA_MASKRET
	if libc.strchr(smask, 'l') != nil do mask |= lua.LUA_MASKLINE
	if count > 0 do mask |= lua.LUA_MASKCOUNT
	return mask
}

@(private)
unmakemask :: proc "c" (mask: c.int, smask: [^]u8) -> cstring {
	i: int = 0
	if (mask & lua.LUA_MASKCALL) != 0 {
		smask[i] = 'c'
		i += 1
	}
	if (mask & lua.LUA_MASKRET) != 0 {
		smask[i] = 'r'
		i += 1
	}
	if (mask & lua.LUA_MASKLINE) != 0 {
		smask[i] = 'l'
		i += 1
	}
	smask[i] = 0
	return cstring(smask)
}

@(private)
gethooktable :: proc "c" (L: ^lua.State) {
	lua.lua_pushlightuserdata(L, &KEY_HOOK)
	lua.lua_rawget(L, lua.LUA_REGISTRYINDEX)
	if !lua.lua_istable(L, -1) {
		lua.lua_pop(L, 1)
		lua.lua_createtable(L, 0, 1)
		lua.lua_pushlightuserdata(L, &KEY_HOOK)
		lua.lua_pushvalue(L, -2)
		lua.lua_rawset(L, lua.LUA_REGISTRYINDEX)
	}
}

db_sethook :: proc "c" (L: ^lua.State) -> c.int {
	arg: c.int
	L1 := getthread(L, &arg)
	func: lua.Hook
	mask, count: c.int
	if lua.lua_isnoneornil(L, arg + 1) {
		lua.lua_settop(L, arg + 1)
		func = nil
		mask = 0
		count = 0
	} else {
		smask := lua.luaL_checkstring(L, arg + 2)
		lua.luaL_checktype(L, arg + 1, lua.LUA_TFUNCTION)
		count = lua.luaL_optint(L, arg + 3, 0)
		func = hookf
		mask = makemask(smask, count)
	}
	gethooktable(L)
	lua.lua_pushlightuserdata(L, L1)
	lua.lua_pushvalue(L, arg + 1)
	lua.lua_rawset(L, -3)
	lua.lua_pop(L, 1)
	lua.lua_sethook(L1, func, mask, count)
	return 0
}

db_gethook :: proc "c" (L: ^lua.State) -> c.int {
	arg: c.int
	L1 := getthread(L, &arg)
	buff: [5]u8
	mask := lua.lua_gethookmask(L1)
	hook := lua.lua_gethook(L1)
	if hook != nil && hook != hookf {
		lua.lua_pushliteral(L, "external hook")
	} else {
		gethooktable(L)
		lua.lua_pushlightuserdata(L, L1)
		lua.lua_rawget(L, -2)
		lua.lua_remove(L, -2)
	}
	lua.lua_pushstring(L, unmakemask(mask, &buff[0]))
	lua.lua_pushinteger(L, int(lua.lua_gethookcount(L1)))
	return 3
}

db_debug :: proc "c" (L: ^lua.State) -> c.int {
	for {
		buffer: [250]u8
		lua.fprintf(lua.luaL_get_stderr(), "lua_debug> ")
		if libc.fgets(&buffer[0], size_of(buffer), libc.stdin) == nil ||
		   libc.strcmp(cstring(&buffer[0]), "cont\n") == 0 {
			return 0
		}
		if lua.luaL_loadbuffer(
			   L,
			   cstring(&buffer[0]),
			   libc.strlen(cstring(&buffer[0])),
			   "=(debug command)",
		   ) !=
			   0 ||
		   lua.lua_pcall(L, 0, 0, 0) != 0 {
			lua.fprintf(lua.luaL_get_stderr(), "%s", lua.lua_tostring(L, -1))
			lua.fprintf(lua.luaL_get_stderr(), "\n")
		}
		lua.lua_settop(L, 0)
	}
}

LEVELS1 :: 12
LEVELS2 :: 10

db_errorfb :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	level: c.int
	firstpart: bool = true
	arg: c.int
	L1 := getthread(L, &arg)
	ar: lua.Debug
	if lua.lua_isnumber(L, arg + 2) {
		level = c.int(lua.lua_tointeger(L, arg + 2))
		lua.lua_pop(L, 1)
	} else {
		level = 1 if L == L1 else 0
	}
	if lua.lua_gettop(L) == arg {
		lua.lua_pushliteral(L, "")
	} else if !lua.lua_isstring(L, arg + 1) {
		return 1
	} else {
		lua.lua_pushliteral(L, "\n")
	}
	lua.lua_pushliteral(L, "stack traceback:")
	for lua.lua_getstack(L1, level, &ar) != 0 {
		level += 1
		if level > LEVELS1 && firstpart {
			if lua.lua_getstack(L1, level + LEVELS2, &ar) == 0 {
				level -= 1
			} else {
				lua.lua_pushliteral(L, "\n\t...")
				for lua.lua_getstack(L1, level + LEVELS2, &ar) != 0 {
					level += 1
				}
			}
			firstpart = false
			continue
		}
		lua.lua_pushliteral(L, "\n\t")
		lua.lua_getinfo(L1, "Snl", &ar)
		lua.lua_pushfstring(L, "%s:", cstring(&ar.short_src[0]))
		if ar.currentline > 0 {
			lua.lua_pushfstring(L, "%d:", ar.currentline)
		}
		if (cast([^]u8)ar.namewhat)[0] != 0 {
			lua.lua_pushfstring(L, " in function '%s'", ar.name)
		} else {
			if (cast([^]u8)ar.what)[0] == 'm' {
				lua.lua_pushliteral(L, " in main chunk")
			} else if (cast([^]u8)ar.what)[0] == 'C' || (cast([^]u8)ar.what)[0] == 't' {
				lua.lua_pushliteral(L, " ?")
			} else {
				lua.lua_pushfstring(
					L,
					" in function <%s:%d>",
					cstring(&ar.short_src[0]),
					int(ar.linedefined),
				)
			}
		}
		lua.lua_concat(L, lua.lua_gettop(L) - arg)
	}
	lua.lua_concat(L, lua.lua_gettop(L) - arg)
	return 1
}

open_debug :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	dblib := [?]lua.Reg {
		{"debug", db_debug},
		{"getfenv", db_getfenv},
		{"gethook", db_gethook},
		{"getinfo", db_getinfo},
		{"getlocal", db_getlocal},
		{"getregistry", db_getregistry},
		{"getmetatable", db_getmetatable},
		{"getupvalue", db_getupvalue},
		{"setfenv", db_setfenv},
		{"sethook", db_sethook},
		{"setlocal", db_setlocal},
		{"setmetatable", db_setmetatable},
		{"setupvalue", db_setupvalue},
		{"traceback", db_errorfb},
		{nil, nil},
	}
	lua.luaL_register(L, "debug", &dblib[0])
	return 1
}
