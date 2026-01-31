// Global State - type definitions
// Migrated from lstate.c/h
// Note: Functions remain in C until remaining dependencies are migrated
package core

import "core:c"

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
