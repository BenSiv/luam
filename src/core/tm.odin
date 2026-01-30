// Tag methods (metamethods)
// Migrated from ltm.c/h
package core

import "core:c"

// Type names for debugging
typenames := [NUM_TAGS + 3]cstring {
	"nil",
	"boolean",
	"userdata",
	"number",
	"string",
	"table",
	"function",
	"userdata",
	"thread",
	"proto",
	"upval",
}

// Tag method event names (ORDER TM)
eventnames := [TM.TM_N]cstring {
	"__index",
	"__newindex",
	"__gc",
	"__mode",
	"__eq",
	"__add",
	"__sub",
	"__mul",
	"__div",
	"__mod",
	"__pow",
	"__unm",
	"__len",
	"__lt",
	"__le",
	"__concat",
	"__call",
}

// FFI to C functions
@(private)
foreign import lua_core "system:lua"

@(private)
foreign lua_core {
	luaS_new_c :: proc(L: ^lua_State, s: cstring) -> ^TString ---
}

// Initialize tag method names in global state
luaT_init :: proc(L: ^lua_State) {
	g := G(L)
	for i in TM.TM_INDEX ..= TM.TM_CALL {
		ts := luaS_new_c(L, eventnames[i])
		g.tmname[i] = ts
		luaS_fix(ts) // never collect these names
	}
}

// Get tag method from event table
// Used with fasttm macro - optimized for absence of tag methods
luaT_gettm :: proc(events: ^Table, event: TM, ename: ^TString) -> ^TValue {
	tm := luaH_getstr(events, ename)

	// Check for fast events (TM_INDEX through TM_EQ)
	if event <= TM.TM_EQ {
		if ttisnil(tm) {
			// No tag method - cache this fact
			events.flags |= u8(1 << u8(event))
			return nil
		}
	} else {
		if ttisnil(tm) {
			return nil
		}
	}
	return cast(^TValue)tm
}

// Get tag method by object type
luaT_gettmbyobj :: proc(L: ^lua_State, o: ^TValue, event: TM) -> ^TValue {
	mt: ^Table = nil

	switch o.tt {
	case LUA_TTABLE:
		// Get table's metatable
		t := cast(^Table)o.value.gc
		mt = t.metatable
	case LUA_TUSERDATA:
		// Get userdata's metatable
		u := cast(^Udata)o.value.gc
		mt = u.uv.metatable
	case:
		// Get type's metatable from global state
		g := G(L)
		if o.tt >= 0 && o.tt < NUM_TAGS {
			mt = g.mt[o.tt]
		}
	}

	if mt == nil {
		return nilobject
	}

	return luaH_getstr(mt, G(L).tmname[event])
}

// Fast tag method lookup macro as inline proc
// Returns nil if events table is nil or if the tag method flag is set (cached absence)
gfasttm :: #force_inline proc(g: ^Global_State, et: ^Table, e: TM) -> ^TValue {
	if et == nil {
		return nil
	}
	if (et.flags & u8(1 << u8(e))) != 0 {
		return nil // cached: tag method is absent
	}
	return luaT_gettm(et, e, g.tmname[e])
}

// Fast tag method lookup from lua_State
fasttm :: #force_inline proc(L: ^lua_State, et: ^Table, e: TM) -> ^TValue {
	return gfasttm(G(L), et, e)
}
