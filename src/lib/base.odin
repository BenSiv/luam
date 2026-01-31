package lib

import "../lua"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strconv"
import "core:strings"

// --- Constants ---

CO_RUN :: 0
CO_SUS :: 1
CO_NOR :: 2
CO_DEAD :: 3

statnames: [4]cstring = {"running", "suspended", "normal", "dead"}

// --- Fundamental Globals ---

base_print :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	n := lua.lua_gettop(L)
	lua.lua_getglobal(L, "tostring")
	for i: c.int = 1; i <= n; i += 1 {
		lua.lua_pushvalue(L, -1) // function
		lua.lua_pushvalue(L, i) // arg
		lua.lua_call(L, 1, 1)
		s := lua.lua_tostring(L, -1)
		if s == nil {
			return lua.luaL_error(L, "'tostring' must return a string to 'print'")
		}
		if i > 1 {
			fmt.print("\t")
		}
		fmt.print(s)
		lua.lua_pop(L, 1)
	}
	fmt.println()
	return 0
}

base_tonumber :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	base := int(lua.luaL_optinteger(L, 2, 10))
	if base == 10 {
		lua.luaL_checkany(L, 1)
		if lua.lua_isnumber(L, 1) {
			lua.lua_pushnumber(L, lua.lua_tonumber(L, 1))
			return 1
		}
	} else {
		s1 := lua.luaL_checkstring(L, 1)
		lua.luaL_argcheck(L, c.int(2 <= base && base <= 36), 2, "base out of range")

		s_str := string(s1)
		val, ok := strconv.parse_u64(s_str, base)
		if ok {
			lua.lua_pushnumber(L, f64(val))
			return 1
		}
	}
	lua.lua_pushnil(L)
	return 1
}

base_error :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	level := int(lua.luaL_optinteger(L, 2, 1))
	lua.lua_settop(L, 1)
	if lua.lua_isstring(L, 1) && level > 0 {
		lua.luaL_where(L, c.int(level))
		lua.lua_pushvalue(L, 1)
		lua.lua_concat(L, 2)
	}
	return lua.lua_error(L)
}

base_type :: proc "c" (L: ^lua.State) -> c.int {
	lua.luaL_checkany(L, 1)
	lua.lua_pushstring(L, lua.lua_typename(L, lua.lua_type(L, 1)))
	return 1
}

base_tostring :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.luaL_checkany(L, 1)
	if lua.luaL_callmeta(L, 1, "__tostring") != 0 {
		return 1
	}
	tt := lua.lua_type(L, 1)
	switch tt {
	case lua.LUA_TNUMBER:
		lua.lua_pushstring(L, lua.lua_tostring(L, 1))
	case lua.LUA_TSTRING:
		lua.lua_pushvalue(L, 1)
	case lua.LUA_TBOOLEAN:
		if lua.lua_toboolean(L, 1) != 0 {
			lua.lua_pushstring(L, "true")
		} else {
			lua.lua_pushstring(L, "false")
		}
	case lua.LUA_TNIL:
		lua.lua_pushliteral(L, "nil")

	case:
		{
			tn := lua.lua_typename(L, tt)
			ptr := lua.lua_topointer(L, 1)
			s := fmt.tprintf("%s: %p", tn, ptr)
			lua.lua_pushstring(L, strings.clone_to_cstring(s, context.temp_allocator))
		}
	}
	return 1
}

base_assert :: proc "c" (L: ^lua.State) -> c.int {
	lua.luaL_checkany(L, 1)
	if lua.lua_toboolean(L, 1) == 0 {
		return lua.luaL_error(L, "%s", lua.luaL_optstring(L, 2, "assertion failed!"))
	}
	return lua.lua_gettop(L)
}

base_select :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	n := lua.lua_gettop(L)
	if lua.lua_type(L, 1) == lua.LUA_TSTRING {
		s := lua.lua_tostring(L, 1)
		s_ptr := ([^]u8)(s)
		if s_ptr[0] == '#' {
			lua.lua_pushinteger(L, lua.Integer(n - 1))
			return 1
		}
	}

	i := c.int(lua.luaL_checkinteger(L, 1))
	if i < 0 {
		i = n + i
	} else if i > n {
		i = n
	}
	lua.luaL_argcheck(L, c.int(1 <= i), 1, "index out of range")
	return n - i
}

base_collectgarbage :: proc "c" (L: ^lua.State) -> c.int {
	opts := [?]cstring {
		"stop",
		"restart",
		"collect",
		"count",
		"step",
		"setpause",
		"setstepmul",
		nil,
	}
	optsnum := [?]c.int {
		lua.LUA_GCSTOP,
		lua.LUA_GCRESTART,
		lua.LUA_GCCOLLECT,
		lua.LUA_GCCOUNT,
		lua.LUA_GCSTEP,
		lua.LUA_GCSETPAUSE,
		lua.LUA_GCSETSTEPMUL,
	}
	o := int(lua.luaL_checkoption(L, 1, "collect", &opts[0]))
	ex := int(lua.luaL_optinteger(L, 2, 0))
	res := lua.lua_gc(L, optsnum[o], c.int(ex))
	switch optsnum[o] {
	case lua.LUA_GCCOUNT:
		b := lua.lua_gc(L, lua.LUA_GCCOUNTB, 0)
		lua.lua_pushnumber(L, f64(res) + (f64(b) / 1024))
		return 1
	case lua.LUA_GCSTEP:
		lua.lua_pushboolean(L, res)
		return 1
	case:
		lua.lua_pushnumber(L, f64(res))
		return 1
	}
}

// --- Table Ops ---

base_rawequal :: proc "c" (L: ^lua.State) -> c.int {
	lua.luaL_checkany(L, 1)
	lua.luaL_checkany(L, 2)
	lua.lua_pushboolean(L, lua.lua_rawequal(L, 1, 2))
	return 1
}

base_rawget :: proc "c" (L: ^lua.State) -> c.int {
	lua.luaL_checktype(L, 1, lua.LUA_TTABLE)
	lua.luaL_checkany(L, 2)
	lua.lua_settop(L, 2)
	lua.lua_rawget(L, 1)
	return 1
}

base_rawset :: proc "c" (L: ^lua.State) -> c.int {
	lua.luaL_checktype(L, 1, lua.LUA_TTABLE)
	lua.luaL_checkany(L, 2)
	lua.luaL_checkany(L, 3)
	lua.lua_settop(L, 3)
	lua.lua_rawset(L, 1)
	return 1
}

base_next :: proc "c" (L: ^lua.State) -> c.int {
	lua.luaL_checktype(L, 1, lua.LUA_TTABLE)
	lua.lua_settop(L, 2)
	if lua.lua_next(L, 1) != 0 {
		return 2
	} else {
		lua.lua_pushnil(L)
		return 1
	}
}

base_pairs :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.luaL_checktype(L, 1, lua.LUA_TTABLE)
	lua.lua_pushvalue(L, lua.lua_upvalueindex(1)) // next
	lua.lua_pushvalue(L, 1) // table
	lua.lua_pushnil(L)
	return 3
}

ipairsaux :: proc "c" (L: ^lua.State) -> c.int {
	i := int(lua.luaL_checkinteger(L, 2))
	lua.luaL_checktype(L, 1, lua.LUA_TTABLE)
	i += 1
	lua.lua_pushinteger(L, lua.Integer(i))
	lua.lua_rawgeti(L, 1, c.int(i))
	if lua.lua_isnil(L, -1) {
		return 0
	} else {
		return 2
	}
}

base_ipairs :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.luaL_checktype(L, 1, lua.LUA_TTABLE)
	lua.lua_pushvalue(L, lua.lua_upvalueindex(1)) // ipairsaux
	lua.lua_pushvalue(L, 1) // table
	lua.lua_pushinteger(L, 0)
	return 3
}

// --- Loading ---

load_aux :: proc "c" (L: ^lua.State, status: c.int) -> c.int {
	if status == 0 {
		return 1
	} else {
		lua.lua_pushnil(L)
		lua.lua_insert(L, -2)
		return 2
	}
}

base_loadstring :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sz: c.size_t
	s := lua.luaL_checklstring(L, 1, &sz)
	chunkname := lua.luaL_optstring(L, 2, s)
	return load_aux(L, lua.luaL_loadbuffer(L, s, sz, chunkname))
}

base_loadfile :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	fname := lua.luaL_optstring(L, 1, nil)
	return load_aux(L, lua.luaL_loadfile(L, fname))
}

base_dofile :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	fname := lua.luaL_optstring(L, 1, nil)
	n := lua.lua_gettop(L)
	if lua.luaL_loadfile(L, fname) != 0 {
		return lua.lua_error(L)
	}
	lua.lua_call(L, 0, lua.LUA_MULTRET)
	return lua.lua_gettop(L) - n
}

generic_reader :: proc "c" (L: ^lua.State, ud: rawptr, size: ^c.size_t) -> cstring {
	context = runtime.default_context()
	lua.luaL_checkstack(L, 2, "too many nested functions")
	lua.lua_pushvalue(L, 1)
	lua.lua_call(L, 0, 1)
	if lua.lua_isnil(L, -1) {
		size^ = 0
		return nil
	} else if lua.lua_isstring(L, -1) {
		lua.lua_replace(L, 3)
		return lua.lua_tolstring(L, 3, size)
	} else {
		lua.luaL_error(L, "reader function must return a string")
	}
	return nil
}

base_load :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cname := lua.luaL_optstring(L, 2, "=(load)")
	if lua.lua_type(L, 1) == lua.LUA_TSTRING {
		sz: c.size_t
		s := lua.lua_tolstring(L, 1, &sz)
		return load_aux(L, lua.luaL_loadbuffer(L, s, sz, cname))
	} else {
		lua.luaL_checktype(L, 1, lua.LUA_TFUNCTION)
		lua.lua_settop(L, 3)
		status := lua.lua_load(L, generic_reader, nil, cname)
		return load_aux(L, status)
	}
}

// --- Protected Call ---

base_pcall :: proc "c" (L: ^lua.State) -> c.int {
	lua.luaL_checkany(L, 1)
	status := lua.lua_pcall(L, lua.lua_gettop(L) - 1, lua.LUA_MULTRET, 0)
	if status == 0 {
		lua.lua_pushboolean(L, 1)
	} else {
		lua.lua_pushboolean(L, 0)
	}
	lua.lua_insert(L, 1)
	return lua.lua_gettop(L)
}

base_xpcall :: proc "c" (L: ^lua.State) -> c.int {
	n := lua.lua_gettop(L)
	lua.luaL_checkany(L, 2)
	lua.lua_pushvalue(L, 2) // error handler
	lua.lua_pushvalue(L, 1) // function
	lua.lua_replace(L, 2)
	lua.lua_replace(L, 1)
	status := lua.lua_pcall(L, n - 2, lua.LUA_MULTRET, 1)
	if status == 0 {
		lua.lua_pushboolean(L, 1)
	} else {
		lua.lua_pushboolean(L, 0)
	}
	lua.lua_replace(L, 1)
	return lua.lua_gettop(L)
}

// --- Coroutines ---

costatus :: proc "c" (L: ^lua.State, co: ^lua.State) -> c.int {
	if L == co {
		return 0 // CO_RUN
	}
	status := lua.lua_status(co)
	if status == lua.LUA_YIELD {
		return 1 // CO_SUS
	} else if status == 0 {
		ar: lua.Debug
		if lua.lua_getstack(co, 0, &ar) > 0 {
			return 2 // CO_NOR
		} else if lua.lua_gettop(co) == 0 {
			return 3 // CO_DEAD
		} else {
			return 1 // CO_SUS
		}
	} else {
		return 3 // CO_DEAD
	}
}

base_costatus :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	co := lua.lua_tothread(L, 1)
	lua.luaL_argcheck(L, c.int(co != nil), 1, "coroutine expected")
	lua.lua_pushstring(L, statnames[costatus(L, co)])
	return 1
}

auxresume :: proc "c" (L: ^lua.State, co: ^lua.State, narg: c.int) -> c.int {
	status := costatus(L, co)
	if lua.lua_checkstack(co, narg) == 0 {
		lua.luaL_error(L, "too many arguments to resume")
	}
	if status != 1 { 	// CO_SUS
		lua.lua_pushfstring(L, "cannot resume %s coroutine", statnames[status])
		return -1
	}
	lua.lua_xmove(L, co, narg)
	lua.lua_setlevel(L, co)
	res_status := lua.lua_resume(co, narg)
	if res_status == 0 || res_status == lua.LUA_YIELD {
		nres := lua.lua_gettop(co)
		if lua.lua_checkstack(L, nres + 1) == 0 {
			lua.luaL_error(L, "too many results to resume")
		}
		lua.lua_xmove(co, L, nres)
		return nres
	} else {
		lua.lua_xmove(co, L, 1)
		return -1
	}
}

base_coresume :: proc "c" (L: ^lua.State) -> c.int {
	co := lua.lua_tothread(L, 1)
	lua.luaL_argcheck(L, c.int(co != nil), 1, "coroutine expected")
	r := auxresume(L, co, lua.lua_gettop(L) - 1)
	if r < 0 {
		lua.lua_pushboolean(L, 0)
		lua.lua_insert(L, -2)
		return 2
	} else {
		lua.lua_pushboolean(L, 1)
		lua.lua_insert(L, -(r + 1))
		return r + 1
	}
}

base_auxwrap :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	co := lua.lua_tothread(L, lua.lua_upvalueindex(1))
	r := auxresume(L, co, lua.lua_gettop(L))
	if r < 0 {
		if lua.lua_isstring(L, -1) {
			lua.luaL_where(L, 1)
			lua.lua_insert(L, -2)
			lua.lua_concat(L, 2)
		}
		return lua.lua_error(L)
	}
	return r
}

base_cocreate :: proc "c" (L: ^lua.State) -> c.int {
	NL := lua.lua_newthread(L)
	lua.luaL_argcheck(
		L,
		c.int(lua.lua_isfunction(L, 1) && (!lua.lua_iscfunction(L, 1))),
		1,
		"Lua function expected",
	)
	lua.lua_pushvalue(L, 1)
	lua.lua_xmove(L, NL, 1)
	return 1
}

base_cowrap :: proc "c" (L: ^lua.State) -> c.int {
	base_cocreate(L)
	lua.lua_pushcclosure(L, base_auxwrap, 1)
	return 1
}

base_yield :: proc "c" (L: ^lua.State) -> c.int {
	return lua.lua_yield(L, lua.lua_gettop(L))
}

base_corunning :: proc "c" (L: ^lua.State) -> c.int {
	if lua.lua_pushthread(L) != 0 {
		lua.lua_pushnil(L)
	}
	return 1
}

@(export)
open_base :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	// fmt.eprintln("DEBUG: open_base start")
	base_funcs := [?]lua.Reg {
		{"assert", base_assert},
		{"collectgarbage", base_collectgarbage},
		{"dofile", base_dofile},
		{"error", base_error},
		{"loadfile", base_loadfile},
		{"load", base_load},
		{"loadstring", base_loadstring},
		{"next", base_next},
		{"pcall", base_pcall},
		{"print", base_print},
		{"rawequal", base_rawequal},
		{"rawget", base_rawget},
		{"rawset", base_rawset},
		{"select", base_select},
		{"tonumber", base_tonumber},
		{"tostring", base_tostring},
		{"type", base_type},
		{"xpcall", base_xpcall},
		{nil, nil},
	}

	co_funcs := [?]lua.Reg {
		{"create", base_cocreate},
		{"resume", base_coresume},
		{"running", base_corunning},
		{"status", base_costatus},
		{"wrap", base_cowrap},
		{"yield", base_yield},
		{nil, nil},
	}

	// set global _G
	lua.lua_pushvalue(L, lua.LUA_GLOBALSINDEX)
	lua.lua_setglobal(L, "_G")
	// fmt.eprintln("DEBUG: open_base _G set")

	lua.luaL_register(L, "_G", &base_funcs[0])
	// fmt.eprintln("DEBUG: open_base registered")

	lua.lua_pushliteral(L, lua.LUA_VERSION)
	lua.lua_setglobal(L, "_VERSION")
	// fmt.eprintln("DEBUG: open_base _VERSION set")

	// ipairs and pairs with upvalues
	lua.pushcfunction(L, ipairsaux)
	lua.lua_pushcclosure(L, base_ipairs, 1)
	lua.lua_setglobal(L, "ipairs")
	// fmt.eprintln("DEBUG: open_base ipairs set")

	lua.pushcfunction(L, base_next)
	lua.lua_pushcclosure(L, base_pairs, 1)
	lua.lua_setglobal(L, "pairs")
	// fmt.eprintln("DEBUG: open_base pairs set")

	lua.luaL_register(L, "coroutine", &co_funcs[0])
	// fmt.eprintln("DEBUG: open_base end")

	return 2
}
