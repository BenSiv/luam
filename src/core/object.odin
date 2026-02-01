// Type definitions for Lua objects
// Migrated from lobject.c/h
package core

import "core:c"
import "core:mem"

// Lua type tags (from lua.h)
LUA_TNIL :: 0
LUA_TBOOLEAN :: 1
LUA_TLIGHTUSERDATA :: 2
LUA_TNUMBER :: 3
LUA_TSTRING :: 4
LUA_TTABLE :: 5
LUA_TFUNCTION :: 6
LUA_TUSERDATA :: 7
LUA_TTHREAD :: 8

// Tags for visible types
LAST_TAG :: LUA_TTHREAD
NUM_TAGS :: LAST_TAG + 1

// Extra tags for non-values
LUA_TPROTO :: LAST_TAG + 1
LUA_TUPVAL :: LAST_TAG + 2
LUA_TDEADKEY :: LAST_TAG + 3

// lua_Number type (typically f64)
lua_Number :: f64

// Forward declarations for recursive types
GCObject :: struct #raw_union {
	gch: GCheader,
	ts:  TString,
	u:   Udata,
	cl:  Closure,
	h:   Table,
	p:   Proto,
	uv:  UpVal,
	th:  rawptr, // lua_State - will be defined in lstate
}

// Common Header for all collectable GC objects
GCheader :: struct {
	next:   ^GCObject,
	tt:     u8,
	marked: u8,
}

// Union of all Lua values
Value :: struct #raw_union {
	gc: ^GCObject,
	p:  rawptr,
	n:  lua_Number,
	b:  c.int,
}

// Tagged Value - the fundamental Lua value type
TValue :: struct {
	value: Value,
	tt:    c.int,
}

// Stack index type
StkId :: ^TValue

// Type checking macros as inline procs
ttisnil :: #force_inline proc(o: ^TValue) -> bool {return o.tt == LUA_TNIL}
ttisnumber :: #force_inline proc(o: ^TValue) -> bool {return o.tt == LUA_TNUMBER}
ttisstring :: #force_inline proc(o: ^TValue) -> bool {return o.tt == LUA_TSTRING}
ttistable :: #force_inline proc(o: ^TValue) -> bool {return o.tt == LUA_TTABLE}
ttisfunction :: #force_inline proc(o: ^TValue) -> bool {return o.tt == LUA_TFUNCTION}
ttisboolean :: #force_inline proc(o: ^TValue) -> bool {return o.tt == LUA_TBOOLEAN}
ttisuserdata :: #force_inline proc(o: ^TValue) -> bool {return o.tt == LUA_TUSERDATA}
ttisthread :: #force_inline proc(o: ^TValue) -> bool {return o.tt == LUA_TTHREAD}
ttislightuserdata :: #force_inline proc(o: ^TValue) -> bool {return o.tt == LUA_TLIGHTUSERDATA}

// Value accessors
ttype :: #force_inline proc(o: ^TValue) -> c.int {
	return o.tt
}
gcvalue :: #force_inline proc(o: ^TValue) -> ^GCObject {return o.value.gc}
pvalue :: #force_inline proc(o: ^TValue) -> rawptr {return o.value.p}
nvalue :: #force_inline proc(o: ^TValue) -> lua_Number {return o.value.n}
bvalue :: #force_inline proc(o: ^TValue) -> c.int {return o.value.b}

iscollectable :: #force_inline proc(o: ^TValue) -> bool {return o.tt >= LUA_TSTRING}

l_isfalse :: #force_inline proc(o: ^TValue) -> bool {
	return ttisnil(o) || (ttisboolean(o) && bvalue(o) == 0)
}

// Value setters
setnilvalue :: #force_inline proc(obj: ^TValue) {
	obj.tt = LUA_TNIL
}

foreign import lua_core "../../obj/liblua.a"

foreign lua_core {
	@(link_name = "luaO_nilobject_")
	nilobject_: TValue
}

nilobject := &nilobject_

setnvalue :: #force_inline proc(obj: ^TValue, x: lua_Number) {
	obj.value.n = x
	obj.tt = LUA_TNUMBER
}

setpvalue :: #force_inline proc(obj: ^TValue, x: rawptr) {
	obj.value.p = x
	obj.tt = LUA_TLIGHTUSERDATA
}

setbvalue :: #force_inline proc(obj: ^TValue, x: c.int) {
	obj.value.b = x
	obj.tt = LUA_TBOOLEAN
}

setgcvalue :: #force_inline proc(obj: ^TValue, x: ^GCObject, tag: c.int) {
	obj.value.gc = x
	obj.tt = tag
}

// Copy TValue
setobj :: #force_inline proc(obj1: ^TValue, obj2: ^TValue) {
	obj1.value = obj2.value
	obj1.tt = obj2.tt
}

// String header
TString :: struct #raw_union {
	dummy: max_align_t, // ensures maximum alignment
	tsv:   struct {
		next:     ^GCObject,
		tt:       u8,
		marked:   u8,
		reserved: u8,
		hash:     c.uint,
		len:      c.size_t,
	},
}

// Maximum alignment type
max_align_t :: struct {
	_:  f64,
	__: rawptr,
}

// Get string data (stored after the TString header)
getstr :: #force_inline proc(ts: ^TString) -> cstring {
	return cast(cstring)(cast(rawptr)(cast(uintptr)ts + size_of(TString)))
}

// Userdata header
Udata :: struct #raw_union {
	dummy: max_align_t,
	uv:    struct {
		next:      ^GCObject,
		tt:        u8,
		marked:    u8,
		metatable: ^Table,
		env:       ^Table,
		len:       c.size_t,
	},
}

// Local variable info
LocVar :: struct {
	varname:  ^TString,
	startpc:  c.int,
	endpc:    c.int,
	is_const: u8,
}

// Function prototype
Proto :: struct {
	// GC header
	next:            ^GCObject,
	tt:              u8,
	marked:          u8,
	// Proto-specific fields
	k:               [^]TValue, // constants
	code:            [^]Instruction, // bytecode
	p:               [^]^Proto, // nested protos
	lineinfo:        [^]c.int, // source line mapping
	locvars:         [^]LocVar, // local variable info
	upvalues:        [^]^TString, // upvalue names
	source:          ^TString,
	sizeupvalues:    c.int,
	sizek:           c.int,
	sizecode:        c.int,
	sizelineinfo:    c.int,
	sizep:           c.int,
	sizelocvars:     c.int,
	linedefined:     c.int,
	lastlinedefined: c.int,
	gclist:          ^GCObject,
	nups:            u8,
	numparams:       u8,
	is_vararg:       u8,
	maxstacksize:    u8,
}

// Vararg masks
VARARG_HASARG :: 1
VARARG_ISVARARG :: 2
VARARG_NEEDSARG :: 4

// Upvalue
UpVal :: struct {
	// GC header
	next:   ^GCObject,
	tt:     u8,
	marked: u8,
	// UpVal-specific
	v:      ^TValue, // points to stack or to own value
	u:      struct #raw_union {
		value: TValue, // the value (when closed)
		l:     struct {
			// linked list (when open)
			prev: ^UpVal,
			next: ^UpVal,
		},
	},
}

// C Closure
CClosure :: struct {
	// GC header + closure header
	next:      ^GCObject,
	tt:        u8,
	marked:    u8,
	isC:       u8,
	nupvalues: u8,
	gclist:    ^GCObject,
	env:       ^Table,
	// CClosure-specific
	f:         CFunction,
	upvalue:   [1]TValue,
}

// Lua Closure
LClosure :: struct {
	// GC header + closure header
	next:      ^GCObject,
	tt:        u8,
	marked:    u8,
	isC:       u8,
	nupvalues: u8,
	gclist:    ^GCObject,
	env:       ^Table,
	// LClosure-specific
	p:         ^Proto,
	upvals:    [1]^UpVal,
}

// Closure union
Closure :: struct #raw_union {
	c: CClosure,
	l: LClosure,
}

// C function type
CFunction :: #type proc "c" (L: rawptr) -> c.int

iscfunction :: #force_inline proc(o: ^TValue) -> bool {
	if o.tt != LUA_TFUNCTION do return false
	cl := cast(^Closure)o.value.gc
	return cl.c.isC != 0
}

isLfunction :: #force_inline proc(o: ^TValue) -> bool {
	if o.tt != LUA_TFUNCTION do return false
	cl := cast(^Closure)o.value.gc
	return cl.c.isC == 0
}

// Table key - union for hash chaining
TKey :: struct #raw_union {
	nk:  struct {
		value: Value,
		tt:    c.int,
		next:  ^Node,
	},
	tvk: TValue,
}

// Hash table node
Node :: struct {
	i_val: TValue,
	i_key: TKey,
}

// Table (hash + array)
Table :: struct {
	// GC header
	next:      ^GCObject,
	tt:        u8,
	marked:    u8,
	// Table-specific
	flags:     u8, // 1<<p means tagmethod(p) is not present
	lsizenode: u8, // log2 of size of node array
	metatable: ^Table,
	array:     [^]TValue, // array part
	node:      ^Node,
	lastfree:  ^Node, // any free position is before this
	gclist:    ^GCObject,
	sizearray: c.int,
}

// Table size helpers
twoto :: #force_inline proc(x: u8) -> int {return 1 << uint(x)}
sizenode :: #force_inline proc(t: ^Table) -> int {return twoto(t.lsizenode)}
lmod :: #force_inline proc(s: uint, size: int) -> int {return int(s) & (size - 1)}

// Global nil object


// Utility functions

// Convert integer to floating point byte representation
int2fb :: #force_inline proc(x: u32) -> int {
	e := 0
	val := x
	for val >= 16 {
		val = (val + 1) >> 1
		e += 1
	}
	if val < 8 {
		return int(val)
	}
	return ((e + 1) << 3) | (int(val) - 8)
}

// Convert floating point byte back to integer
fb2int :: #force_inline proc(x: c.int) -> int {
	e := (x >> 3) & 31
	if e == 0 {
		return int(x)
	}
	return int(((x & 7) + 8) << uint(e - 1))
}

// Log2 lookup table
@(private)
log2_table := [256]u8 {
	0,
	1,
	2,
	2,
	3,
	3,
	3,
	3,
	4,
	4,
	4,
	4,
	4,
	4,
	4,
	4,
	5,
	5,
	5,
	5,
	5,
	5,
	5,
	5,
	5,
	5,
	5,
	5,
	5,
	5,
	5,
	5,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	6,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	7,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
	8,
}

// Compute log2 of x
log2 :: proc(x: u32) -> int {
	l := -1
	val := x
	for val >= 256 {
		l += 8
		val >>= 8
	}
	return l + int(log2_table[val])
}

ceillog2 :: #force_inline proc(x: u32) -> int {
	return log2(x - 1) + 1
}

// Raw equality comparison
rawequalObj :: #force_inline proc(t1: ^TValue, t2: ^TValue) -> bool {
	if t1.tt != t2.tt {
		return false
	}
	switch t1.tt {
	case LUA_TNIL:
		return true
	case LUA_TNUMBER:
		return t1.value.n == t2.value.n
	case LUA_TBOOLEAN:
		return t1.value.b == t2.value.b
	case LUA_TLIGHTUSERDATA:
		return t1.value.p == t2.value.p
	case:
		return t1.value.gc == t2.value.gc
	}
}

// Helpers added for API migration
// uvalue is in vm.odin. clvalue, hvalue are in do.odin.

thvalue :: #force_inline proc(o: ^TValue) -> ^lua_State {
	return cast(^lua_State)o.value.gc.th
}

rawuvalue :: #force_inline proc(o: ^TValue) -> ^Udata {
	return cast(^Udata)o.value.gc
}

svalue :: #force_inline proc(o: ^TValue) -> cstring {
	return getstr(tsvalue(o))
}

lua_number2integer :: #force_inline proc(res: ^lua_Integer, n: lua_Number) {
	res^ = cast(lua_Integer)n
}

// Lua Reader/Writer types
lua_Reader :: #type proc "c" (L: ^lua_State, ud: rawptr, sz: ^c.size_t) -> cstring
lua_Writer :: #type proc "c" (L: ^lua_State, p: rawptr, sz: c.size_t, ud: rawptr) -> c.int

setuvalue :: #force_inline proc(L: ^lua_State, obj: ^TValue, x: ^Udata) {
	obj.value.gc = cast(^GCObject)x
	obj.tt = LUA_TUSERDATA
}

setthvalue :: #force_inline proc(L: ^lua_State, obj: ^TValue, x: ^lua_State) {
	obj.value.gc = cast(^GCObject)x
	obj.tt = LUA_TTHREAD
}
