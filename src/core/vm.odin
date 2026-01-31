// Lua Virtual Machine
// Migrated from lvm.c/h
package core

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:strconv"

// Helpers
tsvalue :: #force_inline proc(o: ^TValue) -> ^TString {return &o.value.gc.ts}
uvalue :: #force_inline proc(o: ^TValue) -> ^Udata {return &o.value.gc.u}

// Limit for table tag-method chains (to avoid loops)
MAXTAGLOOP :: 100

// Multiple returns
LUA_MULTRET :: -1

// FFI to C functions
// FFI to C functions
foreign import lua_core "system:lua"

foreign lua_core {
	@(link_name = "luaG_typeerror")
	luaG_typeerror_c :: proc(L: ^lua_State, o: ^TValue, op: cstring) ---
	@(link_name = "luaG_concaterror")
	luaG_concaterror_c :: proc(L: ^lua_State, p1: StkId, p2: StkId) ---
	@(link_name = "luaG_aritherror")
	luaG_aritherror_c :: proc(L: ^lua_State, p1: ^TValue, p2: ^TValue) ---
	@(link_name = "luaG_ordererror")
	luaG_ordererror_c :: proc(L: ^lua_State, p1: ^TValue, p2: ^TValue) -> c.int ---
	@(link_name = "luaO_str2d")
	luaO_str2d_c :: proc(s: cstring, result: ^lua_Number) -> c.int ---
	@(link_name = "luaO_rawequalObj")
	luaO_rawequalObj_c :: proc(t1: ^TValue, t2: ^TValue) -> c.int ---
	@(link_name = "luaZ_openspace")
	luaZ_openspace_c :: proc(L: ^lua_State, buff: ^Mbuffer, n: c.size_t) -> [^]u8 ---
}

// Number arithmetic macros as inline procs
luai_numadd :: #force_inline proc(a: lua_Number, b: lua_Number) -> lua_Number {
	return a + b
}

luai_numsub :: #force_inline proc(a: lua_Number, b: lua_Number) -> lua_Number {
	return a - b
}

luai_nummul :: #force_inline proc(a: lua_Number, b: lua_Number) -> lua_Number {
	return a * b
}

luai_numdiv :: #force_inline proc(a: lua_Number, b: lua_Number) -> lua_Number {
	return a / b
}

luai_nummod :: #force_inline proc(a: lua_Number, b: lua_Number) -> lua_Number {
	return a - math.floor(a / b) * b
}

luai_numpow :: #force_inline proc(a: lua_Number, b: lua_Number) -> lua_Number {
	return math.pow(a, b)
}

luai_numunm :: #force_inline proc(a: lua_Number) -> lua_Number {
	return -a
}

luai_numeq :: #force_inline proc(a: lua_Number, b: lua_Number) -> bool {
	return a == b
}

luai_numlt :: #force_inline proc(a: lua_Number, b: lua_Number) -> bool {
	return a < b
}

luai_numle :: #force_inline proc(a: lua_Number, b: lua_Number) -> bool {
	return a <= b
}


// Convert to number, returns nil if not convertible
@(export, link_name = "luaV_tonumber")
luaV_tonumber :: proc "c" (obj: ^TValue, n: ^TValue) -> ^TValue {
	context = runtime.default_context()
	if ttisnumber(obj) {
		return obj
	}
	if ttisstring(obj) {
		num: lua_Number
		s := getstr(&obj.value.gc.ts)
		if luaO_str2d_c(s, &num) != 0 {
			setnvalue(n, num)
			return n
		}
	}
	return nil
}

// Check if value can be converted to number inline
tonumber :: #force_inline proc(v: ^TValue, n: ^TValue) -> bool {
	return ttisnumber(v) || luaV_tonumber(v, n) != nil
}

// Convert number to string
@(export, link_name = "luaV_tostring")
luaV_tostring :: proc "c" (L: ^lua_State, obj: StkId) -> int {
	context = runtime.default_context()
	if !ttisnumber(obj) {
		return 0
	}
	// Use a buffer for number to string conversion
	s: [64]u8
	n := nvalue(obj)
	// Simple number formatting
	len := num_to_str(&s, n)
	s_ptr := cast([^]u8)&s[0]

	pos := savestack(L, obj)
	ts := luaS_newlstr(L, cast(cstring)s_ptr, c.size_t(len))
	setsvalue2s(L, restorestack(L, pos), ts)
	return 1
}

// Helper for number to string (simplified)
@(private)
num_to_str :: proc(buf: ^[64]u8, n: lua_Number) -> int {
	// Simple implementation - just format as integer if whole, else float
	// In real implementation, would use proper Lua number formatting

	if n == f64(int(n)) {
		// Integer
		s := fmt.bprintf(buf[:], "%d", int(n))
		return len(s)
	}
	// Float - simplified
	s := fmt.bprintf(buf[:], "%.14g", n)
	return len(s)
}

// tostring conversion helper
tostring :: #force_inline proc(L: ^lua_State, o: StkId) -> bool {
	return ttisstring(o) || luaV_tostring(L, o) != 0
}

// Call tag method with result
callTMres :: proc(L: ^lua_State, res: StkId, f: ^TValue, p1: ^TValue, p2: ^TValue) {
	luaD_checkstack(L, 3)
	result := savestack(L, res)
	setobj2s(L, L.top, f) // push function
	setobj2s(L, cast(StkId)(cast(uintptr)L.top + size_of(TValue)), p1) // 1st argument
	setobj2s(L, cast(StkId)(cast(uintptr)L.top + 2 * size_of(TValue)), p2) // 2nd argument
	L.top = cast(StkId)(cast(uintptr)L.top + 3 * size_of(TValue))
	luaD_call_c(L, cast(StkId)(cast(uintptr)L.top - 3 * size_of(TValue)), 1)
	res_restored := restorestack(L, result)
	L.top = cast(StkId)(cast(uintptr)L.top - size_of(TValue))
	setobjs2s(L, res_restored, L.top)
}

// Call tag method without result
callTM :: proc(L: ^lua_State, f: ^TValue, p1: ^TValue, p2: ^TValue, p3: ^TValue) {
	luaD_checkstack(L, 4)
	setobj2s(L, L.top, f) // push function
	setobj2s(L, cast(StkId)(cast(uintptr)L.top + size_of(TValue)), p1)
	setobj2s(L, cast(StkId)(cast(uintptr)L.top + 2 * size_of(TValue)), p2)
	setobj2s(L, cast(StkId)(cast(uintptr)L.top + 3 * size_of(TValue)), p3)
	L.top = cast(StkId)(cast(uintptr)L.top + 4 * size_of(TValue))
	luaD_call_c(L, cast(StkId)(cast(uintptr)L.top - 4 * size_of(TValue)), 0)
}

// Get table value with metamethods
@(export, link_name = "luaV_gettable")
luaV_gettable :: proc "c" (L: ^lua_State, t: ^TValue, key: ^TValue, val: StkId) {
	context = runtime.default_context()
	t := t
	temp: TValue
	for loop in 0 ..< MAXTAGLOOP {
		tm: ^TValue = nil

		if ttistable(t) {
			h := hvalue(t)
			res := luaH_get(h, key)
			tm = fasttm(L, h.metatable, .TM_INDEX)
			if !ttisnil(res) || tm == nil {
				setobj2s(L, val, res)
				return
			}
		} else {
			tm = luaT_gettmbyobj(L, t, c.int(TM.TM_INDEX))
			if ttisnil(tm) {
				luaG_typeerror_c(L, t, "index")
			}
		}

		if ttisfunction(tm) {
			callTMres(L, val, tm, t, key)
			return
		}
		// else repeat with 'tm'
		setobj(&temp, tm)
		t = &temp
	}
	luaG_runerror_c(L, "loop in gettable")
}

// Set table value with metamethods
@(export, link_name = "luaV_settable")
luaV_settable :: proc "c" (L: ^lua_State, t: ^TValue, key: ^TValue, val: StkId) {
	context = runtime.default_context()
	t := t
	temp: TValue

	for loop in 0 ..< MAXTAGLOOP {
		tm: ^TValue = nil

		if ttistable(t) {
			h := hvalue(t)
			oldval := luaH_set(L, h, key)
			tm = fasttm(L, h.metatable, .TM_NEWINDEX)
			if !ttisnil(oldval) || tm == nil {
				setobj2t(L, oldval, val)
				h.flags = 0
				luaC_barriert(L, h, val)
				return
			}
		} else {
			tm = luaT_gettmbyobj(L, t, c.int(TM.TM_NEWINDEX))
			if ttisnil(tm) {
				luaG_typeerror_c(L, t, "index")
			}
		}

		if ttisfunction(tm) {
			callTM(L, tm, t, key, val)
			return
		}
		// else repeat with 'tm'
		setobj(&temp, tm) // avoid pointing inside table (may rehash)
		t = &temp
	}
	luaG_runerror_c(L, "loop in settable")
}

// Call binary tag method
call_binTM :: proc(L: ^lua_State, p1: ^TValue, p2: ^TValue, res: StkId, event: TM) -> bool {
	tm := luaT_gettmbyobj(L, p1, c.int(event)) // try first operand
	if ttisnil(tm) {
		tm = luaT_gettmbyobj(L, p2, c.int(event)) // try second operand
	}
	if ttisnil(tm) {
		return false
	}
	callTMres(L, res, tm, p1, p2)
	return true
}

// Get comparison tag method
get_compTM :: proc(L: ^lua_State, mt1: ^Table, mt2: ^Table, event: TM) -> ^TValue {
	tm1 := fasttm(L, mt1, event)
	if tm1 == nil {
		return nil
	}
	if mt1 == mt2 {
		return tm1 // same metatables => same metamethods
	}
	tm2 := fasttm(L, mt2, event)
	if tm2 == nil {
		return nil
	}
	if luaO_rawequalObj_c(cast(^TValue)tm1, cast(^TValue)tm2) != 0 {
		return tm1
	}
	return nil
}

// String comparison
l_strcmp :: proc(ls: ^TString, rs: ^TString) -> int {
	l := getstr(ls)
	ll := ls.tsv.len
	r := getstr(rs)
	lr := rs.tsv.len

	// Compare byte by byte
	min_len := min(ll, lr)
	for i in 0 ..< int(min_len) {
		lc := (cast([^]u8)l)[i]
		rc := (cast([^]u8)r)[i]
		if lc != rc {
			return int(lc) - int(rc)
		}
	}

	// Prefix match - shorter string is less
	if ll < lr {return -1}
	if ll > lr {return 1}
	return 0
}

// Less than comparison
@(export, link_name = "luaV_lessthan")
luaV_lessthan :: proc "c" (L: ^lua_State, l: ^TValue, r: ^TValue) -> int {
	context = runtime.default_context()
	if ttype(l) != ttype(r) {
		return int(luaG_ordererror_c(L, l, r))
	}
	if ttisnumber(l) {
		return luai_numlt(nvalue(l), nvalue(r)) ? 1 : 0
	}
	if ttisstring(l) {
		return l_strcmp(rawtsvalue(l), rawtsvalue(r)) < 0 ? 1 : 0
	}
	// Try metamethod
	res := call_orderTM(L, l, r, .TM_LT)
	if res != -1 {
		return res
	}
	return int(luaG_ordererror_c(L, l, r))
}

// Call order tag method
call_orderTM :: proc(L: ^lua_State, p1: ^TValue, p2: ^TValue, event: TM) -> int {
	tm1 := luaT_gettmbyobj(L, p1, c.int(event))
	if ttisnil(tm1) {
		return -1 // no metamethod
	}
	tm2 := luaT_gettmbyobj(L, p2, c.int(event))
	if luaO_rawequalObj_c(cast(^TValue)tm1, cast(^TValue)tm2) == 0 {
		return -1 // different metamethods
	}
	callTMres(L, L.top, tm1, p1, p2)
	return l_isfalse(L.top) ? 0 : 1
}

// Less than or equal comparison
lessequal :: proc(L: ^lua_State, l: ^TValue, r: ^TValue) -> int {
	if ttype(l) != ttype(r) {
		return int(luaG_ordererror_c(L, l, r))
	}
	if ttisnumber(l) {
		return luai_numle(nvalue(l), nvalue(r)) ? 1 : 0
	}
	if ttisstring(l) {
		return l_strcmp(rawtsvalue(l), rawtsvalue(r)) <= 0 ? 1 : 0
	}
	// Try 'le' first
	res := call_orderTM(L, l, r, .TM_LE)
	if res != -1 {
		return res
	}
	// Then try 'lt' (reversed)
	res = call_orderTM(L, r, l, .TM_LT)
	if res != -1 {
		return res == 0 ? 1 : 0 // !res
	}
	return int(luaG_ordererror_c(L, l, r))
}

// Equality comparison
@(export, link_name = "luaV_equalval")
luaV_equalval :: proc "c" (L: ^lua_State, t1: ^TValue, t2: ^TValue) -> int {
	context = runtime.default_context()
	tm: ^TValue = nil

	switch ttype(t1) {
	case LUA_TNIL:
		return 1
	case LUA_TNUMBER:
		return luai_numeq(nvalue(t1), nvalue(t2)) ? 1 : 0
	case LUA_TBOOLEAN:
		return bvalue(t1) == bvalue(t2) ? 1 : 0
	case LUA_TLIGHTUSERDATA:
		return pvalue(t1) == pvalue(t2) ? 1 : 0
	case LUA_TUSERDATA:
		if uvalue(t1) == uvalue(t2) {
			return 1
		}
		return 0 // No metatable comparison
	case LUA_TTABLE:
		if hvalue(t1) == hvalue(t2) {
			return 1
		}
		tm = get_compTM(L, hvalue(t1).metatable, hvalue(t2).metatable, .TM_EQ)
	case:
		return gcvalue(t1) == gcvalue(t2) ? 1 : 0
	}

	if tm == nil {
		return 0
	}
	callTMres(L, L.top, tm, t1, t2)
	return l_isfalse(L.top) ? 0 : 1
}

// Object equality wrapper
equalobj :: #force_inline proc(L: ^lua_State, o1: ^TValue, o2: ^TValue) -> bool {
	if ttype(o1) != ttype(o2) {
		return false
	}
	return luaV_equalval(L, o1, o2) != 0
}

// Arithmetic operation
Arith :: proc(L: ^lua_State, ra: StkId, rb: ^TValue, rc: ^TValue, op: TM) {
	tempb, tempc: TValue
	b := luaV_tonumber(rb, &tempb)
	c := luaV_tonumber(rc, &tempc)

	if b != nil && c != nil {
		nb := nvalue(b)
		nc := nvalue(c)

		#partial switch op {
		case .TM_ADD:
			setnvalue(ra, luai_numadd(nb, nc))
		case .TM_SUB:
			setnvalue(ra, luai_numsub(nb, nc))
		case .TM_MUL:
			setnvalue(ra, luai_nummul(nb, nc))
		case .TM_DIV:
			setnvalue(ra, luai_numdiv(nb, nc))
		case .TM_MOD:
			setnvalue(ra, luai_nummod(nb, nc))
		case .TM_POW:
			setnvalue(ra, luai_numpow(nb, nc))
		case .TM_UNM:
			setnvalue(ra, luai_numunm(nb))
		case: // Should not happen
		}
	} else {
		if !call_binTM(L, rb, rc, ra, op) {
			luaG_aritherror_c(L, rb, rc)
		}
	}
}

// Set obj2s helper (set object to stack with barrier)
setobj2s :: #force_inline proc(L: ^lua_State, o1: ^TValue, o2: ^TValue) {
	o1.value = o2.value
	o1.tt = o2.tt
}

// Set obj2t helper (set object to table with barrier)
setobj2t :: #force_inline proc(L: ^lua_State, o1: ^TValue, o2: ^TValue) {
	o1.value = o2.value
	o1.tt = o2.tt
}

// Concat string values
@(export, link_name = "luaV_concat")
luaV_concat :: proc "c" (L: ^lua_State, total: int, last: int) {
	context = runtime.default_context()
	total := total
	last := last

	refresh_top :: #force_inline proc(L: ^lua_State, last: int) -> StkId {
		return cast(StkId)(cast(uintptr)L.base + uintptr(last + 1) * size_of(TValue))
	}

	for total > 1 {
		n := 2
		top := refresh_top(L, last)

		// Check if top-2 and top-1 are strings or numbers
		val_minus_2 := cast(StkId)(cast(uintptr)top - 2 * size_of(TValue))
		val_minus_1 := cast(StkId)(cast(uintptr)top - size_of(TValue))

		if !(ttisstring(val_minus_2) || ttisnumber(val_minus_2)) || !tostring(L, val_minus_1) {
			// Refresh pointers after potential tostring realloc
			top = refresh_top(L, last)
			val_minus_2 = cast(StkId)(cast(uintptr)top - 2 * size_of(TValue))
			val_minus_1 = cast(StkId)(cast(uintptr)top - size_of(TValue))
			if !call_binTM(L, val_minus_2, val_minus_1, val_minus_2, .TM_CONCAT) {
				luaG_concaterror_c(L, val_minus_2, val_minus_1)
			}
		} else if tsvalue(val_minus_1).tsv.len == 0 {
			// Second op is empty? Result is first op (as string)
			tostring(L, val_minus_2)
		} else {
			// At least two string values; get as many as possible
			tl := tsvalue(val_minus_1).tsv.len
			i := 1
			n = 1

			// Collect total length
			for n < total {
				val_minus_n_1 := cast(StkId)(cast(uintptr)refresh_top(L, last) -
					uintptr(n + 1) * size_of(TValue))
				if !tostring(L, val_minus_n_1) {break}

				l := tsvalue(val_minus_n_1).tsv.len
				if l >= MAX_SIZET - tl {
					luaG_runerror_c(L, "string length overflow")
				}
				tl += l
				n += 1
			}

			// Allocate buffer
			buff := &G(L).buff
			buffer := luaZ_openspace_c(L, buff, tl)

			tl = 0
			for i = n; i > 0; i -= 1 {
				val_minus_i := cast(StkId)(cast(uintptr)refresh_top(L, last) -
					uintptr(i) * size_of(TValue))
				l := tsvalue(val_minus_i).tsv.len
				mem.copy(
					cast(rawptr)(cast(uintptr)buffer + uintptr(tl)),
					cast(rawptr)getstr(tsvalue(val_minus_i)),
					int(l),
				)
				tl += l
			}

			dest_pos := savestack(
				L,
				cast(StkId)(cast(uintptr)refresh_top(L, last) - uintptr(n) * size_of(TValue)),
			)
			ts := luaS_newlstr(L, cast(cstring)buffer, tl)
			setsvalue2s(L, restorestack(L, dest_pos), ts)
		}

		total -= n - 1
		last -= n - 1
	}
}
