// Global State - type definitions
// Migrated from lstate.c/h
// Note: Functions remain in C until remaining dependencies are migrated
package core

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:mem"

// Extra stack space for TM calls
EXTRA_STACK :: 5

// Basic sizes
BASIC_CI_SIZE :: 8
BASIC_STACK_SIZE :: 2 * LUA_MINSTACK
LUA_MINSTACK :: 20

// Minimum string table size
MINSTRTABSIZE :: 32

// String table for string interning
Stringtable :: struct {
	hash: [^]^GCObject,
	nuse: u32, // number of elements
	size: c.int,
}

// Information about a call
CallInfo :: struct {
	base:      StkId, // base for this function
	func:      StkId, // function index in the stack
	top:       StkId, // top for this function
	savedpc:   [^]Instruction, // saved program counter
	nresults:  c.int, // expected number of results
	tailcalls: c.int, // number of tail calls lost
}

// Tag method enum (from ltm.h)
TM :: enum {
	TM_INDEX,
	TM_NEWINDEX,
	TM_GC,
	TM_MODE,
	TM_EQ, // last tag method with `fast' access
	TM_ADD,
	TM_SUB,
	TM_MUL,
	TM_DIV,
	TM_MOD,
	TM_POW,
	TM_UNM,
	TM_LEN,
	TM_LT,
	TM_LE,
	TM_CONCAT,
	TM_CALL,
	TM_N, // number of elements
}

// GC states
GCSpause :: 0
GCSpropagate :: 1
GCSsweepstring :: 2
GCSsweep :: 3
GCSfinalize :: 4

// GC color bits
WHITE0BIT :: 0
WHITE1BIT :: 1
BLACKBIT :: 2
FINALIZEDBIT :: 3
FIXEDBIT :: 5
SFIXEDBIT :: 6

// Hook function type
Hook :: #type proc "c" (L: ^lua_State, ar: rawptr)

// Forward declaration for error jump
lua_longjmp :: struct {} // defined in ldo.c

// Global state, shared by all threads
Global_State :: struct {
	strt:         Stringtable, // hash table for strings
	frealloc:     Alloc, // memory allocator function
	ud:           rawptr, // user data for allocator
	currentwhite: u8,
	gcstate:      u8, // state of garbage collector
	sweepstrgc:   c.int, // position of sweep in `strt'
	rootgc:       ^GCObject, // list of all collectable objects
	sweepgc:      ^rawptr, // position of sweep in `rootgc'
	gray:         ^GCObject, // list of gray objects
	grayagain:    ^GCObject, // list of objects to be traversed atomically
	weak:         ^GCObject, // list of weak tables (to be cleared)
	tmudata:      ^GCObject, // last element of list of userdata to be GC
	buff:         Mbuffer, // temporary buffer for string concatenation
	GCthreshold:  c.size_t,
	totalbytes:   c.size_t, // number of bytes currently allocated
	estimate:     c.size_t, // estimate of bytes actually in use
	gcdept:       c.size_t, // how much GC is `behind schedule'
	gcpause:      c.int, // size of pause between successive GCs
	gcstepmul:    c.int, // GC `granularity'
	panic:        CFunction, // to be called in unprotected errors
	l_registry:   TValue,
	mainthread:   ^lua_State,
	uvhead:       UpVal, // head of double-linked list of all open upvalues
	mt:           [NUM_TAGS]^Table, // metatables for basic types
	tmname:       [TM.TM_N]^TString, // array with tag-method names
}

// Per-thread state
lua_State :: struct {
	// GC header
	next:          ^GCObject,
	tt:            u8,
	marked:        u8,
	// lua_State-specific
	status:        u8,
	top:           StkId, // first free slot in the stack
	base:          StkId, // base of current function
	l_G:           ^Global_State,
	ci:            ^CallInfo, // call info for current function
	savedpc:       [^]Instruction, // `savedpc' of current function
	stack_last:    StkId, // last free slot in the stack
	stack:         StkId, // stack base
	end_ci:        ^CallInfo, // points after end of ci array
	base_ci:       ^CallInfo, // array of CallInfo's
	stacksize:     c.int,
	size_ci:       c.int, // size of array `base_ci'
	nCcalls:       u16, // number of nested C calls
	baseCcalls:    u16, // nested C calls when resuming coroutine
	hookmask:      u8,
	allowhook:     u8,
	basehookcount: c.int,
	hookcount:     c.int,
	hook:          Hook,
	l_gt:          TValue, // table of globals
	env:           TValue, // temporary place for environments
	openupval:     ^GCObject, // list of open upvalues in this stack
	gclist:        ^GCObject,
	errorJmp:      ^lua_longjmp, // current error recover point
	errfunc:       c.ptrdiff_t, // current error handling function (stack index)
}

// Get global state from lua_State
G :: #force_inline proc(L: ^lua_State) -> ^Global_State {
	return L.l_G
}

// Get table of globals
gt :: #force_inline proc(L: ^lua_State) -> ^TValue {
	return &L.l_gt
}

// Get registry
registry :: #force_inline proc(L: ^lua_State) -> ^TValue {
	return &G(L).l_registry
}

// CallInfo helpers
curr_func :: #force_inline proc(L: ^lua_State) -> ^Closure {
	return cast(^Closure)L.ci.func.value.gc
}

ci_func :: #force_inline proc(ci: ^CallInfo) -> ^Closure {
	return cast(^Closure)ci.func.value.gc
}

f_isLua :: #force_inline proc(ci: ^CallInfo) -> bool {
	cl := ci_func(ci)
	return cl.c.isC == 0
}

isLua :: #force_inline proc(ci: ^CallInfo) -> bool {
	return ttisfunction(ci.func) && f_isLua(ci)
}

// GCObject conversion helpers
rawgco2ts :: #force_inline proc(o: ^GCObject) -> ^TString {
	return &o.ts
}

gco2ts :: #force_inline proc(o: ^GCObject) -> ^TString {
	return rawgco2ts(o)
}

gco2h :: #force_inline proc(o: ^GCObject) -> ^Table {
	return &o.h
}

gco2cl :: #force_inline proc(o: ^GCObject) -> ^Closure {
	return &o.cl
}

gco2uv :: #force_inline proc(o: ^GCObject) -> ^UpVal {
	return &o.uv
}

gco2th :: #force_inline proc(o: ^GCObject) -> ^lua_State {
	return cast(^lua_State)o
}

obj2gco :: #force_inline proc(v: rawptr) -> ^GCObject {
	return cast(^GCObject)v
}

gco2p :: #force_inline proc(o: ^GCObject) -> ^Proto {
	return &o.p
}

gco2u :: #force_inline proc(o: ^GCObject) -> ^Udata {
	return &o.u
}

// GC marking helpers
luaC_white :: #force_inline proc(g: ^Global_State) -> u8 {
	return g.currentwhite & 3
}

iswhite :: #force_inline proc(x: ^GCObject) -> bool {
	return (x.gch.marked & 3) != 0
}

isdead :: #force_inline proc(g: ^Global_State, v: ^GCObject) -> bool {
	return (v.gch.marked & otherwhite(g) & WHITEBITS) != 0
}

// Bit manipulation helpers
bit2mask :: #force_inline proc(b1: u8, b2: u8) -> u8 {
	return (1 << b1) | (1 << b2)
}

set2bits :: #force_inline proc(x: ^u8, b1: u8, b2: u8) {
	x^ |= bit2mask(b1, b2)
}

// Macros for state size
state_size :: #force_inline proc(x: int) -> int {
	return x + size_of(LUA_EXTRASPACE)
}

fromstate :: #force_inline proc(l: ^lua_State) -> rawptr {
	return cast(rawptr)(cast(uintptr)l - size_of(LUA_EXTRASPACE))
}

tostate :: #force_inline proc(l: rawptr) -> ^lua_State {
	return cast(^lua_State)(cast(uintptr)l + size_of(LUA_EXTRASPACE))
}

LG :: struct {
	l: lua_State,
	g: Global_State,
}

// LUA_EXTRASPACE (defined as empty in luaconf.h equivalent, but for alignment/C compat we often ignore it or define it as [0]u8)
// Check luaconf.h. Defaults to empty.
LUA_EXTRASPACE :: [0]u8{}

// luaC_freeall and luaC_callGCTM foreign imports removed (implemented in gc.odin)

// Stack initialization
@(private)
stack_init :: proc(L1: ^lua_State, L: ^lua_State) {
	// Initialize CallInfo array
	L1.base_ci = cast(^CallInfo)luaM_malloc(L, c.size_t(BASIC_CI_SIZE * size_of(CallInfo)))
	L1.ci = L1.base_ci
	L1.size_ci = BASIC_CI_SIZE
	L1.end_ci = cast(^CallInfo)mem.ptr_offset(L1.base_ci, L1.size_ci - 1)

	// Initialize stack array
	size := BASIC_STACK_SIZE + EXTRA_STACK
	L1.stack = cast(StkId)luaM_malloc(L, c.size_t(size * size_of(TValue)))
	L1.stacksize = c.int(size)
	L1.top = L1.stack
	L1.stack_last = cast(StkId)mem.ptr_offset(L1.stack, size - EXTRA_STACK - 1)

	// Initialize first ci
	L1.ci.func = L1.top
	setnilvalue(L1.top)
	L1.top = cast(StkId)mem.ptr_offset(L1.top, 1)
	L1.base = L1.top
	L1.ci.base = L1.base
	L1.ci.top = cast(StkId)mem.ptr_offset(L1.top, LUA_MINSTACK)
}

@(private)
freestack :: proc(L: ^lua_State, L1: ^lua_State) {
	luaM_freemem(L, L1.base_ci, c.size_t(L1.size_ci) * size_of(CallInfo))
	luaM_freemem(L, L1.stack, c.size_t(L1.stacksize) * size_of(TValue))
}

// f_luaopen
f_luaopen :: proc "c" (L: ^lua_State, ud: rawptr) {
	context = runtime.default_context()
	g := G(L)
	stack_init(L, L)
	sethvalue(L, gt(L), luaH_new(L, 0, 2)) // table of globals
	sethvalue(L, registry(L), luaH_new(L, 0, 2)) // registry
	luaS_resize(L, MINSTRTABSIZE)
	luaT_init(L)
	// luaX_init(L) // Lexer init?? llex.c check.
	// luaS_fix(luaS_newliteral(L, MEMERRMSG)) // MEMERRMSG "not enough memory"
	// For now, defer X_init and MEMERRMSG.
	// Check if luaX_init is strictly needed for non-parser states?
	// It initialized reserved words.
	// We might need to import luaX_init or reimplement it.
	// But llex.c is C.
	// Import it.
	fmt.printf(
		"DEBUG: Odin size_of(TValue)=%d, align_of(TValue)=%d\n",
		size_of(TValue),
		align_of(TValue),
	)
	fmt.printf(
		"DEBUG: Odin size_of(Table)=%d, align_of(Table)=%d\n",
		size_of(Table),
		align_of(Table),
	)
	luaX_init_unique_c(L)

	s := luaS_new(L, "not enough memory")
	luaS_fix(s)

	g.GCthreshold = 4 * g.totalbytes
}

// Foreign import for Lexer (still in C)
foreign import lua_core "../../obj/liblua.a"

foreign lua_core {
	@(link_name = "luaX_init_unique")
	luaX_init_unique_c :: proc(L: ^lua_State) ---
}

@(private)
preinit_state :: proc(L: ^lua_State, g: ^Global_State) {
	L.l_G = g
	L.stack = nil
	L.stacksize = 0
	L.errorJmp = nil
	L.hook = nil
	L.hookmask = 0
	L.basehookcount = 0
	L.allowhook = 1
	// resethookcount(L) // Defined in debug.odin
	resethookcount(L)
	L.openupval = nil
	L.size_ci = 0
	L.nCcalls = 0
	L.baseCcalls = 0
	L.status = 0
	L.base_ci = nil
	L.ci = nil
	L.savedpc = nil
	L.errfunc = 0
	setnilvalue(gt(L))
}

// resethookcount is in debug.odin

@(private)
close_state :: proc(L: ^lua_State) {
	g := G(L)
	luaF_close(L, L.stack)
	luaF_close(L, L.stack)
	luaC_freeall(L)
	// lua_assert(g.rootgc == obj2gco(L))
	// lua_assert(g.strt.nuse == 0)
	luaM_freemem(L, g.strt.hash, c.size_t(g.strt.size) * size_of(^GCObject))
	luaZ_freebuffer(L, &g.buff)
	freestack(L, L)
	// lua_assert(g.totalbytes == size_of(LG))
	g.frealloc(g.ud, fromstate(L), c.size_t(state_size(size_of(LG))), 0)
}

@(export, link_name = "luaE_newthread")
luaE_newthread :: proc "c" (L: ^lua_State) -> ^lua_State {
	context = runtime.default_context()
	L1 := tostate(luaM_malloc(L, c.size_t(state_size(size_of(lua_State)))))
	luaC_link(L, obj2gco(L1), LUA_TTHREAD)
	preinit_state(L1, G(L))
	stack_init(L1, L)
	setobj(gt(L1), gt(L))
	L1.hookmask = L.hookmask
	L1.basehookcount = L.basehookcount
	L1.hook = L.hook
	resethookcount(L1)
	return L1
}

@(export, link_name = "luaE_freethread")
luaE_freethread :: proc "c" (L: ^lua_State, L1: ^lua_State) {
	context = runtime.default_context()
	luaF_close(L1, L1.stack)
	// luai_userstatefree(L1) // Macro, often empty
	freestack(L, L1)
	luaM_freemem(L, fromstate(L1), c.size_t(state_size(size_of(lua_State))))
}

@(export, link_name = "lua_newstate")
lua_newstate :: proc "c" (f: Alloc, ud: rawptr) -> ^lua_State {
	context = runtime.default_context()
	l := f(ud, nil, 0, c.size_t(state_size(size_of(LG))))
	if l == nil {
		return nil
	}
	L := tostate(l)
	g := &(cast(^LG)L).g

	L.next = nil
	L.tt = LUA_TTHREAD
	g.currentwhite = bit2mask(WHITE0BIT, FIXEDBIT)
	L.marked = luaC_white(g)
	set2bits(&L.marked, FIXEDBIT, SFIXEDBIT)
	preinit_state(L, g)
	g.frealloc = f
	g.ud = ud
	g.mainthread = L
	g.uvhead.u.l.prev = &g.uvhead
	g.uvhead.u.l.next = &g.uvhead
	g.GCthreshold = 0
	g.strt.size = 0
	g.strt.nuse = 0
	g.strt.hash = nil
	setnilvalue(registry(L))
	initbuffer(&g.buff)
	g.panic = nil
	g.gcstate = GCSpause
	g.rootgc = obj2gco(L)
	g.sweepstrgc = 0
	g.sweepgc = cast(^rawptr)&g.rootgc
	g.gray = nil
	g.grayagain = nil
	g.weak = nil
	g.tmudata = nil
	g.totalbytes = c.size_t(size_of(LG))
	g.gcpause = LUAI_GCPAUSE
	g.gcstepmul = LUAI_GCMUL
	g.gcdept = 0
	for i in 0 ..< NUM_TAGS {
		g.mt[i] = nil
	}

	if luaD_rawrunprotected_c(L, f_luaopen, nil) != 0 {
		close_state(L) // Should be close_state(L) or lua_close(L)? C uses close_state.
		return nil
	}

	// luai_userstateopen(L)
	return L
}

callallgcTM :: proc "c" (L: ^lua_State, ud: rawptr) {
	context = runtime.default_context()
	luaC_callGCTM(L)
}

@(export, link_name = "lua_close")
lua_close :: proc "c" (L: ^lua_State) {
	context = runtime.default_context()
	L1 := G(L).mainthread
	// lua_lock(L1)
	luaF_close(L1, L1.stack)
	luaF_close(L1, L1.stack)
	luaC_separateudata(L1, 1) // 1 = all
	L1.errfunc = 0
	L1.errfunc = 0

	for {
		L1.ci = L1.base_ci
		L1.base = L1.ci.base
		L1.top = L1.base
		L1.nCcalls = 0
		L1.baseCcalls = 0
		if luaD_rawrunprotected_c(L1, callallgcTM, nil) == 0 {
			break
		}
	}

	// luai_userstateclose(L1)
	close_state(L1)
}

// luaC_separateudata_c removed (implemented in gc.odin)
