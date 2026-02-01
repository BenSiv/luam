package core

import "base:runtime"
import "core:c"

// Foreign import for error handling
foreign import lua_core "../../obj/liblua.a"

@(private)
foreign lua_core {
	luaG_typeerror :: proc(L: ^lua_State, o: ^TValue, op: cstring) ---
}

// Pure Odin implementations of luaD_precall, luaD_poscall, luaD_call

// Try to get __call metamethod for non-function values
tryfuncTM_pure :: #force_inline proc(L: ^lua_State, func: StkId) -> StkId {
	tm := luaT_gettmbyobj(L, func, c.int(TM.TM_CALL))
	if !ttisfunction(tm) {
		luaG_typeerror(L, func, "call")
	}

	// Open a hole in the stack at `func`
	p := L.top
	for cast(uintptr)p > cast(uintptr)func {
		setobjs2s(L, p, cast(StkId)(cast(uintptr)p - size_of(TValue)))
		p = cast(StkId)(cast(uintptr)p - size_of(TValue))
	}
	incr_top(L)

	funcr := savestack(L, func)
	func_new := restorestack(L, funcr) // previous call may change stack
	setobj2s(L, func_new, tm) // tag method is the new function to be called
	return func_new
}

// Adjust varargs for function calls
adjust_varargs_pure :: #force_inline proc(L: ^lua_State, p: ^Proto, actual: c.int) -> StkId {
	nfixargs := p.numparams
	actual_count := actual

	// Pad with nil if not enough args
	for actual_count < c.int(nfixargs) {
		setnilvalue(L.top)
		L.top = cast(StkId)(cast(uintptr)L.top + size_of(TValue))
		actual_count += 1
	}

	// Move fixed parameters to final position
	fixed := cast(StkId)(cast(uintptr)L.top - uintptr(actual_count) * size_of(TValue))
	base := L.top

	for i := c.int(0); i < c.int(nfixargs); i += 1 {
		setobjs2s(L, L.top, cast(StkId)(cast(uintptr)fixed + uintptr(i) * size_of(TValue)))
		L.top = cast(StkId)(cast(uintptr)L.top + size_of(TValue))
		setnilvalue(cast(StkId)(cast(uintptr)fixed + uintptr(i) * size_of(TValue)))
	}

	return base
}

// Call return hooks
callrethooks_pure :: #force_inline proc(L: ^lua_State, firstResult: StkId) -> StkId {
	fr := savestack(L, firstResult)
	luaD_callhook(L, LUA_HOOKRET, -1)

	if f_isLua(L.ci) {
		// Handle tail calls
		for (L.hookmask & LUA_MASKRET) != 0 && L.ci.tailcalls > 0 {
			L.ci.tailcalls -= 1
			luaD_callhook(L, LUA_HOOKTAILRET, -1)
		}
	}

	return restorestack(L, fr)
}

// Pure Odin implementation of luaD_precall
luaD_precall_pure :: proc "c" (L: ^lua_State, func_param: StkId, nresults: c.int) -> c.int {
	context = runtime.default_context()

	func := func_param

	// Check if func is actually a function
	if !ttisfunction(func) {
		func = tryfuncTM_pure(L, func)
	}

	funcr := savestack(L, func)
	cl := &clvalue(func).l
	L.ci.savedpc = L.savedpc

	if cl.isC != 1 {
		// Lua function
		ci: ^CallInfo
		base: StkId
		p := cl.p

		luaD_checkstack(L, int(p.maxstacksize))
		func = restorestack(L, funcr)

		if (p.is_vararg & VARARG_ISVARARG) == 0 {
			// No varargs
			base = cast(StkId)(cast(uintptr)func + size_of(TValue))
			if cast(uintptr)L.top > cast(uintptr)base + uintptr(p.numparams) * size_of(TValue) {
				L.top = cast(StkId)(cast(uintptr)base + uintptr(p.numparams) * size_of(TValue))
			}
		} else {
			// Vararg function
			nargs := c.int((cast(uintptr)L.top - cast(uintptr)func) / size_of(TValue)) - 1
			base = adjust_varargs_pure(L, p, nargs)
			func = restorestack(L, funcr)
		}

		ci = inc_ci(L)
		ci.func = func
		L.base = base
		ci.base = base
		ci.top = cast(StkId)(cast(uintptr)L.base + uintptr(p.maxstacksize) * size_of(TValue))
		L.savedpc = p.code
		ci.tailcalls = 0
		ci.nresults = nresults

		// Initialize stack slots to nil
		st := L.top
		for cast(uintptr)st < cast(uintptr)ci.top {
			setnilvalue(st)
			st = cast(StkId)(cast(uintptr)st + size_of(TValue))
		}
		L.top = ci.top

		if (L.hookmask & LUA_MASKCALL) != 0 {
			L.savedpc = cast([^]Instruction)(cast(uintptr)L.savedpc + size_of(Instruction))
			luaD_callhook(L, LUA_HOOKCALL, -1)
			L.savedpc = cast([^]Instruction)(cast(uintptr)L.savedpc - size_of(Instruction))
		}

		return PCRLUA
	} else {
		// C function
		ci: ^CallInfo

		luaD_checkstack(L, LUA_MINSTACK)
		ci = inc_ci(L)
		ci.func = restorestack(L, funcr)
		L.base = cast(StkId)(cast(uintptr)ci.func + size_of(TValue))
		ci.base = L.base
		ci.top = cast(StkId)(cast(uintptr)L.top + uintptr(LUA_MINSTACK) * size_of(TValue))
		ci.nresults = nresults

		if (L.hookmask & LUA_MASKCALL) != 0 {
			luaD_callhook(L, LUA_HOOKCALL, -1)
		}

		// Call the C function
		n := curr_func(L).c.f(L)

		if n < 0 {
			// Yielding
			return PCRYIELD
		} else {
			luaD_poscall_pure(L, cast(StkId)(cast(uintptr)L.top - uintptr(n) * size_of(TValue)))
			return PCRC
		}
	}
}

// Pure Odin implementation of luaD_poscall
luaD_poscall_pure :: proc "c" (L: ^lua_State, firstResult_param: StkId) -> c.int {
	context = runtime.default_context()

	firstResult := firstResult_param

	if (L.hookmask & LUA_MASKRET) != 0 {
		firstResult = callrethooks_pure(L, firstResult)
	}

	ci := L.ci
	L.ci = cast(^CallInfo)(cast(uintptr)L.ci - size_of(CallInfo))

	res := ci.func
	wanted := ci.nresults
	prev_ci := cast(^CallInfo)(cast(uintptr)ci - size_of(CallInfo))
	L.base = prev_ci.base
	L.savedpc = prev_ci.savedpc

	// Move results to correct place
	i := wanted
	for i != 0 && cast(uintptr)firstResult < cast(uintptr)L.top {
		setobjs2s(L, res, firstResult)
		res = cast(StkId)(cast(uintptr)res + size_of(TValue))
		firstResult = cast(StkId)(cast(uintptr)firstResult + size_of(TValue))
		i -= 1
	}

	// Pad with nil if needed
	for i > 0 {
		setnilvalue(res)
		res = cast(StkId)(cast(uintptr)res + size_of(TValue))
		i -= 1
	}

	L.top = res

	if wanted == LUA_MULTRET {
		return 0
	} else {
		return wanted - LUA_MULTRET
	}
}

// Pure Odin implementation of luaD_call
luaD_call_pure :: proc "c" (L: ^lua_State, func: StkId, nResults: c.int) {
	context = runtime.default_context()

	L.nCcalls += 1
	if L.nCcalls >= LUAI_MAXCCALLS {
		if L.nCcalls == LUAI_MAXCCALLS {
			luaG_runerror(L, "C stack overflow")
		} else if L.nCcalls >= (LUAI_MAXCCALLS + (LUAI_MAXCCALLS >> 3)) {
			luaD_throw(L, LUA_ERRERR)
		}
	}

	if luaD_precall_pure(L, func, nResults) == PCRLUA {
		luaV_execute(L, 1)
	}

	L.nCcalls -= 1
	luaC_checkGC(L)
}
