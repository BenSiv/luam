// Stack and Call structure of Lua
// Migrated from ldo.c/h
package core

import "core:c"

// Protected function type
Pfunc :: #type proc "c" (L: ^lua_State, ud: rawptr)

// Error codes
LUA_YIELD :: 1
LUA_ERRRUN :: 2
LUA_ERRSYNTAX :: 3
LUA_ERRMEM :: 4
LUA_ERRERR :: 5

// Precall return codes
PCRLUA :: 0 // Lua function
PCRC :: 1 // C function
PCRYIELD :: 2 // Yielded

// Max C calls
LUAI_MAXCCALLS :: 200
LUAI_MAXCALLS :: 20000


// Stack save/restore helpers
savestack :: #force_inline proc(L: ^lua_State, p: StkId) -> c.ptrdiff_t {
	return c.ptrdiff_t(cast(uintptr)p - cast(uintptr)L.stack)
}

restorestack :: #force_inline proc(L: ^lua_State, n: c.ptrdiff_t) -> StkId {
	return cast(StkId)(cast(uintptr)L.stack + uintptr(n))
}

// CI save/restore helpers
saveci :: #force_inline proc(L: ^lua_State, ci: ^CallInfo) -> c.ptrdiff_t {
	return c.ptrdiff_t(cast(uintptr)ci - cast(uintptr)L.base_ci)
}

restoreci :: #force_inline proc(L: ^lua_State, n: c.ptrdiff_t) -> ^CallInfo {
	return cast(^CallInfo)(cast(uintptr)L.base_ci + uintptr(n))
}

// Increment top of stack
incr_top :: #force_inline proc(L: ^lua_State) {
	L.top = cast(StkId)(cast(uintptr)L.top + size_of(TValue))
}

// Check stack has n slots available
luaD_checkstack :: #force_inline proc(L: ^lua_State, n: int) {
	if cast(uintptr)L.stack_last - cast(uintptr)L.top <= uintptr(n * size_of(TValue)) {
		luaD_growstack_c(L, c.int(n))
	}
}

// FFI to C functions (temporarily needed for protected calls)
foreign import lua_core "../../obj/liblua.a"

foreign lua_core {
	@(link_name = "luaD_growstack")
	luaD_growstack_c :: proc(L: ^lua_State, n: c.int) ---
	@(link_name = "luaD_throw")
	luaD_throw_c :: proc(L: ^lua_State, errcode: c.int) ---
	@(link_name = "luaD_rawrunprotected")
	luaD_rawrunprotected_c :: proc(L: ^lua_State, f: Pfunc, ud: rawptr) -> c.int ---
	@(link_name = "luaD_reallocstack")
	luaD_reallocstack_c :: proc(L: ^lua_State, newsize: c.int) ---
	@(link_name = "luaD_reallocCI")
	luaD_reallocCI_c :: proc(L: ^lua_State, newsize: c.int) ---
	// luaD_precall, luaD_poscall, luaD_call removed (replaced by pure Odin versions)
	@(link_name = "luaD_pcall")
	luaD_pcall_c :: proc(L: ^lua_State, func: Pfunc, u: rawptr, old_top: c.ptrdiff_t, ef: c.ptrdiff_t) -> c.int ---
	@(link_name = "luaG_runerror")
	luaG_runerror_c :: proc(L: ^lua_State, fmt: cstring, #c_vararg args: ..any) ---
	luaV_execute_c :: proc(L: ^lua_State, nexeccalls: c.int) ---
	@(link_name = "luaD_protectedparser")
	luaD_protectedparser :: proc(L: ^lua_State, z: ^ZIO, name: cstring) -> c.int ---
	@(link_name = "luaU_dump")
	luaU_dump :: proc(L: ^lua_State, p: ^Proto, writer: lua_Writer, data: rawptr, strip: c.int) -> c.int ---
}

// Correct stack pointers after reallocation
correctstack :: proc(L: ^lua_State, oldstack: ^TValue) {
	old_base := cast(uintptr)oldstack
	new_base := cast(uintptr)L.stack

	// Correct L->top
	L.top = cast(StkId)(cast(uintptr)L.top - old_base + new_base)

	// Correct open upvalues
	up := L.openupval
	for up != nil {
		uv := gco2uv(up)
		uv.v = cast(^TValue)(cast(uintptr)uv.v - old_base + new_base)
		up = up.gch.next
	}

	// Correct CallInfo pointers
	ci := L.base_ci
	for cast(uintptr)ci <= cast(uintptr)L.ci {
		ci.top = cast(StkId)(cast(uintptr)ci.top - old_base + new_base)
		ci.base = cast(StkId)(cast(uintptr)ci.base - old_base + new_base)
		ci.func = cast(StkId)(cast(uintptr)ci.func - old_base + new_base)
		ci = cast(^CallInfo)(cast(uintptr)ci + size_of(CallInfo))
	}

	// Correct L->base
	L.base = cast(StkId)(cast(uintptr)L.base - old_base + new_base)
}

// Grow call info array
growCI :: proc(L: ^lua_State) -> ^CallInfo {
	if L.size_ci > LUAI_MAXCALLS {
		luaD_throw_c(L, LUA_ERRERR)
	}
	luaD_reallocCI_c(L, 2 * L.size_ci)
	if L.size_ci > LUAI_MAXCALLS {
		luaG_runerror_c(L, "stack overflow")
	}
	L.ci = cast(^CallInfo)(cast(uintptr)L.ci + size_of(CallInfo))
	return L.ci
}

// Increment CI
inc_ci :: #force_inline proc(L: ^lua_State) -> ^CallInfo {
	if L.ci == L.end_ci {
		return growCI(L)
	}
	L.ci = cast(^CallInfo)(cast(uintptr)L.ci + size_of(CallInfo))
	return L.ci
}

// Call debug hook
luaD_callhook :: proc(L: ^lua_State, event: int, line: int) {
	hook := L.hook
	if hook != nil && L.allowhook != 0 {
		top := savestack(L, L.top)
		ci_top := savestack(L, L.ci.top)

		ar: lua_Debug
		ar.event = c.int(event)
		ar.currentline = c.int(line)
		if event == LUA_HOOKTAILRET {
			ar.i_ci = 0
		} else {
			ar.i_ci = c.int((cast(uintptr)L.ci - cast(uintptr)L.base_ci) / size_of(CallInfo))
		}

		luaD_checkstack(L, LUA_MINSTACK)
		L.ci.top = cast(StkId)(cast(uintptr)L.top + uintptr(LUA_MINSTACK * size_of(TValue)))
		L.allowhook = 0

		hook(L, &ar)

		L.allowhook = 1
		L.ci.top = restorestack(L, ci_top)
		L.top = restorestack(L, top)
	}
}

// Set TValue setters that need L parameter (for GC barriers)
setsvalue2s :: #force_inline proc(L: ^lua_State, obj: ^TValue, ts: ^TString) {
	obj.value.gc = obj2gco(ts)
	obj.tt = LUA_TSTRING
}

setobjs2s :: #force_inline proc(L: ^lua_State, obj1: ^TValue, obj2: ^TValue) {
	obj1.value = obj2.value
	obj1.tt = obj2.tt
}

sethvalue :: #force_inline proc(L: ^lua_State, obj: ^TValue, h: ^Table) {
	obj.value.gc = obj2gco(h)
	obj.tt = LUA_TTABLE
}

setclvalue :: #force_inline proc(L: ^lua_State, obj: ^TValue, cl: ^Closure) {
	obj.value.gc = obj2gco(cl)
	obj.tt = LUA_TFUNCTION
}

// Closure value accessor
clvalue :: #force_inline proc(o: ^TValue) -> ^Closure {
	return cast(^Closure)o.value.gc
}

// Table value accessor
hvalue :: #force_inline proc(o: ^TValue) -> ^Table {
	return cast(^Table)o.value.gc
}

// Set error object
luaD_seterrorobj :: proc(L: ^lua_State, errcode: int, oldtop: StkId) {
	switch errcode {
	case LUA_ERRMEM:
		ts := luaS_new(L, MEMERRMSG)
		setsvalue2s(L, oldtop, ts)
	case LUA_ERRERR:
		ts := luaS_new(L, "error in error handling")
		setsvalue2s(L, oldtop, ts)
	case LUA_ERRSYNTAX, LUA_ERRRUN:
		// Error message is already on top of stack
		prev := cast(^TValue)(cast(uintptr)L.top - size_of(TValue))
		setobjs2s(L, oldtop, prev)
	}
	L.top = cast(StkId)(cast(uintptr)oldtop + size_of(TValue))
}
