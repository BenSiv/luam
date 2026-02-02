// Auxiliary functions to manipulate prototypes and closures
// Migrated from lfunc.c/h
package core

import "base:runtime"
import "core:c"
import "core:fmt"

// Size calculations for closures
sizeCclosure :: #force_inline proc(n: int) -> c.size_t {
	return size_of(CClosure) + size_of(TValue) * c.size_t(n - 1) if n > 1 else size_of(CClosure)
}

sizeLclosure :: #force_inline proc(n: int) -> c.size_t {
	return size_of(LClosure) + size_of(^UpVal) * c.size_t(n - 1) if n > 1 else size_of(LClosure)
}

// FFI to C functions (needed until full integration)
foreign import lua_core "../../obj/liblua.a"

foreign lua_core {
}

luaC_link_c :: luaC_link
luaC_linkupval_c :: luaC_linkupval


// Memory allocation functions now in core/mem.odin (pure Odin implementation)

// Create new C closure
@(export, link_name = "luaF_newCclosure")
luaF_newCclosure :: proc "c" (L: ^lua_State, nelems: c.int, e: ^Table) -> ^Closure {
	context = runtime.default_context()
	c := cast(^Closure)luaM_malloc(L, sizeCclosure(int(nelems)))
	luaC_link_c(L, obj2gco(c), LUA_TFUNCTION)
	c.c.isC = 1
	c.c.env = e
	c.c.nupvalues = u8(nelems)
	return c
}

// Create new Lua closure
@(export, link_name = "luaF_newLclosure")
luaF_newLclosure :: proc "c" (L: ^lua_State, nelems: c.int, e: ^Table) -> ^Closure {
	context = runtime.default_context()
	fmt.printf("DEBUG: luaF_newLclosure called. nelems=%d e=%p\n", nelems, e)
	cl := cast(^Closure)luaM_malloc(L, sizeLclosure(int(nelems)))
	luaC_link_c(L, obj2gco(cl), LUA_TFUNCTION)
	cl.l.isC = 0
	cl.l.env = e
	cl.l.nupvalues = u8(nelems)
	// Initialize upvals to nil
	upvals := cast([^]^UpVal)(cast(uintptr)&cl.l.upvals[0])
	for i in 0 ..< int(nelems) {
		upvals[i] = nil
	}
	return cl
}

// Create new upvalue
@(export, link_name = "luaF_newupval")
luaF_newupval :: proc "c" (L: ^lua_State) -> ^UpVal {
	context = runtime.default_context()
	uv := cast(^UpVal)luaM_malloc(L, size_of(UpVal))
	luaC_link_c(L, obj2gco(uv), LUA_TUPVAL)
	uv.v = &uv.u.value
	setnilvalue(uv.v)
	return uv
}

// Convert GCObject to UpVal (handles nil)
ngcotouv :: #force_inline proc(o: ^GCObject) -> ^UpVal {
	if o == nil {return nil}
	return &o.uv
}

// Find or create upvalue for stack level
@(export, link_name = "luaF_findupval")
luaF_findupval :: proc "c" (L: ^lua_State, level: StkId) -> ^UpVal {
	context = runtime.default_context()
	g := G(L)
	pp := &L.openupval

	// Search for existing upvalue
	for pp^ != nil {
		p := ngcotouv(pp^)
		if p.v == nil || cast(uintptr)p.v < cast(uintptr)level {
			break
		}
		if p.v == level {
			// Found a corresponding upvalue
			if isdead(g, obj2gco(p)) {
				changewhite(obj2gco(p)) // resurrect it
			}
			return p
		}
		pp = &p.next
	}

	// Not found: create a new one
	uv := cast(^UpVal)luaM_malloc(L, size_of(UpVal))
	uv.tt = LUA_TUPVAL
	uv.marked = luaC_white(g)
	uv.v = level // current value lives in the stack
	uv.next = pp^ // chain it in the proper position
	pp^ = obj2gco(uv)

	// Double link it in `uvhead' list
	uv.u.l.prev = &g.uvhead
	uv.u.l.next = g.uvhead.u.l.next
	uv.u.l.next.u.l.prev = uv
	g.uvhead.u.l.next = uv

	return uv
}

// Unlink upvalue from uvhead list
unlinkupval :: proc(uv: ^UpVal) {
	uv.u.l.next.u.l.prev = uv.u.l.prev
	uv.u.l.prev.u.l.next = uv.u.l.next
}

// Free upvalue
@(export, link_name = "luaF_freeupval")
luaF_freeupval :: proc "c" (L: ^lua_State, uv: ^UpVal) {
	context = runtime.default_context()
	if uv.v != &uv.u.value { 	// is it open?
		unlinkupval(uv) // remove from open list
	}
	luaM_freemem(L, uv, size_of(UpVal))
}

// GC black check
isblack :: #force_inline proc(x: ^GCObject) -> bool {
	return (x.gch.marked & (1 << BLACKBIT)) != 0
}

// Close all upvalues up to given stack level
@(export, link_name = "luaF_close")
luaF_close :: proc "c" (L: ^lua_State, level: StkId) {
	context = runtime.default_context()
	g := G(L)

	for L.openupval != nil {
		uv := ngcotouv(L.openupval)
		if uv.v == nil || cast(uintptr)uv.v < cast(uintptr)level {
			break
		}

		o := obj2gco(uv)
		L.openupval = uv.next // remove from `open' list

		if isdead(g, o) {
			luaF_freeupval(L, uv) // free upvalue
		} else {
			unlinkupval(uv)
			setobj(&uv.u.value, uv.v) // copy to own storage
			uv.v = &uv.u.value // now current value lives here
			luaC_linkupval_c(L, uv) // link upvalue into `gcroot' list
		}
	}
}

// Create new function prototype
@(export, link_name = "luaF_newproto")
luaF_newproto :: proc "c" (L: ^lua_State) -> ^Proto {
	context = runtime.default_context()
	f := cast(^Proto)luaM_malloc(L, size_of(Proto))
	luaC_link_c(L, obj2gco(f), LUA_TPROTO)
	f.k = nil
	f.sizek = 0
	f.p = nil
	f.sizep = 0
	f.code = nil
	f.sizecode = 0
	f.sizelineinfo = 0
	f.sizeupvalues = 0
	f.nups = 0
	f.upvalues = nil
	f.numparams = 0
	f.is_vararg = 0
	f.maxstacksize = 0
	f.lineinfo = nil
	f.sizelocvars = 0
	f.locvars = nil
	f.linedefined = 0
	f.lastlinedefined = 0
	f.source = nil
	return f
}

// Free function prototype
@(export, link_name = "luaF_freeproto")
luaF_freeproto :: proc "c" (L: ^lua_State, f: ^Proto) {
	context = runtime.default_context()
	if f.code != nil && f.sizecode > 0 {
		luaM_freemem(L, f.code, c.size_t(f.sizecode) * size_of(Instruction))
	}
	if f.p != nil && f.sizep > 0 {
		luaM_freemem(L, f.p, c.size_t(f.sizep) * size_of(^Proto))
	}
	if f.k != nil && f.sizek > 0 {
		luaM_freemem(L, f.k, c.size_t(f.sizek) * size_of(TValue))
	}
	if f.lineinfo != nil && f.sizelineinfo > 0 {
		luaM_freemem(L, f.lineinfo, c.size_t(f.sizelineinfo) * size_of(c.int))
	}
	if f.locvars != nil && f.sizelocvars > 0 {
		luaM_freemem(L, f.locvars, c.size_t(f.sizelocvars) * size_of(LocVar))
	}
	if f.upvalues != nil && f.sizeupvalues > 0 {
		luaM_freemem(L, f.upvalues, c.size_t(f.sizeupvalues) * size_of(^TString))
	}
	luaM_freemem(L, f, size_of(Proto))
}

// Free closure
@(export, link_name = "luaF_freeclosure")
luaF_freeclosure :: proc "c" (L: ^lua_State, cl: ^Closure) {
	context = runtime.default_context()
	size :=
		sizeCclosure(int(cl.c.nupvalues)) if cl.c.isC != 0 else sizeLclosure(int(cl.l.nupvalues))
	luaM_freemem(L, cl, size)
}

// Get local variable name at given PC
@(export, link_name = "luaF_getlocalname")
luaF_getlocalname :: proc "c" (f: ^Proto, local_number: c.int, pc: c.int) -> cstring {
	context = runtime.default_context()
	local_num := int(local_number)
	for i in 0 ..< int(f.sizelocvars) {
		if f.locvars[i].startpc <= pc {
			if int(pc) < int(f.locvars[i].endpc) {
				local_num -= 1
				if local_num == 0 {
					return getstr(f.locvars[i].varname)
				}
			}
		} else {
			break
		}
	}
	return nil
}
