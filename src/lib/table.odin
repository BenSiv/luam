package lib

import "../lua"
import "base:runtime"
import "core:c"

// Implementation of table library functions

aux_getn :: #force_inline proc "c" (L: ^lua.State, n: c.int) -> int {
	lua.luaL_checktype(L, n, lua.LUA_TTABLE)
	return lua.luaL_getn(L, n)
}

table_getn :: proc "c" (L: ^lua.State) -> c.int {
	lua.lua_pushinteger(L, lua.Integer(aux_getn(L, 1)))
	return 1
}

table_setn :: proc "c" (L: ^lua.State) -> c.int {
	lua.luaL_checktype(L, 1, lua.LUA_TTABLE)
	lua.luaL_setn(L, 1, int(lua.luaL_checkinteger(L, 2)))
	lua.lua_pushvalue(L, 1)
	return 1
}

table_maxn :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	max: f64 = 0
	lua.luaL_checktype(L, 1, lua.LUA_TTABLE)
	lua.lua_pushnil(L)
	for lua.lua_next(L, 1) != 0 {
		lua.lua_pop(L, 1) // remove value
		if lua.lua_type(L, -1) == lua.LUA_TNUMBER {
			v := f64(lua.luaL_checknumber(L, -1))
			if v > max {
				max = v
			}
		}
	}
	lua.lua_pushnumber(L, max)
	return 1
}

table_insert :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	e := aux_getn(L, 1) + 1
	pos: int
	top := lua.lua_gettop(L)
	if top == 2 {
		pos = e
	} else if top == 3 {
		pos = int(lua.luaL_checkinteger(L, 2))
		if pos > e {
			e = pos
		}
		for i := e; i > pos; i -= 1 {
			lua.lua_rawgeti(L, 1, c.int(i - 1))
			lua.lua_rawseti(L, 1, c.int(i))
		}
	} else {
		return lua.luaL_error(L, "wrong number of arguments to 'insert'")
	}
	lua.luaL_setn(L, 1, e)
	lua.lua_rawseti(L, 1, c.int(pos))
	return 0
}

table_remove :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	e := aux_getn(L, 1)
	pos := int(lua.luaL_optinteger(L, 2, lua.Integer(e)))
	if !(1 <= pos && pos <= e) {
		return 0
	}
	lua.luaL_setn(L, 1, e - 1)
	lua.lua_rawgeti(L, 1, c.int(pos))
	for i := pos; i < e; i += 1 {
		lua.lua_rawgeti(L, 1, c.int(i + 1))
		lua.lua_rawseti(L, 1, c.int(i))
	}
	lua.lua_pushnil(L)
	lua.lua_rawseti(L, 1, c.int(e))
	return 1
}

table_concat :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	b: lua.Buffer
	sep := lua.luaL_optstring(L, 2, "")
	lua.luaL_checktype(L, 1, lua.LUA_TTABLE)
	i := int(lua.luaL_optinteger(L, 3, 1))
	last := int(lua.luaL_optinteger(L, 4, lua.Integer(aux_getn(L, 1))))
	lua.luaL_buffinit(L, &b)
	for ; i < last; i += 1 {
		lua.lua_rawgeti(L, 1, c.int(i))
		if !lua.lua_isstring(L, -1) {
			return lua.luaL_error(L, "invalid value at index %d in table for 'concat'", i)
		}
		lua.luaL_addvalue(&b)
		lua.luaL_addstring(&b, sep)
	}
	if i == last {
		lua.lua_rawgeti(L, 1, c.int(i))
		if !lua.lua_isstring(L, -1) {
			return lua.luaL_error(L, "invalid value at index %d in table for 'concat'", i)
		}
		lua.luaL_addvalue(&b)
	}
	lua.luaL_pushresult(&b)
	return 1
}

table_pack :: proc "c" (L: ^lua.State) -> c.int {
	n := lua.lua_gettop(L)
	lua.lua_createtable(L, n, 1)
	lua.lua_insert(L, 1)
	lua.lua_pushinteger(L, lua.Integer(n))
	lua.lua_setfield(L, 1, "n")
	for i := n; i > 0; i -= 1 {
		lua.lua_rawseti(L, 1, c.int(i))
	}
	return 1
}

table_unpack :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.luaL_checktype(L, 1, lua.LUA_TTABLE)
	i := int(lua.luaL_optinteger(L, 2, 1))
	last := int(lua.luaL_optinteger(L, 3, lua.Integer(aux_getn(L, 1))))
	if i > last {
		return 0
	}
	n := last - i + 1
	if n <= 0 || lua.lua_checkstack(L, c.int(n)) == 0 {
		return lua.luaL_error(L, "too many results to unpack")
	}
	for ; i <= last; i += 1 {
		lua.lua_rawgeti(L, 1, c.int(i))
	}
	return c.int(n)
}

table_foreach :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.luaL_checktype(L, 1, lua.LUA_TTABLE)
	lua.luaL_checktype(L, 2, lua.LUA_TFUNCTION)
	lua.lua_pushnil(L)
	for lua.lua_next(L, 1) != 0 {
		lua.lua_pushvalue(L, 2)
		lua.lua_pushvalue(L, -3) // key
		lua.lua_pushvalue(L, -3) // value
		lua.lua_call(L, 2, 1)
		if lua.lua_isnil(L, -1) == false {
			return 1
		}
		lua.lua_pop(L, 2) // remove value and result
	}
	return 0
}

table_foreachi :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	n := aux_getn(L, 1)
	lua.luaL_checktype(L, 2, lua.LUA_TFUNCTION)
	for i := 1; i <= n; i += 1 {
		lua.lua_pushvalue(L, 2)
		lua.lua_pushinteger(L, lua.Integer(i))
		lua.lua_rawgeti(L, 1, c.int(i))
		lua.lua_call(L, 2, 1)
		if lua.lua_isnil(L, -1) == false {
			return 1
		}
		lua.lua_pop(L, 1)
	}
	return 0
}

// Quicksort implementation
sort_comp :: proc "c" (L: ^lua.State, a, b: c.int) -> bool {
	if lua.lua_isnil(L, 2) == false {
		lua.lua_pushvalue(L, 2)
		lua.lua_pushvalue(L, a - 1)
		lua.lua_pushvalue(L, b - 2)
		lua.lua_call(L, 2, 1)
		res := lua.lua_toboolean(L, -1) != 0
		lua.lua_pop(L, 1)
		return res
	} else {
		return lua.lua_lessthan(L, a, b) != 0
	}
}

set2 :: proc "c" (L: ^lua.State, i, j: int) {
	lua.lua_rawseti(L, 1, c.int(i))
	lua.lua_rawseti(L, 1, c.int(j))
}

auxsort :: proc "c" (L: ^lua.State, l, u: int) {
	l_var := l
	u_var := u
	for l_var < u_var {
		i, j: int
		lua.lua_rawgeti(L, 1, c.int(l_var))
		lua.lua_rawgeti(L, 1, c.int(u_var))
		if sort_comp(L, -1, -2) {
			set2(L, l_var, u_var)
		} else {
			lua.lua_pop(L, 2)
		}
		if u_var - l_var == 1 {
			break
		}
		i = (l_var + u_var) / 2
		lua.lua_rawgeti(L, 1, c.int(i))
		lua.lua_rawgeti(L, 1, c.int(l_var))
		if sort_comp(L, -2, -1) {
			set2(L, i, l_var)
		} else {
			lua.lua_pop(L, 1)
			lua.lua_rawgeti(L, 1, c.int(u_var))
			if sort_comp(L, -1, -2) {
				set2(L, i, u_var)
			} else {
				lua.lua_pop(L, 2)
			}
		}
		if u_var - l_var == 2 {
			break
		}
		lua.lua_rawgeti(L, 1, c.int(i))
		lua.lua_pushvalue(L, -1)
		lua.lua_rawgeti(L, 1, c.int(u_var - 1))
		set2(L, i, u_var - 1)
		i = l_var
		j = u_var - 1
		for {
			for {
				i += 1
				lua.lua_rawgeti(L, 1, c.int(i))
				if !sort_comp(L, -1, -2) {
					break
				}
				lua.lua_pop(L, 1)
			}
			for {
				j -= 1
				lua.lua_rawgeti(L, 1, c.int(j))
				if !sort_comp(L, -3, -1) {
					break
				}
				lua.lua_pop(L, 1)
			}
			if j < i {
				lua.lua_pop(L, 3)
				break
			}
			set2(L, i, j)
		}
		lua.lua_rawgeti(L, 1, c.int(u_var - 1))
		lua.lua_rawgeti(L, 1, c.int(i))
		set2(L, u_var - 1, i)
		if i - l_var < u_var - i {
			auxsort(L, l_var, i - 1)
			l_var = i + 1
		} else {
			auxsort(L, i + 1, u_var)
			u_var = i - 1
		}
	}
}

table_sort :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	n := aux_getn(L, 1)
	lua.luaL_checkstack(L, 40, "")
	if lua.lua_isnoneornil(L, 2) == false {
		lua.luaL_checktype(L, 2, lua.LUA_TFUNCTION)
	}
	lua.lua_settop(L, 2)
	auxsort(L, 1, n)
	return 0
}

import "core:fmt"

@(export)
open_table :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	tablib := [?]lua.Reg {
		{"concat", table_concat},
		{"insert", table_insert},
		{"remove", table_remove},
		{"getn", table_getn},
		{"setn", table_setn},
		{"maxn", table_maxn},
		{"pack", table_pack},
		{"unpack", table_unpack},
		{"foreach", table_foreach},
		{"foreachi", table_foreachi},
		{"sort", table_sort},
		{nil, nil},
	}
	lua.luaL_register(L, "table", &tablib[0])
	// Get the table we just created/updated
	lua.lua_getfield(L, -1, "insert")
	insert_type := lua.lua_type(L, -1)
	_ = insert_type
	// 	fmt.printf(
	// 		"DEBUG: open_table: table lib registered, insert type=%d (6=function)\n",
	// 		insert_type,
	// 	)
	lua.lua_pop(L, 1)
	return 1
}
