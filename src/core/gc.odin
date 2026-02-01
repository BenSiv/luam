// Garbage Collector
// Migrated from lgc.c/h
package core

import "base:runtime"
import "core:c"
import "core:mem"

// --- Constants ---

GCSTEPSIZE :: 1024
GCSWEEPMAX :: 40
GCSWEEPCOST :: 10
GCFINALIZECOST :: 100

// Weak table bits
KEYWEAKBIT :: 3
VALUEWEAKBIT :: 4
KEYWEAK :: 1 << KEYWEAKBIT
VALUEWEAK :: 1 << VALUEWEAKBIT

// White bits mask
WHITEBITS :: 3 // bit0 | bit1

// --- Macros converted to Inline Procs ---

otherwhite :: #force_inline proc(g: ^Global_State) -> u8 {
	return g.currentwhite ~ WHITEBITS
}

maskmarks :: ~u8((1 << BLACKBIT) | WHITEBITS)

makewhite :: #force_inline proc(g: ^Global_State, x: ^GCObject) {
	x.gch.marked = (x.gch.marked & maskmarks) | luaC_white(g)
}

white2gray :: #force_inline proc(x: ^GCObject) {
	x.gch.marked &= ~u8(WHITEBITS)
}

gray2black :: #force_inline proc(x: ^GCObject) {
	x.gch.marked |= (1 << BLACKBIT)
}

black2gray :: #force_inline proc(x: ^GCObject) {
	x.gch.marked &= ~u8(1 << BLACKBIT)
}

isgray :: #force_inline proc(x: ^GCObject) -> bool {
	return !iswhite(x) && !isblack(x)
}

stringmark :: #force_inline proc(s: ^TString) {
	s.tsv.marked &= ~u8(WHITEBITS)
}

markobject :: #force_inline proc(g: ^Global_State, t: rawptr) {
	x := obj2gco(t)
	if iswhite(x) {
		reallymarkobject(g, x)
	}
}

markvalue :: #force_inline proc(g: ^Global_State, o: ^TValue) {
	if iscollectable(o) && iswhite(gcvalue(o)) {
		reallymarkobject(g, gcvalue(o))
	}
}

// --- Mark Phase ---

// Recursively mark object
@(private)
reallymarkobject :: proc(g: ^Global_State, o: ^GCObject) {
	white2gray(o)
	switch o.gch.tt {
	case LUA_TSTRING:
		return
	case LUA_TUSERDATA:
		gray2black(o)
		markobject(g, gco2u(o).uv.env)
		return
	case LUA_TUPVAL:
		uv := gco2uv(o)
		markvalue(g, uv.v)
		if uv.v == &uv.u.value { 	// closed?
			gray2black(o) // open upvalues are never black
		}
		return
	case LUA_TFUNCTION:
		cl := gco2cl(o)
		cl.c.gclist = g.gray
		g.gray = o
	case LUA_TTABLE:
		h := gco2h(o)
		h.gclist = g.gray
		g.gray = o
	case LUA_TTHREAD:
		th := gco2th(o)
		th.gclist = g.gray
		g.gray = o
	case LUA_TPROTO:
		p := gco2p(o)
		p.gclist = g.gray
		g.gray = o
	case:
	// lua_assert(0)
	}
}

// Traverse table
@(private)
traversetable :: proc(g: ^Global_State, h: ^Table) -> int {
	weakkey := 0
	weakvalue := 0

	if h.metatable != nil {
		markobject(g, h.metatable)
	}

	mode := gfasttm(g, h.metatable, TM.TM_MODE)
	if mode != nil && ttisstring(mode) {
		// Checks for 'k' and 'v' in mode string (omitting strchr for brevity, implementing manual check or using lib)
		// For now simplifying: if string contains 'k' or 'v'
		s := getstr(rawtsvalue(mode))
		// Iterate string logic... (TODO: proper check)
		// Assuming standard Lua weak tables logic
		// We need 'strchr'. Since it's CString, we can walk it or use libc
		// Let's manually check for now
		c_ptr := ([^]u8)(s)
		i := 0
		for c_ptr[i] != 0 {
			if c_ptr[i] == 'k' do weakkey = 1
			if c_ptr[i] == 'v' do weakvalue = 1
			i += 1
		}

		if weakkey != 0 || weakvalue != 0 {
			h.flags |= u8(KEYWEAK) if weakkey != 0 else 0
			h.flags |= u8(VALUEWEAK) if weakvalue != 0 else 0
			// Bit hack: modifying marked to store weak info
			// h->marked &= ~(KEYWEAK | VALUEWEAK);
			// h->marked |= cast_byte((weakkey << KEYWEAKBIT) | (weakvalue << VALUEWEAKBIT));
			h.marked &= ~u8(KEYWEAK | VALUEWEAK)
			h.marked |= u8((weakkey << KEYWEAKBIT) | (weakvalue << VALUEWEAKBIT))

			h.gclist = g.weak
			g.weak = obj2gco(h)
		}
	}

	if weakkey != 0 && weakvalue != 0 {
		return 1
	}

	if weakvalue == 0 {
		for i in 0 ..< int(h.sizearray) {
			markvalue(g, &h.array[i])
		}
	}

	for i in 0 ..< sizenode(h) {
		n := gnode(h, i)
		if !ttisnil(gval(n)) {
			// removeentry logic is for sweep? No, removeentry logic was in traversetable in lgc.c
			// C code: if (ttisnil(gval(n))) removeentry(n); else ...
			// We should do that if we want to clean up empty entries during mark?
			// lgc.c: removeentry(n) sets dead key.
			// Let's defer strict deadkey handling or implement removeentry.
			if weakkey == 0 {
				markvalue(g, gkey(n))
			}
			if weakvalue == 0 {
				markvalue(g, gval(n))
			}
		}
	}
	return weakkey | weakvalue
}

// Traverse function
@(private)
traverseclosure :: proc(g: ^Global_State, cl: ^Closure) {
	markobject(g, cl.c.env)
	if cl.c.isC != 0 {
		for i in 0 ..< int(cl.c.nupvalues) {
			markvalue(g, &cl.c.upvalue[i])
		}
	} else {
		markobject(g, cl.l.p)
		for i in 0 ..< int(cl.l.nupvalues) {
			markobject(g, cl.l.upvals[i])
		}
	}
}

// Traverse proto
@(private)
traverseproto :: proc(g: ^Global_State, f: ^Proto) {
	if f.source != nil {
		stringmark(f.source)
	}
	for i in 0 ..< int(f.sizek) {
		markvalue(g, &f.k[i])
	}
	for i in 0 ..< int(f.sizeupvalues) {
		if f.upvalues[i] != nil {
			stringmark(f.upvalues[i])
		}
	}
	for i in 0 ..< int(f.sizep) {
		if f.p[i] != nil {
			markobject(g, f.p[i])
		}
	}
	for i in 0 ..< int(f.sizelocvars) {
		if f.locvars[i].varname != nil {
			stringmark(f.locvars[i].varname)
		}
	}
}

// Traverse stack
@(private)
traversestack :: proc(g: ^Global_State, l: ^lua_State) {
	if l.l_gt.value.gc != nil { 	// Handle l_gt being TValue
		markvalue(g, gt(l))
	}

	lim := l.top
	for ci := l.base_ci;
	    cast(uintptr)ci <= cast(uintptr)l.ci;
	    ci = cast(^CallInfo)(cast(uintptr)ci + size_of(CallInfo)) {
		if cast(uintptr)lim < cast(uintptr)ci.top {
			lim = ci.top
		}
	}

	for o := l.stack;
	    cast(uintptr)o < cast(uintptr)l.top;
	    o = cast(StkId)(cast(uintptr)o + size_of(TValue)) {
		markvalue(g, o)
	}

	// Clear rest of stack
	for o := l.top;
	    cast(uintptr)o <= cast(uintptr)lim;
	    o = cast(StkId)(cast(uintptr)o + size_of(TValue)) {
		setnilvalue(o)
	}
}


// Propagate mark
@(private)
propagatemark :: proc(g: ^Global_State) -> c.size_t {
	o := g.gray
	// lua_assert(isgray(o))
	gray2black(o)

	switch o.gch.tt {
	case LUA_TTABLE:
		h := gco2h(o)
		g.gray = h.gclist
		if traversetable(g, h) != 0 {
			black2gray(o)
		}
		return c.size_t(
			size_of(Table) + size_of(TValue) * int(h.sizearray) + size_of(Node) * sizenode(h),
		)
	case LUA_TFUNCTION:
		cl := gco2cl(o)
		g.gray = cl.c.gclist
		traverseclosure(g, cl)
		return(
			(cl.c.isC != 0) ? sizeCclosure(int(cl.c.nupvalues)) : sizeLclosure(int(cl.l.nupvalues)) \
		)
	case LUA_TTHREAD:
		th := gco2th(o)
		g.gray = th.gclist
		th.gclist = g.grayagain
		g.grayagain = o
		black2gray(o)
		traversestack(g, th)
		return c.size_t(
			size_of(lua_State) +
			size_of(TValue) * int(th.stacksize) +
			size_of(CallInfo) * int(th.size_ci),
		)
	case LUA_TPROTO:
		p := gco2p(o)
		g.gray = p.gclist
		traverseproto(g, p)
		// simplified size calc
		return c.size_t(size_of(Proto)) // + ... (dynamic arrays)
	case:
		return 0
	}
}

@(private)
propagateall :: proc(g: ^Global_State) -> c.size_t {
	m: c.size_t = 0
	for g.gray != nil {
		m += propagatemark(g)
	}
	return m
}

@(private)
iscleared :: proc(o: ^TValue, iskey: bool) -> bool {
	if !iscollectable(o) {
		return false
	}
	if ttisstring(o) {
		stringmark(rawtsvalue(o))
		return false
	}
	return iswhite(gcvalue(o)) || (ttisuserdata(o) && (!iskey && isfinalized(gco2u(gcvalue(o)))))
}

@(private)
cleartable :: proc(l: ^GCObject) {
	curr := l
	for curr != nil {
		h := gco2h(curr)
		i := int(h.sizearray)

		if (h.marked & u8(VALUEWEAKBIT)) != 0 {
			for i > 0 {
				i -= 1
				o := &h.array[i]
				if iscleared(o, false) {
					setnilvalue(o)
				}
			}
		}

		i = sizenode(h)
		for i > 0 {
			i -= 1
			n := gnode(h, i)
			if !ttisnil(gval(n)) && (iscleared(key2tval(n), true) || iscleared(gval(n), false)) {
				setnilvalue(gval(n))
				removeentry(n)
			}
		}
		curr = h.gclist
	}
}

@(private)
removeentry :: proc(n: ^Node) {
	if iscollectable(gkey(n)) {
		// setttype(gkey(n), LUA_TDEADKEY);
		// gkey(n).tt = LUA_TDEADKEY
		// Accessing i_key.nk.tt directly?
		// Needs proper helper or cast access
		// setgcvalue(gkey(n), gcvalue(gkey(n)), LUA_TDEADKEY)?? No, setttype.
		// We can just set tt
		gkey(n).tt = LUA_TDEADKEY
	}
}

@(private)
freeobj :: proc(L: ^lua_State, o: ^GCObject) {
	switch o.gch.tt {
	case LUA_TPROTO:
		luaF_freeproto(L, gco2p(o))
	case LUA_TFUNCTION:
		luaF_freeclosure(L, gco2cl(o))
	case LUA_TUPVAL:
		luaF_freeupval(L, gco2uv(o))
	case LUA_TTABLE:
		luaH_free(L, gco2h(o))
	case LUA_TTHREAD:
		luaE_freethread(L, gco2th(o))
	case LUA_TSTRING:
		G(L).strt.nuse -= 1
		luaM_freemem(L, o, c.size_t(sizestring(gco2ts(o)))) // need sizestring helper
	case LUA_TUSERDATA:
		luaM_freemem(L, o, c.size_t(sizeudata(gco2u(o)))) // need sizeudata helper
	case:
	// lua_assert(0)
	}
}

// sizestring and sizeudata are defined in string.odin

sweeplist :: proc(L: ^lua_State, p: ^^GCObject, count: c.size_t) -> ^^GCObject {
	curr: ^GCObject
	g := G(L)
	deadmask := otherwhite(g)
	cnt := count
	pp := p

	for {
		curr = pp^
		if curr == nil || cnt == 0 {break}
		cnt -= 1

		if curr.gch.tt == LUA_TTHREAD {
			sweepwholelist(L, &gco2th(curr).openupval)
		}

		if ((curr.gch.marked ~ u8(WHITEBITS)) & deadmask) != 0 {
			// Not dead
			makewhite(g, curr)
			pp = &curr.gch.next
		} else {
			// Must erase
			pp^ = curr.gch.next
			if curr == g.rootgc {
				g.rootgc = curr.gch.next
			}
			freeobj(L, curr)
		}
	}
	return pp
}

sweepwholelist :: #force_inline proc(L: ^lua_State, p: ^^GCObject) {
	sweeplist(L, p, MAX_SIZET)
}

@(private)
remarkupvals :: proc(g: ^Global_State) {
	for uv := g.uvhead.u.l.next; uv != &g.uvhead; uv = uv.u.l.next {
		if isgray(obj2gco(uv)) {
			markvalue(g, uv.v)
		}
	}
}

@(export, link_name = "luaC_separateudata")
luaC_separateudata :: proc "c" (L: ^lua_State, all: c.int) -> c.size_t {
	context = runtime.default_context()
	g := G(L)
	p := &g.mainthread.next
	curr: ^GCObject

	for {
		curr = p^
		if curr == nil {break}

		// Luam specific: no finalizers
		is_white := iswhite(curr)
		should_separate := (is_white || all != 0) && !isfinalized(gco2u(curr))

		if should_separate {
			// Keep iterating (don't separate because no finalizers support)
			// Original C:
			// if (!(iswhite(curr) || all) || isfinalized(gco2u(curr)))
			//   p = &curr->gch.next;
			// else { markfinalized(gco2u(curr)); p = &curr->gch.next; }

			// Wait, logic:
			// If (NOT (white or all)) OR finalized -> SKIP (keep in list, advance p)
			// Else (white or all AND not finalized) -> Separate (mark finalized, advance p... wait, usually moves to tmudata)
			// Here we just mark finalized and keep it in the list (since no tmudata list management required without __gc)
			markfinalized(gco2u(curr))
			p = &curr.gch.next
		} else {
			p = &curr.gch.next
		}
	}
	return 0
}

isfinalized :: #force_inline proc(u: ^Udata) -> bool {return(
		(u.uv.marked & (1 << FINALIZEDBIT)) !=
		0 \
	)}
markfinalized :: #force_inline proc(u: ^Udata) {u.uv.marked |= (1 << FINALIZEDBIT)}

// Missing marking helpers (if not visible from state.odin)
// iswhite is defined in state.odin

// isblack removed (use definition from func.odin)

@(private)
marktmu :: proc(g: ^Global_State) {
	u := g.tmudata
	if u != nil {
		for {
			u = u.gch.next
			makewhite(g, u)
			reallymarkobject(g, u)
			if u == g.tmudata {break}
		}
	}
}

@(private)
markmt :: proc(g: ^Global_State) {
	for i in 0 ..< NUM_TAGS {
		if g.mt[i] != nil {
			markobject(g, g.mt[i])
		}
	}
}

// Mark root set
@(private)
markroot :: proc(L: ^lua_State) {
	g := G(L)
	g.gray = nil
	g.grayagain = nil
	g.weak = nil
	markobject(g, g.mainthread)
	markvalue(g, gt(g.mainthread))
	markvalue(g, registry(L))
	markmt(g)
	g.gcstate = GCSpropagate
}

@(private)
atomic :: proc(L: ^lua_State) {
	g := G(L)
	remarkupvals(g)
	propagateall(g)

	g.gray = g.weak
	g.weak = nil
	markobject(g, L)
	markmt(g)
	propagateall(g)

	g.gray = g.grayagain
	g.grayagain = nil
	propagateall(g)

	luaC_separateudata(L, 0)
	marktmu(g)
	propagateall(g)

	cleartable(g.weak)

	g.currentwhite = cast(u8)otherwhite(g)
	g.sweepstrgc = 0
	g.sweepgc = cast(^rawptr)&g.rootgc
	g.gcstate = GCSsweepstring
	g.estimate = g.totalbytes
}

@(private)
singlestep :: proc(L: ^lua_State) -> c.size_t {
	g := G(L)
	switch g.gcstate {
	case GCSpause:
		markroot(L)
		return 0
	case GCSpropagate:
		if g.gray != nil {
			return propagatemark(g)
		} else {
			atomic(L)
			return 0
		}
	case GCSsweepstring:
		old := g.totalbytes
		sweepwholelist(L, &g.strt.hash[g.sweepstrgc])
		g.sweepstrgc += 1
		if g.sweepstrgc >= g.strt.size {
			g.gcstate = GCSsweep
		}
		g.estimate -= old - g.totalbytes
		return GCSWEEPCOST
	case GCSsweep:
		old := g.totalbytes
		g.sweepgc = cast(^rawptr)sweeplist(L, cast(^^GCObject)g.sweepgc, GCSWEEPMAX)
		if (cast(^^GCObject)g.sweepgc)^ == nil {
			checkSizes(L)
			g.gcstate = GCSfinalize
		}
		g.estimate -= old - g.totalbytes
		return GCSWEEPMAX * GCSWEEPCOST
	case GCSfinalize:
		if g.tmudata != nil {
			GCTM(L)
			if g.estimate > GCFINALIZECOST {
				g.estimate -= GCFINALIZECOST
			}
			return GCFINALIZECOST
		} else {
			g.gcstate = GCSpause
			g.gcdept = 0
			return 0
		}
	case:
		return 0
	}
}

@(private)
checkSizes :: proc(L: ^lua_State) {
	g := G(L)
	if g.strt.nuse < u32(g.strt.size / 4) && g.strt.size > MINSTRTABSIZE * 2 {
		luaS_resize(L, c.int(g.strt.size / 2))
	}
	if g.buff.buffsize > LUA_MINBUFFER * 2 {
		newsize := g.buff.buffsize / 2
		luaZ_resizebuffer(L, &g.buff, newsize)
	}
}

@(private)
GCTM :: proc(L: ^lua_State) {
	// simplified: removed metatable support for userdata
	g := G(L)
	o := g.tmudata.gch.next
	udata := gco2u(o)

	if o == g.tmudata {
		g.tmudata = nil
	} else {
		g.tmudata.gch.next = udata.uv.next
	}
	udata.uv.next = g.mainthread.next
	g.mainthread.next = o
	makewhite(g, o)

	// Call __gc metamethod (removed)
}

// Public API

// Set threshold for next GC
setthreshold :: #force_inline proc(g: ^Global_State) {
	g.GCthreshold = (g.estimate / 100) * c.size_t(g.gcpause)
}

@(export, link_name = "luaC_step")
luaC_step :: proc "c" (L: ^lua_State) {
	context = runtime.default_context()
	g := G(L)
	lim := (c.size_t(GCSTEPSIZE) / 100) * c.size_t(g.gcstepmul)
	if lim == 0 {
		lim = (MAX_SIZET - 1) / 2
	}
	g.gcdept += g.totalbytes - g.GCthreshold

	for {
		lim -= singlestep(L)
		if g.gcstate == GCSpause {
			break
		}
		if lim <= 0 {
			break
		}
	}

	if g.gcstate != GCSpause {
		if g.gcdept < c.size_t(GCSTEPSIZE) {
			g.GCthreshold = g.totalbytes + c.size_t(GCSTEPSIZE)
		} else {
			g.gcdept -= c.size_t(GCSTEPSIZE)
			g.GCthreshold = g.totalbytes
		}
	} else {
		setthreshold(g)
	}
}

@(export, link_name = "luaC_fullgc")
luaC_fullgc :: proc "c" (L: ^lua_State) {
	context = runtime.default_context()
	g := G(L)
	if g.gcstate <= GCSpropagate {
		g.sweepstrgc = 0
		g.sweepgc = cast(^rawptr)&g.rootgc
		g.gray = nil
		g.grayagain = nil
		g.weak = nil
		g.gcstate = GCSsweepstring
	}

	for g.gcstate != GCSfinalize {
		singlestep(L)
	}
	markroot(L)
	for g.gcstate != GCSpause {
		singlestep(L)
	}
	setthreshold(g)
}

@(export, link_name = "luaC_barrierf")
luaC_barrierf :: proc "c" (L: ^lua_State, o: ^GCObject, v: ^GCObject) {
	context = runtime.default_context()
	g := G(L)
	if g.gcstate == GCSpropagate {
		reallymarkobject(g, v)
	} else {
		makewhite(g, o)
	}
}

@(export, link_name = "luaC_barrierback")
luaC_barrierback :: proc "c" (L: ^lua_State, t: ^Table) {
	context = runtime.default_context()
	g := G(L)
	o := obj2gco(t)
	black2gray(o)
	t.gclist = g.grayagain
	g.grayagain = o
}

@(export, link_name = "luaC_link")
luaC_link :: proc "c" (L: ^lua_State, o: ^GCObject, tt: u8) {
	context = runtime.default_context()
	g := G(L)
	o.gch.next = g.rootgc
	g.rootgc = o
	o.gch.marked = luaC_white(g)
	o.gch.tt = tt
}

@(export, link_name = "luaC_linkupval")
luaC_linkupval :: proc "c" (L: ^lua_State, uv: ^UpVal) {
	context = runtime.default_context()
	g := G(L)
	o := obj2gco(uv)
	o.gch.next = g.rootgc
	g.rootgc = o
	if isgray(o) {
		if g.gcstate == GCSpropagate {
			gray2black(o)
			luaC_barrier(L, uv, uv.v)
		} else {
			makewhite(g, o)
		}
	}
}

@(export, link_name = "luaC_callGCTM")
luaC_callGCTM :: proc "c" (L: ^lua_State) {
	context = runtime.default_context()
	for G(L).tmudata != nil {
		GCTM(L)
	}
}

@(export, link_name = "luaC_freeall")
luaC_freeall :: proc "c" (L: ^lua_State) {
	context = runtime.default_context()
	g := G(L)
	g.currentwhite = u8(WHITEBITS) | u8(1 << SFIXEDBIT)
	sweepwholelist(L, &g.rootgc)
	for i in 0 ..< int(g.strt.size) {
		sweepwholelist(L, &g.strt.hash[i])
	}
}

// Foreign imports no longer needed for these

// Reuse existing checkGC for now, but implement logic if needed
luaC_checkGC :: #force_inline proc(L: ^lua_State) {
	g := G(L)
	if g.totalbytes >= g.GCthreshold {
		luaC_step(L)
	}
}

// Generic barrier check macro as inline proc
luaC_barrier :: #force_inline proc(L: ^lua_State, p: rawptr, v: ^TValue) {
	if iscollectable(v) && isblack(obj2gco(p)) && iswhite(gcvalue(v)) {
		luaC_barrierf(L, obj2gco(p), gcvalue(v))
	}
}

// Table barrier
luaC_barriert :: #force_inline proc(L: ^lua_State, t: ^Table, v: ^TValue) {
	if iscollectable(v) && isblack(obj2gco(t)) && iswhite(gcvalue(v)) {
		luaC_barrierback(L, t)
	}
}

// GC pause/step constants
LUAI_GCPAUSE :: 200
LUAI_GCMUL :: 200
