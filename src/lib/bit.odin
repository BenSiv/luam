package lib

import "../lua"
import "base:runtime"
import "core:c"

@(private)
b_uint :: i64

@(private)
andaux :: proc "c" (L: ^lua.State) -> b_uint {
	i, n: c.int
	n = lua.lua_gettop(L)
	r: b_uint = ~b_uint(0)
	for i = 1; i <= n; i += 1 {
		r &= b_uint(lua.luaL_checkinteger(L, i))
	}
	return r
}

db_band :: proc "c" (L: ^lua.State) -> c.int {
	r := andaux(L)
	lua.lua_pushnumber(L, lua.Number(r))
	return 1
}

db_bor :: proc "c" (L: ^lua.State) -> c.int {
	i, n: c.int
	n = lua.lua_gettop(L)
	r: b_uint = 0
	for i = 1; i <= n; i += 1 {
		r |= b_uint(lua.luaL_checkinteger(L, i))
	}
	lua.lua_pushnumber(L, lua.Number(r))
	return 1
}

db_bxor :: proc "c" (L: ^lua.State) -> c.int {
	i, n: c.int
	n = lua.lua_gettop(L)
	r: b_uint = 0
	for i = 1; i <= n; i += 1 {
		r ~= b_uint(lua.luaL_checkinteger(L, i))
	}
	lua.lua_pushnumber(L, lua.Number(r))
	return 1
}

db_bnot :: proc "c" (L: ^lua.State) -> c.int {
	r: b_uint = ~b_uint(lua.luaL_checkinteger(L, 1))
	lua.lua_pushnumber(L, lua.Number(r))
	return 1
}

db_lshift :: proc "c" (L: ^lua.State) -> c.int {
	r: b_uint = b_uint(lua.luaL_checkinteger(L, 1))
	i: c.int = lua.luaL_checkint(L, 2)
	if i < 0 {
		r >>= u64(-i)
	} else {
		r <<= u64(i)
	}
	lua.lua_pushnumber(L, lua.Number(r))
	return 1
}

db_rshift :: proc "c" (L: ^lua.State) -> c.int {
	r: b_uint = b_uint(lua.luaL_checkinteger(L, 1))
	i: c.int = lua.luaL_checkint(L, 2)
	if i < 0 {
		r <<= u64(-i)
	} else {
		r >>= u64(i)
	}
	lua.lua_pushnumber(L, lua.Number(r))
	return 1
}

open_bit :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	bitlib := [?]lua.Reg {
		{"band", db_band},
		{"bor", db_bor},
		{"bxor", db_bxor},
		{"bnot", db_bnot},
		{"lshift", db_lshift},
		{"rshift", db_rshift},
		{nil, nil},
	}
	lua.luaL_register(L, "bit", &bitlib[0])
	return 1
}
