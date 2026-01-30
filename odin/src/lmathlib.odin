package main

import "core:c"
import "core:math"
import "core:math/rand"
import "lua"

// Implementation of math library functions

math_abs :: proc "c" (L: ^lua.State) -> c.int {
	n := lua.luaL_checknumber(L, 1)
	lua.lua_pushnumber(L, abs(n))
	return 1
}

math_sin :: proc "c" (L: ^lua.State) -> c.int {
	n := lua.luaL_checknumber(L, 1)
	lua.lua_pushnumber(L, math.sin(n))
	return 1
}

math_cos :: proc "c" (L: ^lua.State) -> c.int {
	n := lua.luaL_checknumber(L, 1)
	lua.lua_pushnumber(L, math.cos(n))
	return 1
}

math_tan :: proc "c" (L: ^lua.State) -> c.int {
	n := lua.luaL_checknumber(L, 1)
	lua.lua_pushnumber(L, math.tan(n))
	return 1
}

math_ceil :: proc "c" (L: ^lua.State) -> c.int {
	n := lua.luaL_checknumber(L, 1)
	lua.lua_pushnumber(L, math.ceil(n))
	return 1
}

math_floor :: proc "c" (L: ^lua.State) -> c.int {
	n := lua.luaL_checknumber(L, 1)
	lua.lua_pushnumber(L, math.floor(n))
	return 1
}

math_sqrt :: proc "c" (L: ^lua.State) -> c.int {
	n := lua.luaL_checknumber(L, 1)
	lua.lua_pushnumber(L, math.sqrt(n))
	return 1
}

// TODO: Implement rest of functions

@(export)
luaopen_math_odin :: proc "c" (L: ^lua.State) -> c.int {
	mathlib := [?]lua.Reg {
		{"abs", math_abs},
		{"sin", math_sin},
		{"cos", math_cos},
		{"tan", math_tan},
		{"ceil", math_ceil},
		{"floor", math_floor},
		{"sqrt", math_sqrt},
		{nil, nil},
	}

	lua.luaL_register(L, "math", &mathlib[0])

	lua.lua_pushnumber(L, math.PI)
	lua.lua_setfield(L, -2, "pi")

	lua.lua_pushnumber(L, math.INF_F64)
	lua.lua_setfield(L, -2, "huge")

	return 1
}
