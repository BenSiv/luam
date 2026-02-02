package core

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:mem"

// --- Constants & Types ---
LUA_REGISTRYINDEX :: -10000
LUA_ENVIRONINDEX :: -10001
LUA_GLOBALSINDEX :: -10002
LUAI_MAXCSTACK :: 8000 // Default from luaconf.h usually

lua_Integer :: c.ptrdiff_t
lua_CFunction :: CFunction

// Map C macro to Odin global
luaO_nilobject := nilobject

// getcurrenv_helper
getcurrenv_helper :: #force_inline proc(L: ^lua_State) -> ^Table {
	if L.ci == L.base_ci {
		return hvalue(gt(L))
	}
	return clvalue(L.ci.func).c.env
}


index2adr :: proc(L: ^lua_State, idx: c.int) -> ^TValue {
	if idx > 0 {
		o := cast(^TValue)mem.ptr_offset(L.base, int(idx - 1))
		// api_check(L, idx <= L.ci.top - L.base)
		if o >= L.top {
			return cast(^TValue)luaO_nilobject
		}
		return o
	} else if idx > LUA_REGISTRYINDEX {
		// api_check(L, idx != 0 && -idx <= L.top - L.base)
		return cast(^TValue)mem.ptr_offset(L.top, int(idx))
	} else {
		switch idx {
		case LUA_REGISTRYINDEX:
			return registry(L)
		case LUA_ENVIRONINDEX:
			func := curr_func(L)
			sethvalue(L, &L.env, func.c.env)
			return &L.env
		case LUA_GLOBALSINDEX:
			return gt(L)
		case:
			func := curr_func(L)
			idx_up := LUA_GLOBALSINDEX - idx
			if int(idx_up) <= int(func.c.nupvalues) {
				return &func.c.upvalue[idx_up - 1]
			}
			return cast(^TValue)luaO_nilobject
		}
	}
}

api_checknelems :: #force_inline proc(L: ^lua_State, n: int) {
	// api_check(L, (n) <= (L.top - L.base))
}

api_checkvalidindex :: #force_inline proc(L: ^lua_State, o: ^TValue) {
	// api_check(L, o != luaO_nilobject)
}

@(export, link_name = "luaA_pushobject")
luaA_pushobject :: proc "c" (L: ^lua_State, o: ^TValue) {
	context = runtime.default_context()
	setobj2s(L, L.top, o)
	api_incr_top(L)
}

api_incr_top :: #force_inline proc(L: ^lua_State) {
	// api_check(L, L.top < L.ci.top)
	L.top = cast(StkId)mem.ptr_offset(L.top, 1)
}

// --- Basic Stack Manipulation ---

@(export, link_name = "lua_newuserdata")
lua_newuserdata :: proc "c" (L: ^lua_State, size: c.size_t) -> rawptr {
	context = runtime.default_context()
	luaC_checkGC(L)
	u := luaS_newudata(L, size, getcurrenv_helper(L))
	setuvalue(L, L.top, u)
	api_incr_top(L)
	return mem.ptr_offset(u, 1)
}

@(export, link_name = "lua_newthread")
lua_newthread :: proc "c" (L: ^lua_State) -> ^lua_State {
	context = runtime.default_context()
	luaC_checkGC(L)
	L1 := luaE_newthread(L)
	setthvalue(L, L.top, L1)
	api_incr_top(L)
	return L1
}

@(export, link_name = "lua_atpanic")
lua_atpanic :: proc "c" (L: ^lua_State, panicf: lua_CFunction) -> lua_CFunction {
	context = runtime.default_context()
	old := G(L).panic
	G(L).panic = panicf
	return old
}

@(export, link_name = "lua_checkstack")
lua_checkstack :: proc "c" (L: ^lua_State, size: c.int) -> c.int {
	context = runtime.default_context()
	res := 1
	// lua_lock(L)
	if size > LUAI_MAXCSTACK || (mem.ptr_sub(L.top, L.base) + int(size)) > LUAI_MAXCSTACK {
		res = 0 // stack overflow
	} else if size > 0 {
		luaD_checkstack(L, int(size))
		if mem.ptr_sub(L.ci.top, cast(StkId)mem.ptr_offset(L.top, int(size))) < 0 {
			L.ci.top = cast(StkId)mem.ptr_offset(L.top, int(size))
		}
	}
	// lua_unlock(L)
	return c.int(res)
}

@(export, link_name = "lua_xmove")
lua_xmove :: proc "c" (from: ^lua_State, to: ^lua_State, n: c.int) {
	context = runtime.default_context()
	if from == to {return}
	// lua_lock(to)
	// api_checknelems(from, n)
	// api_check(from, G(from) == G(to))
	// api_check(from, to.ci.top - to.top >= n)
	from.top = cast(StkId)mem.ptr_offset(from.top, -int(n))
	for i in 0 ..< int(n) {
		setobj2s(to, cast(StkId)mem.ptr_offset(to.top, i), cast(StkId)mem.ptr_offset(from.top, i))
	}
	to.top = cast(StkId)mem.ptr_offset(to.top, int(n))
	// lua_unlock(to)
}

@(export, link_name = "lua_gettop")
lua_gettop :: proc "c" (L: ^lua_State) -> c.int {
	return c.int(mem.ptr_sub(L.top, L.base))
}

@(export, link_name = "lua_settop")
lua_settop :: proc "c" (L: ^lua_State, idx: c.int) {
	context = runtime.default_context()
	// lua_lock(L)
	if idx >= 0 {
		// api_check(L, idx <= L.stack_last - L.base)
		for mem.ptr_sub(L.top, L.base) < int(idx) {
			setnilvalue(L.top)
			L.top = cast(StkId)mem.ptr_offset(L.top, 1)
		}
		L.top = cast(StkId)mem.ptr_offset(L.base, int(idx))
	} else {
		// api_check(L, -(idx + 1) <= (L.top - L.base))
		L.top = cast(StkId)mem.ptr_offset(L.top, int(idx + 1))
	}
	// lua_unlock(L)
}

@(export, link_name = "lua_remove")
lua_remove :: proc "c" (L: ^lua_State, idx: c.int) {
	context = runtime.default_context()
	p := index2adr(L, idx)
	// api_checkvalidindex(L, p)
	for mem.ptr_sub(mem.ptr_offset(p, 1), L.top) < 0 {
		setobjs2s(L, p, mem.ptr_offset(p, 1))
		p = mem.ptr_offset(p, 1)
	}
	L.top = cast(StkId)mem.ptr_offset(L.top, -1)
}

@(export, link_name = "lua_insert")
lua_insert :: proc "c" (L: ^lua_State, idx: c.int) {
	context = runtime.default_context()
	p := index2adr(L, idx)
	// api_checkvalidindex(L, p)
	for q := L.top; mem.ptr_sub(q, p) > 0; q = mem.ptr_offset(q, -1) {
		setobjs2s(L, q, mem.ptr_offset(q, -1))
	}
	setobjs2s(L, p, L.top)
}

@(export, link_name = "lua_replace")
lua_replace :: proc "c" (L: ^lua_State, idx: c.int) {
	context = runtime.default_context()
	// lua_lock(L)
	if idx == LUA_ENVIRONINDEX && L.ci == L.base_ci {
		luaG_runerror(L, "no calling environment")
	}
	// api_checknelems(L, 1)
	o := index2adr(L, idx)
	// api_checkvalidindex(L, o)
	if idx == LUA_ENVIRONINDEX {
		func := curr_func(L)
		// api_check(L, ttistable(L.top - 1))
		func.c.env = hvalue(mem.ptr_offset(L.top, -1))
		luaC_barrier(L, func, mem.ptr_offset(L.top, -1))
	} else {
		setobj(o, mem.ptr_offset(L.top, -1))
		if idx < LUA_GLOBALSINDEX {
			luaC_barrier(L, curr_func(L), mem.ptr_offset(L.top, -1))
		}
	}
	L.top = cast(StkId)mem.ptr_offset(L.top, -1)
	// lua_unlock(L)
}

@(export, link_name = "lua_pushvalue")
lua_pushvalue :: proc "c" (L: ^lua_State, idx: c.int) {
	context = runtime.default_context()
	// lua_lock(L)
	setobj2s(L, L.top, index2adr(L, idx))
	api_incr_top(L)
	// lua_unlock(L)
}

// --- Access Functions ---

LUA_TNONE :: -1

@(export, link_name = "lua_type")
lua_type :: proc "c" (L: ^lua_State, idx: c.int) -> c.int {
	context = runtime.default_context()
	o := index2adr(L, idx)
	if o == nilobject {
		return LUA_TNONE
	}
	return c.int(ttype(o))
}

@(export, link_name = "lua_typename")
lua_typename :: proc "c" (L: ^lua_State, t: c.int) -> cstring {
	// No context needed for simple array lookup?
	// But passing cstring back to C?
	// global 'typenames' is in Odin.
	// We need context to access globals if they are thread-local?
	// 'typenames' is a global constant array.
	if t == LUA_TNONE {
		return "no value"
	}
	return typenames[t]
}

@(export, link_name = "lua_iscfunction")
lua_iscfunction :: proc "c" (L: ^lua_State, idx: c.int) -> c.int {
	context = runtime.default_context()
	o := index2adr(L, idx)
	return c.int(iscfunction(o))
}

@(export, link_name = "lua_isnumber")
lua_isnumber :: proc "c" (L: ^lua_State, idx: c.int) -> c.int {
	context = runtime.default_context()
	n: TValue
	o := index2adr(L, idx)
	return c.int(tonumber(o, &n))
}

@(export, link_name = "lua_isstring")
lua_isstring :: proc "c" (L: ^lua_State, idx: c.int) -> c.int {
	context = runtime.default_context()
	t := lua_type(L, idx)
	return c.int(t == LUA_TSTRING || t == LUA_TNUMBER)
}

@(export, link_name = "lua_isuserdata")
lua_isuserdata :: proc "c" (L: ^lua_State, idx: c.int) -> c.int {
	context = runtime.default_context()
	o := index2adr(L, idx)
	return c.int(ttisuserdata(o) || ttislightuserdata(o))
}

@(export, link_name = "lua_rawequal")
lua_rawequal :: proc "c" (L: ^lua_State, index1: c.int, index2: c.int) -> c.int {
	context = runtime.default_context()
	o1 := index2adr(L, index1)
	o2 := index2adr(L, index2)
	if o1 == luaO_nilobject || o2 == luaO_nilobject {
		return 0
	}
	return c.int(rawequalObj(o1, o2))
}

@(export, link_name = "lua_equal")
lua_equal :: proc "c" (L: ^lua_State, index1: c.int, index2: c.int) -> c.int {
	context = runtime.default_context()
	// lua_lock(L)
	o1 := index2adr(L, index1)
	o2 := index2adr(L, index2)
	i := 0
	if o1 != luaO_nilobject && o2 != luaO_nilobject && equalobj(L, o1, o2) {
		i = 1
	}
	// lua_unlock(L)
	return c.int(i)
}

@(export, link_name = "lua_lessthan")
lua_lessthan :: proc "c" (L: ^lua_State, index1: c.int, index2: c.int) -> c.int {
	context = runtime.default_context()
	// lua_lock(L)
	o1 := index2adr(L, index1)
	o2 := index2adr(L, index2)
	i := 0
	if o1 != luaO_nilobject && o2 != luaO_nilobject && luaV_lessthan(L, o1, o2) != 0 {
		i = 1
	}
	// lua_unlock(L)
	return c.int(i)
}

@(export, link_name = "lua_tonumber")
lua_tonumber :: proc "c" (L: ^lua_State, idx: c.int) -> lua_Number {
	context = runtime.default_context()
	n: TValue
	o := index2adr(L, idx)
	if tonumber(o, &n) {
		return nvalue(o)
	}
	return 0
}

@(export, link_name = "lua_tointeger")
lua_tointeger :: proc "c" (L: ^lua_State, idx: c.int) -> lua_Integer {
	context = runtime.default_context()
	n: TValue
	o := index2adr(L, idx)
	if tonumber(o, &n) {
		res: lua_Integer
		num := nvalue(o)
		lua_number2integer(&res, num)
		return res
	}
	return 0
}

@(export, link_name = "lua_toboolean")
lua_toboolean :: proc "c" (L: ^lua_State, idx: c.int) -> c.int {
	context = runtime.default_context()
	o := index2adr(L, idx)
	return c.int(!l_isfalse(o))
}

@(export, link_name = "lua_tolstring")
lua_tolstring :: proc "c" (L: ^lua_State, idx: c.int, len: ^c.size_t) -> cstring {
	context = runtime.default_context()
	o := index2adr(L, idx)
	if !ttisstring(o) {
		// lua_lock(L)
		if luaV_tostring(L, o) == 0 {
			if len != nil {len^ = 0}
			// lua_unlock(L)
			return nil
		}
		luaC_checkGC(L)
		o = index2adr(L, idx)
		// lua_unlock(L)
	}
	if len != nil {
		len^ = tsvalue(o).tsv.len
	}
	return svalue(o)
}

@(export, link_name = "lua_objlen")
lua_objlen :: proc "c" (L: ^lua_State, idx: c.int) -> c.size_t {
	context = runtime.default_context()
	o := index2adr(L, idx)
	switch ttype(o) {
	case LUA_TSTRING:
		return tsvalue(o).tsv.len
	case LUA_TUSERDATA:
		return uvalue(o).uv.len
	case LUA_TTABLE:
		return c.size_t(luaH_getn(hvalue(o)))
	case LUA_TNUMBER:
		return 0 // old behavior? Lua 5.1 return len of string number? No, 0.
	case:
		return 0
	}
}

@(export, link_name = "lua_tocfunction")
lua_tocfunction :: proc "c" (L: ^lua_State, idx: c.int) -> lua_CFunction {
	context = runtime.default_context()
	o := index2adr(L, idx)
	return (!iscfunction(o)) ? nil : clvalue(o).c.f
}

@(export, link_name = "lua_touserdata")
lua_touserdata :: proc "c" (L: ^lua_State, idx: c.int) -> rawptr {
	context = runtime.default_context()
	o := index2adr(L, idx)
	switch ttype(o) {
	case LUA_TUSERDATA:
		return rawptr(cast(uintptr)rawuvalue(o) + size_of(Udata))
	case LUA_TLIGHTUSERDATA:
		return pvalue(o)
	case:
		return nil
	}
}

@(export, link_name = "lua_tothread")
lua_tothread :: proc "c" (L: ^lua_State, idx: c.int) -> ^lua_State {
	context = runtime.default_context()
	o := index2adr(L, idx)
	return (!ttisthread(o)) ? nil : thvalue(o)
}

@(export, link_name = "lua_topointer")
lua_topointer :: proc "c" (L: ^lua_State, idx: c.int) -> rawptr {
	context = runtime.default_context()
	o := index2adr(L, idx)
	switch ttype(o) {
	case LUA_TTABLE:
		return hvalue(o)
	case LUA_TFUNCTION:
		return clvalue(o)
	case LUA_TTHREAD:
		return thvalue(o)
	case LUA_TUSERDATA, LUA_TLIGHTUSERDATA:
		return lua_touserdata(L, idx)
	case:
		return nil
	}
}

// --- Push Functions ---

foreign import lua_core "../../obj/liblua.a"

foreign lua_core {
	@(link_name = "luaO_pushvfstring")
	luaO_pushvfstring :: proc(L: ^lua_State, fmt: cstring, argp: c.va_list) -> cstring ---
}

@(export, link_name = "lua_pushnil")
lua_pushnil :: proc "c" (L: ^lua_State) {
	context = runtime.default_context()
	// lua_lock(L)
	setnilvalue(L.top)
	api_incr_top(L)
	// lua_unlock(L)
}

@(export, link_name = "lua_pushnumber")
lua_pushnumber :: proc "c" (L: ^lua_State, n: lua_Number) {
	context = runtime.default_context()
	// lua_lock(L)
	setnvalue(L.top, n)
	api_incr_top(L)
	// lua_unlock(L)
}

@(export, link_name = "lua_pushinteger")
lua_pushinteger :: proc "c" (L: ^lua_State, n: lua_Integer) {
	context = runtime.default_context()
	// lua_lock(L)
	setnvalue(L.top, cast(lua_Number)n)
	api_incr_top(L)
	// lua_unlock(L)
}

@(export, link_name = "lua_pushlstring")
lua_pushlstring :: proc "c" (L: ^lua_State, s: cstring, len: c.size_t) {
	context = runtime.default_context()
	// lua_lock(L)
	luaC_checkGC(L)
	setsvalue2s(L, L.top, luaS_newlstr(L, s, len))
	api_incr_top(L)
	// lua_unlock(L)
}

@(export, link_name = "lua_pushstring")
lua_pushstring :: proc "c" (L: ^lua_State, s: cstring) {
	context = runtime.default_context()
	if s == nil {
		lua_pushnil(L)
	} else {
		lua_pushlstring(L, s, c.size_t(len(s)))
	}
}


@(export, link_name = "lua_pushcclosure") // lua_pushfstring omitted (C varargs not supported for export)
lua_pushcclosure :: proc "c" (L: ^lua_State, fn: lua_CFunction, n: c.int) {
	context = runtime.default_context()
	// lua_lock(L)
	luaC_checkGC(L)
	// api_checknelems(L, n)
	cl := luaF_newCclosure(L, n, getcurrenv_helper(L))
	cl.c.f = fn
	L.top = cast(StkId)mem.ptr_offset(L.top, -int(n))
	for i in 0 ..< int(n) {
		setobj(&cl.c.upvalue[i], cast(StkId)mem.ptr_offset(L.top, i)) // No barrier needed for new obj
	}
	setclvalue(L, L.top, cl)
	// lua_assert(iswhite(obj2gco(cl)))
	api_incr_top(L)
	// lua_unlock(L)
}

@(export, link_name = "lua_pushboolean")
lua_pushboolean :: proc "c" (L: ^lua_State, b: c.int) {
	context = runtime.default_context()
	// lua_lock(L)
	setbvalue(L.top, (b != 0) ? 1 : 0)
	api_incr_top(L)
	// lua_unlock(L)
}

@(export, link_name = "lua_pushlightuserdata")
lua_pushlightuserdata :: proc "c" (L: ^lua_State, p: rawptr) {
	context = runtime.default_context()
	// lua_lock(L)
	setpvalue(L.top, p)
	api_incr_top(L)
	// lua_unlock(L)
}

@(export, link_name = "lua_pushthread")
lua_pushthread :: proc "c" (L: ^lua_State) -> c.int {
	context = runtime.default_context()
	// lua_lock(L)
	setthvalue(L, L.top, L)
	api_incr_top(L)
	// lua_unlock(L)
	return c.int(G(L).mainthread == L)
}

// --- Get Functions ---

@(export, link_name = "lua_gettable")
lua_gettable :: proc "c" (L: ^lua_State, idx: c.int) {
	context = runtime.default_context()
	// lua_lock(L)
	t := index2adr(L, idx)
	// api_checkvalidindex(L, t)
	luaV_gettable(L, t, mem.ptr_offset(L.top, -1), mem.ptr_offset(L.top, -1))
	// lua_unlock(L)
}

@(export, link_name = "lua_getfield")
lua_getfield :: proc "c" (L: ^lua_State, idx: c.int, k: cstring) {
	context = runtime.default_context()
	key: TValue
	// lua_lock(L)
	t := index2adr(L, idx)
	// api_checkvalidindex(L, t)
	setsvalue2s(L, &key, luaS_new(L, k))
	luaV_gettable(L, t, &key, L.top)
	api_incr_top(L)
	// lua_unlock(L)
}

@(export, link_name = "lua_rawget")
lua_rawget :: proc "c" (L: ^lua_State, idx: c.int) {
	context = runtime.default_context()
	// lua_lock(L)
	t := index2adr(L, idx)
	// api_check(L, ttistable(t))
	setobj2s(L, mem.ptr_offset(L.top, -1), luaH_get(hvalue(t), mem.ptr_offset(L.top, -1)))
	// lua_unlock(L)
}

@(export, link_name = "lua_rawgeti")
lua_rawgeti :: proc "c" (L: ^lua_State, idx: c.int, n: c.int) {
	context = runtime.default_context()
	// lua_lock(L)
	o := index2adr(L, idx)
	// api_check(L, ttistable(o))
	setobj2s(L, L.top, luaH_getnum(hvalue(o), n))
	api_incr_top(L)
	// lua_unlock(L)
}

@(export, link_name = "lua_createtable")
lua_createtable :: proc "c" (L: ^lua_State, narray: c.int, nrec: c.int) {
	context = runtime.default_context()
	// lua_lock(L)
	luaC_checkGC(L)
	sethvalue(L, L.top, luaH_new(L, narray, nrec))
	api_incr_top(L)
	// lua_unlock(L)
}

@(export, link_name = "lua_getmetatable")
lua_getmetatable :: proc "c" (L: ^lua_State, objindex: c.int) -> c.int {
	context = runtime.default_context()
	mt: ^Table = nil
	res: int = 0
	// lua_lock(L)
	obj := index2adr(L, objindex)
	switch ttype(obj) {
	case LUA_TTABLE:
		mt = hvalue(obj).metatable
	case LUA_TUSERDATA:
		mt = uvalue(obj).uv.metatable
	case:
		mt = G(L).mt[ttype(obj)]
	}
	if mt == nil {
		res = 0
	} else {
		sethvalue(L, L.top, mt)
		api_incr_top(L)
		res = 1
	}
	// lua_unlock(L)
	return c.int(res)
}

// ... (skipping to lua_gc)

// In lua_gc (need to target it separately if range is far, but let's check line numbers)
// lua_getmetatable ends at 588 (originally 577). Garbage is until 642.
// lua_gc is further down (around 882 in original, maybe shifted).
// I will split the calls.

@(export, link_name = "lua_getfenv")
lua_getfenv :: proc "c" (L: ^lua_State, idx: c.int) {
	context = runtime.default_context()
	// lua_lock(L)
	o := index2adr(L, idx)
	// api_checkvalidindex(L, o)
	switch ttype(o) {
	case LUA_TFUNCTION:
		sethvalue(L, L.top, clvalue(o).c.env)
	case LUA_TUSERDATA:
		sethvalue(L, L.top, uvalue(o).uv.env)
	case LUA_TTHREAD:
		setobj2s(L, L.top, gt(thvalue(o)))
	case:
		setnilvalue(L.top)
	}
	api_incr_top(L)
	// lua_unlock(L)
}

// --- Set Functions ---

@(export, link_name = "lua_settable")
lua_settable :: proc "c" (L: ^lua_State, idx: c.int) {
	context = runtime.default_context()
	// lua_lock(L)
	// api_checknelems(L, 2)
	t := index2adr(L, idx)
	// api_checkvalidindex(L, t)
	luaV_settable(L, t, mem.ptr_offset(L.top, -2), mem.ptr_offset(L.top, -1))
	L.top = cast(StkId)mem.ptr_offset(L.top, -2)
	// lua_unlock(L)
}

@(export, link_name = "lua_setfield")
lua_setfield :: proc "c" (L: ^lua_State, idx: c.int, k: cstring) {
	context = runtime.default_context()
	key: TValue
	// lua_lock(L)
	// api_checknelems(L, 1)
	t := index2adr(L, idx)
	// api_checkvalidindex(L, t)
	setsvalue2s(L, &key, luaS_new(L, k))
	luaV_settable(L, t, &key, mem.ptr_offset(L.top, -1))
	L.top = cast(StkId)mem.ptr_offset(L.top, -1)
	// lua_unlock(L)
}

@(export, link_name = "lua_rawset")
lua_rawset :: proc "c" (L: ^lua_State, idx: c.int) {
	context = runtime.default_context()
	// lua_lock(L)
	// api_checknelems(L, 2)
	t := index2adr(L, idx)
	// api_check(L, ttistable(t))
	val := mem.ptr_offset(L.top, -1)
	key := mem.ptr_offset(L.top, -2)
	setobj2t(L, luaH_set(L, hvalue(t), key), val)
	luaC_barriert(L, hvalue(t), val)
	L.top = cast(StkId)mem.ptr_offset(L.top, -2)
	// lua_unlock(L)
}

@(export, link_name = "lua_rawseti")
lua_rawseti :: proc "c" (L: ^lua_State, idx: c.int, n: c.int) {
	context = runtime.default_context()
	// lua_lock(L)
	// api_checknelems(L, 1)
	o := index2adr(L, idx)
	// api_check(L, ttistable(o))
	val := mem.ptr_offset(L.top, -1)
	setobj2t(L, luaH_setnum(L, hvalue(o), n), val)

	luaC_barriert(L, hvalue(o), val)
	L.top = cast(StkId)mem.ptr_offset(L.top, -1)
	// lua_unlock(L)
}

@(export, link_name = "lua_setmetatable")
lua_setmetatable :: proc "c" (L: ^lua_State, objindex: c.int) -> c.int {
	context = runtime.default_context()
	mt: ^Table
	// lua_lock(L)
	// api_checknelems(L, 1)
	obj := index2adr(L, objindex)
	// api_checkvalidindex(L, obj)
	if ttisnil(mem.ptr_offset(L.top, -1)) {
		mt = nil
	} else {
		// api_check(L, ttistable(L.top - 1))
		mt = hvalue(mem.ptr_offset(L.top, -1))
	}
	switch ttype(obj) {
	case LUA_TTABLE:
		hvalue(obj).metatable = mt
		if mt != nil {
			luaC_objbarriert(L, hvalue(obj), mt)
		}
	case LUA_TUSERDATA:
		uvalue(obj).uv.metatable = mt
		if mt != nil {
			luaC_objbarrier(L, rawuvalue(obj), mt)
		}
	case:
		G(L).mt[ttype(obj)] = mt
	}
	L.top = cast(StkId)mem.ptr_offset(L.top, -1)
	// lua_unlock(L)
	return 1
}

@(export, link_name = "lua_setfenv")
lua_setfenv :: proc "c" (L: ^lua_State, idx: c.int) -> c.int {
	context = runtime.default_context()
	res := 1
	// lua_lock(L)
	// api_checknelems(L, 1)
	o := index2adr(L, idx)
	// api_checkvalidindex(L, o)
	// api_check(L, ttistable(L.top - 1))
	env := hvalue(mem.ptr_offset(L.top, -1))
	switch ttype(o) {
	case LUA_TFUNCTION:
		clvalue(o).c.env = env
	case LUA_TUSERDATA:
		uvalue(o).uv.env = env
	case LUA_TTHREAD:
		sethvalue(L, gt(thvalue(o)), env)
	case:
		res = 0
	}
	if res != 0 {
		luaC_objbarrier(L, gcvalue(o), env)
	}
	L.top = cast(StkId)mem.ptr_offset(L.top, -1)
	// lua_unlock(L)
	return c.int(res)
}

// GC constants
LUA_GCSTOP :: 0
LUA_GCRESTART :: 1
LUA_GCCOLLECT :: 2
LUA_GCCOUNT :: 3
LUA_GCCOUNTB :: 4
LUA_GCSTEP :: 5
LUA_GCSETPAUSE :: 6
LUA_GCSETSTEPMUL :: 7

// Removed duplicate lua_load and lua_pushcclosure
// Keeping lua_call and structure valid.

@(export, link_name = "lua_call")
lua_call :: proc "c" (L: ^lua_State, nargs: c.int, nresults: c.int) {
	context = runtime.default_context()
	luaD_call_pure(L, cast(StkId)mem.ptr_offset(L.top, -int(nargs + 1)), nresults)
}

// Barrier helpers matching macros
luaC_objbarriert :: #force_inline proc(L: ^lua_State, t: ^Table, o: ^Table) {
	// luaC_barrierback(L, t) or just luaC_barrier
	// lgc.h: #define luaC_objbarriert(L,h,o)  { if (isblack(obj2gco(h)) && iswhite(obj2gco(o))) luaC_barrierback(L,h); }
	// We need luaC_barrierback from gc.odin (exported as luaC_barrierback)
	// But api.odin is in same package, so accessible directly if not private.
	// luaC_barrierback is exported in gc.odin.
	if isblack(obj2gco(t)) && iswhite(obj2gco(o)) {
		luaC_barrierback(L, t)
	}
}

luaC_objbarrier :: #force_inline proc(L: ^lua_State, p: rawptr, o: rawptr) {
	// lgc.h: #define luaC_objbarrier(L,p,o)  { if (isblack(obj2gco(p)) && iswhite(obj2gco(o))) luaC_barrierf(L,obj2gco(p),obj2gco(o)); }
	// luaC_barrierf is exported in gc.odin.
	if isblack(obj2gco(p)) && iswhite(obj2gco(o)) {
		luaC_barrierf(L, obj2gco(p), obj2gco(o))
	}
}


// lua_pushcclosure (kept this one in correct sequence)
// Removing duplicate @ 463
// wait, replace_file_content replaces range.
// I will target the DUPLICATE one at 758 and remove it.
// And target duplicate lua_load at 739 (Wait, I want to KEEP one).
// Previous view showed lua_load at 739 AND 858.
// I'll keep 739 (it was in the view) or 858?
// 739 is inside "Call, Load & GC Functions" section?
// View 543 lines 738+:
// @(export, link_name = "lua_load") ...
// View 520 lines 863+:
// @(export, link_name = "lua_dump") ...
// View 520 had lua_load at 852.
// So I have two lua_load.
// I will remove the one at 852 (end of file).

// I will remove lua_pushcclosure at 758 (near end of file in View 543).

// I'll also add getcurrenv_helper near line 20 (Helper Functions).

struct_CCallS :: struct {
	func: lua_CFunction,
	ud:   rawptr,
}

f_Ccall :: proc "c" (L: ^lua_State, ud: rawptr) {
	context = runtime.default_context()
	cs := cast(^struct_CCallS)ud
	luaC_checkGC(L)
	cl := luaF_newCclosure(L, 0, getcurrenv_helper(L))
	cl.c.f = cs.func
	setgcvalue(L.top, cast(^GCObject)cl, LUA_TFUNCTION)
	api_incr_top(L)
	setpvalue(L.top, cs.ud)
	api_incr_top(L)
	luaD_call_pure(L, cast(StkId)mem.ptr_offset(L.top, -2), 0)
}

struct_CallS :: struct {
	func:     StkId,
	nresults: c.int,
}

f_call :: proc "c" (L: ^lua_State, ud: rawptr) {
	context = runtime.default_context()
	cs := cast(^struct_CallS)ud
	luaD_call_pure(L, cs.func, cs.nresults)
}

@(export, link_name = "lua_pcall")
lua_pcall :: proc "c" (L: ^lua_State, nargs: c.int, nresults: c.int, errfunc: c.int) -> c.int {
	context = runtime.default_context()
	cs: struct_CallS
	status: c.int
	func: c.ptrdiff_t
	if errfunc == 0 {
		func = 0
	} else {
		o := index2adr(L, errfunc)
		func = savestack(L, o)
	}
	cs.func = cast(StkId)mem.ptr_offset(L.top, -int(nargs + 1))
	cs.nresults = nresults
	status = luaD_pcall_c(L, f_call, &cs, savestack(L, cs.func), func)
	return status
}

@(export, link_name = "lua_cpcall")
lua_cpcall :: proc "c" (L: ^lua_State, func: lua_CFunction, ud: rawptr) -> c.int {
	context = runtime.default_context()
	cs: struct_CCallS
	status: c.int
	cs.func = func
	cs.ud = ud
	status = luaD_pcall_c(L, f_Ccall, &cs, savestack(L, L.top), 0)
	return status
}

@(export, link_name = "lua_load")
lua_load :: proc "c" (
	L: ^lua_State,
	reader: lua_Reader,
	data: rawptr,
	chunkname: cstring,
) -> c.int {
	context = runtime.default_context()
	z: ZIO
	status: c.int
	cname := chunkname
	if cname == nil {cname = "?"}
	luaZ_init(L, &z, cast(Reader)cast(rawptr)reader, data)
	status = luaD_protectedparser(L, &z, cname)
	return status
}

@(export, link_name = "lua_dump")
lua_dump :: proc "c" (L: ^lua_State, writer: lua_Writer, data: rawptr) -> c.int {
	context = runtime.default_context()
	status: c.int
	o := mem.ptr_offset(L.top, -1)
	if isLfunction(o) {
		status = luaU_dump(L, clvalue(o).l.p, writer, data, 0)
	} else {
		status = 1
	}
	return status
}

@(export, link_name = "lua_getupvalue")
lua_getupvalue :: proc "c" (L: ^lua_State, funcindex: c.int, n: c.int) -> cstring {
	context = runtime.default_context()
	fi := index2adr(L, funcindex)
	if !ttisfunction(fi) {return nil}
	cl := clvalue(fi)
	name: cstring
	val: ^TValue
	if cl.c.isC != 0 {
		if n < 1 || n > c.int(cl.c.nupvalues) {return nil}
		name = "" // C upvalues have no names
		val = &cl.c.upvalue[n - 1]
	} else {
		p := cl.l.p
		if n < 1 || n > c.int(p.sizeupvalues) {return nil}
		name = svalue(cast(^TValue)&p.upvalues[n - 1]) // Simplified name access
		val = cl.l.upvals[n - 1].v
	}
	setobj2s(L, L.top, val)
	api_incr_top(L)
	return name
}

@(export, link_name = "lua_setupvalue")
lua_setupvalue :: proc "c" (L: ^lua_State, funcindex: c.int, n: c.int) -> cstring {
	context = runtime.default_context()
	fi := index2adr(L, funcindex)
	if !ttisfunction(fi) {return nil}
	cl := clvalue(fi)
	name: cstring
	val: ^TValue
	if cl.c.isC != 0 {
		if n < 1 || n > c.int(cl.c.nupvalues) {return nil}
		name = ""
		val = &cl.c.upvalue[n - 1]
	} else {
		p := cl.l.p
		if n < 1 || n > c.int(p.sizeupvalues) {return nil}
		name = svalue(cast(^TValue)&p.upvalues[n - 1])
		val = cl.l.upvals[n - 1].v
	}
	L.top = cast(StkId)mem.ptr_offset(L.top, -1)
	setobj(val, L.top)
	luaC_barrier(L, cl, L.top)
	return name
}

@(export, link_name = "lua_setlevel")
lua_setlevel :: proc "c" (from: ^lua_State, to: ^lua_State) {
	to.nCcalls = from.nCcalls
}

@(export, link_name = "lua_status")
lua_status :: proc "c" (L: ^lua_State) -> c.int {
	return c.int(L.status)
}

@(export, link_name = "lua_gc")
lua_gc :: proc "c" (L: ^lua_State, what: c.int, data: c.int) -> c.int {
	context = runtime.default_context()
	res: int = 0
	g := G(L)
	switch what {
	case LUA_GCSTOP:
		g.GCthreshold = MAX_SIZET
	case LUA_GCRESTART:
		g.GCthreshold = g.totalbytes
	case LUA_GCCOLLECT:
		luaC_fullgc(L)
	case LUA_GCCOUNT:
		res = int(g.totalbytes) >> 10
	case LUA_GCCOUNTB:
		res = int(g.totalbytes) & 1023
	case LUA_GCSTEP:
		a := (cast(u32)data << 10) - 1024
		if a <= 0 {a = 0}
		g.GCthreshold = g.totalbytes - c.size_t(a)
		luaC_step(L)
		res = 1
	case LUA_GCSETPAUSE:
		res = int(g.gcpause)
		g.gcpause = c.int(data)
	case LUA_GCSETSTEPMUL:
		res = int(g.gcstepmul)
		g.gcstepmul = c.int(data)
	}
	return c.int(res)
}

@(export, link_name = "lua_error")
lua_error :: proc "c" (L: ^lua_State) -> c.int {
	context = runtime.default_context()
	luaG_errormsg_c(L)
	return 0
}

@(export, link_name = "lua_next")
lua_next :: proc "c" (L: ^lua_State, idx: c.int) -> c.int {
	context = runtime.default_context()
	t := index2adr(L, idx)
	more := luaH_next(L, hvalue(t), mem.ptr_offset(L.top, -1))
	if more != 0 {
		api_incr_top(L)
	} else {
		L.top = cast(StkId)mem.ptr_offset(L.top, -1)
	}
	return c.int(more)
}

@(export, link_name = "lua_concat")
lua_concat :: proc "c" (L: ^lua_State, n: c.int) {
	context = runtime.default_context()
	luaV_concat(
		L,
		int(n),
		int(cast(c.ptrdiff_t)(cast(uintptr)L.top - cast(uintptr)L.base) / size_of(TValue)) - 1,
	)
	L.top = cast(StkId)mem.ptr_offset(L.top, -int(n - 1))
}
