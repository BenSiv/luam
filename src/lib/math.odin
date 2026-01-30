package lib

import "../lua"
import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:math"
import "core:math/rand"
import "core:mem"

// Implementation of math library functions

math_abs :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	n := lua.luaL_checknumber(L, 1)
	lua.lua_pushnumber(L, abs(n))
	return 1
}

math_sin :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	n := lua.luaL_checknumber(L, 1)
	lua.lua_pushnumber(L, math.sin(n))
	return 1
}

math_cos :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	n := lua.luaL_checknumber(L, 1)
	lua.lua_pushnumber(L, math.cos(n))
	return 1
}

math_tan :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	n := lua.luaL_checknumber(L, 1)
	lua.lua_pushnumber(L, math.tan(n))
	return 1
}

math_ceil :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	n := lua.luaL_checknumber(L, 1)
	lua.lua_pushnumber(L, math.ceil(n))
	return 1
}

math_floor :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	n := lua.luaL_checknumber(L, 1)
	lua.lua_pushnumber(L, math.floor(n))
	return 1
}

math_sqrt :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	n := lua.luaL_checknumber(L, 1)
	lua.lua_pushnumber(L, math.sqrt(n))
	return 1
}

math_acos :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.lua_pushnumber(L, math.acos(lua.luaL_checknumber(L, 1)))
	return 1
}

math_asin :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.lua_pushnumber(L, math.asin(lua.luaL_checknumber(L, 1)))
	return 1
}

math_atan :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.lua_pushnumber(L, math.atan(lua.luaL_checknumber(L, 1)))
	return 1
}

math_atan2 :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.lua_pushnumber(L, math.atan2(lua.luaL_checknumber(L, 1), lua.luaL_checknumber(L, 2)))
	return 1
}

math_cosh :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.lua_pushnumber(L, math.cosh(lua.luaL_checknumber(L, 1)))
	return 1
}

math_sinh :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.lua_pushnumber(L, math.sinh(lua.luaL_checknumber(L, 1)))
	return 1
}

math_tanh :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.lua_pushnumber(L, math.tanh(lua.luaL_checknumber(L, 1)))
	return 1
}

math_deg :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.lua_pushnumber(L, lua.luaL_checknumber(L, 1) * (180.0 / math.PI))
	return 1
}

math_rad :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.lua_pushnumber(L, lua.luaL_checknumber(L, 1) * (math.PI / 180.0))
	return 1
}

math_exp :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.lua_pushnumber(L, math.exp(lua.luaL_checknumber(L, 1)))
	return 1
}

math_pow :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.lua_pushnumber(L, math.pow(lua.luaL_checknumber(L, 1), lua.luaL_checknumber(L, 2)))
	return 1
}

math_fmod :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.lua_pushnumber(L, math.mod(lua.luaL_checknumber(L, 1), lua.luaL_checknumber(L, 2)))
	return 1
}

math_modf :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	ip, fp := math.modf(lua.luaL_checknumber(L, 1))
	lua.lua_pushnumber(L, ip)
	lua.lua_pushnumber(L, fp)
	return 2
}

math_frexp :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	f, e := math.frexp(lua.luaL_checknumber(L, 1))
	lua.lua_pushnumber(L, f)
	lua.lua_pushinteger(L, lua.Integer(e))
	return 2
}

math_ldexp :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.lua_pushnumber(L, math.ldexp(lua.luaL_checknumber(L, 1), int(lua.luaL_checkinteger(L, 2))))
	return 1
}

math_log :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	x := lua.luaL_checknumber(L, 1)
	if lua.lua_isnoneornil(L, 2) {
		lua.lua_pushnumber(L, math.ln(x))
	} else {
		base := lua.luaL_checknumber(L, 2)
		if base == 10.0 {
			lua.lua_pushnumber(L, math.log10(x))
		} else {
			lua.lua_pushnumber(L, math.ln(x) / math.ln(base))
		}
	}
	return 1
}

math_log10 :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.lua_pushnumber(L, math.log10(lua.luaL_checknumber(L, 1)))
	return 1
}

math_max :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	n := lua.lua_gettop(L)
	if n < 1 {return 0}
	dmax := lua.luaL_checknumber(L, 1)
	for i in 2 ..= n {
		d := lua.luaL_checknumber(L, i)
		if d > dmax {dmax = d}
	}
	lua.lua_pushnumber(L, dmax)
	return 1
}

math_min :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	n := lua.lua_gettop(L)
	if n < 1 {return 0}
	dmin := lua.luaL_checknumber(L, 1)
	for i in 2 ..= n {
		d := lua.luaL_checknumber(L, i)
		if d < dmin {dmin = d}
	}
	lua.lua_pushnumber(L, dmin)
	return 1
}

@(private = "file")
random_state: rand.Default_Random_State
@(private = "file")
random_generator: rand.Generator
@(private = "file")
random_initialized: bool

init_random :: proc() {
	if !random_initialized {
		random_state = rand.create(0)
		random_generator = rand.default_random_generator(&random_state)
		random_initialized = true
	}
}

math_random :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	init_random()
	r := rand.float64(random_generator)
	n := lua.lua_gettop(L)
	switch n {
	case 0:
		lua.lua_pushnumber(L, r)
	case 1:
		u := lua.luaL_checkinteger(L, 1)
		if u < 1 {lua.luaL_error(L, "interval is empty")}
		lua.lua_pushnumber(L, math.floor(r * f64(u)) + 1)
	case 2:
		l := lua.luaL_checkinteger(L, 1)
		u := lua.luaL_checkinteger(L, 2)
		if l > u {lua.luaL_error(L, "interval is empty")}
		lua.lua_pushnumber(L, math.floor(r * f64(u - l + 1)) + f64(l))
	case:
		return lua.luaL_error(L, "wrong number of arguments")
	}
	return 1
}

math_randomseed :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	init_random()
	seed := u64(lua.luaL_checkinteger(L, 1))
	rand.reset(seed, random_generator)
	return 0
}

@(export)
open_math :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	mathlib := [?]lua.Reg {
		{"abs", math_abs},
		{"sin", math_sin},
		{"cos", math_cos},
		{"tan", math_tan},
		{"ceil", math_ceil},
		{"floor", math_floor},
		{"sqrt", math_sqrt},
		{"acos", math_acos},
		{"asin", math_asin},
		{"atan", math_atan},
		{"atan2", math_atan2},
		{"cosh", math_cosh},
		{"sinh", math_sinh},
		{"tanh", math_tanh},
		{"deg", math_deg},
		{"rad", math_rad},
		{"exp", math_exp},
		{"pow", math_pow},
		{"fmod", math_fmod},
		{"modf", math_modf},
		{"frexp", math_frexp},
		{"ldexp", math_ldexp},
		{"log", math_log},
		{"log10", math_log10},
		{"max", math_max},
		{"min", math_min},
		{"random", math_random},
		{"randomseed", math_randomseed},
		{nil, nil},
	}

	lua.luaL_register(L, "math", &mathlib[0])

	lua.lua_pushnumber(L, math.PI)
	lua.lua_setfield(L, -2, "pi")

	lua.lua_pushnumber(L, math.INF_F64)
	lua.lua_setfield(L, -2, "huge")

	return 1
}
