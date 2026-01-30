// Auxiliary functions to manipulate prototypes and closures
// Migrated from lfunc.c/h
package core

import "core:c"

// Size calculations for closures
sizeCclosure :: #force_inline proc(n: int) -> c.size_t {
	return size_of(CClosure) + size_of(TValue) * c.size_t(n - 1) if n > 1 else size_of(CClosure)
}

sizeLclosure :: #force_inline proc(n: int) -> c.size_t {
	return size_of(LClosure) + size_of(^UpVal) * c.size_t(n - 1) if n > 1 else size_of(LClosure)
}

// FFI to C functions (needed until full integration)
@(private)
foreign import lua_core "system:lua"

@(private)
foreign lua_core {
	luaC_link_c :: proc(L: ^lua_State, o: ^GCObject, tt: c.int) ---
	luaC_linkupval_c :: proc(L: ^lua_State, uv: ^UpVal) ---
	luaM_malloc_c :: proc(L: ^lua_State, size: c.size_t) -> rawptr ---
	luaM_free_c :: proc(L: ^lua_State, block: rawptr, size: c.size_t) ---
	luaM_freemem_c :: proc(L: ^lua_State, block: rawptr, size: c.size_t) ---
}

// Create new C closure
luaF_newCclosure :: proc(L: ^lua_State, nelems: int, e: ^Table) -> ^Closure {
	c := cast(^Closure)luaM_malloc_c(L, sizeCclosure(nelems))
	luaC_link_c(L, obj2gco(c), LUA_TFUNCTION)
	c.c.isC = 1
	c.c.env = e
	c.c.nupvalues = u8(nelems)
	return c
}

// Create new Lua closure
luaF_newLclosure :: proc(L: ^lua_State, nelems: int, e: ^Table) -> ^Closure {
	cl := cast(^Closure)luaM_malloc_c(L, sizeLclosure(nelems))
	luaC_link_c(L, obj2gco(cl), LUA_TFUNCTION)
	cl.l.isC = 0
	cl.l.env = e
	cl.l.nupvalues = u8(nelems)
	// Initialize upvals to nil
	upvals := cast([^]^UpVal)(cast(uintptr)&cl.l.upvals[0])
	for i in 0 ..< nelems {
		upvals[i] = nil
	}
	return cl
}

// Create new upvalue
luaF_newupval :: proc(L: ^lua_State) -> ^UpVal {
	uv := cast(^UpVal)luaM_malloc_c(L, size_of(UpVal))
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
luaF_findupval :: proc(L: ^lua_State, level: StkId) -> ^UpVal {
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
		pp = cast(^^GCObject)&p.next
	}

	// Not found: create a new one
	uv := cast(^UpVal)luaM_malloc_c(L, size_of(UpVal))
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
@(private)
unlinkupval :: proc(uv: ^UpVal) {
	uv.u.l.next.u.l.prev = uv.u.l.prev
	uv.u.l.prev.u.l.next = uv.u.l.next
}

// Free upvalue
luaF_freeupval :: proc(L: ^lua_State, uv: ^UpVal) {
	if uv.v != &uv.u.value { 	// is it open?
		unlinkupval(uv) // remove from open list
	}
	luaM_free_c(L, uv, size_of(UpVal))
}

// GC black check
isblack :: #force_inline proc(x: ^GCObject) -> bool {
	return (x.gch.marked & (1 << BLACKBIT)) != 0
}

// Close all upvalues up to given stack level
luaF_close :: proc(L: ^lua_State, level: StkId) {
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
			setobj(uv.v, &uv.u.value) // copy to own storage
			uv.v = &uv.u.value // now current value lives here
			luaC_linkupval_c(L, uv) // link upvalue into `gcroot' list
		}
	}
}

// Create new function prototype
luaF_newproto :: proc(L: ^lua_State) -> ^Proto {
	f := cast(^Proto)luaM_malloc_c(L, size_of(Proto))
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
luaF_freeproto :: proc(L: ^lua_State, f: ^Proto) {
	if f.code != nil && f.sizecode > 0 {
		luaM_freemem_c(L, f.code, c.size_t(f.sizecode) * size_of(Instruction))
	}
	if f.p != nil && f.sizep > 0 {
		luaM_freemem_c(L, f.p, c.size_t(f.sizep) * size_of(^Proto))
	}
	if f.k != nil && f.sizek > 0 {
		luaM_freemem_c(L, f.k, c.size_t(f.sizek) * size_of(TValue))
	}
	if f.lineinfo != nil && f.sizelineinfo > 0 {
		luaM_freemem_c(L, f.lineinfo, c.size_t(f.sizelineinfo) * size_of(c.int))
	}
	if f.locvars != nil && f.sizelocvars > 0 {
		luaM_freemem_c(L, f.locvars, c.size_t(f.sizelocvars) * size_of(LocVar))
	}
	if f.upvalues != nil && f.sizeupvalues > 0 {
		luaM_freemem_c(L, f.upvalues, c.size_t(f.sizeupvalues) * size_of(^TString))
	}
	luaM_free_c(L, f, size_of(Proto))
}

// Free closure
luaF_freeclosure :: proc(L: ^lua_State, cl: ^Closure) {
	size :=
		sizeCclosure(int(cl.c.nupvalues)) if cl.c.isC != 0 else sizeLclosure(int(cl.l.nupvalues))
	luaM_freemem_c(L, cl, size)
}

// Get local variable name at given PC
luaF_getlocalname :: proc(f: ^Proto, local_number: int, pc: int) -> cstring {
	local_num := local_number
	for i in 0 ..< int(f.sizelocvars) {
		if f.locvars[i].startpc <= c.int(pc) {
			if pc < int(f.locvars[i].endpc) {
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
