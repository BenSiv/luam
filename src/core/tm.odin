// Tag methods (metamethods)
// Migrated from ltm.c/h
package core

import "base:runtime"
import "core:c"
import "core:fmt"

// Type names for debugging
@(export, link_name = "luaT_typenames")
typenames := [NUM_TAGS + 3]cstring {
	"nil",
	"flag",
	"userdata",
	"number",
	"string",
	"table",
	"function",
	"userdata",
	"thread",
	"proto",
	"upval",
	"deadkey",
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


// Initialize tag method names in global state
@(export, link_name = "luaT_init")
luaT_init :: proc "c" (L: ^lua_State) {
	context = runtime.default_context()
	g := G(L)
	for i in TM.TM_INDEX ..= TM.TM_CALL {
		ts := luaS_new(L, eventnames[i])
		g.tmname[i] = ts
		luaS_fix(ts) // never collect these names
	}
}

// Get tag method from event table
// Used with fasttm macro - optimized for absence of tag methods
// Get tag method from event table
// Used with fasttm macro - optimized for absence of tag methods
@(export, link_name = "luaT_gettm")
luaT_gettm :: proc "c" (events: ^Table, event: c.int, ename: ^TString) -> ^TValue {
	context = runtime.default_context()
	tm := luaH_getstr(events, ename)
	ev := TM(event)

	// Check for fast events (TM_INDEX through TM_EQ)
	if ev <= TM.TM_EQ {
		if ttisnil(tm) {
			// No tag method - cache this fact
			events.flags |= u8(1 << u8(ev))
			return nil
		}
	} else {
		if ttisnil(tm) {
			return nil
		}
	}
	return cast(^TValue)tm
}

// Get tag method for an object
@(export, link_name = "luaT_gettmbyobj")
luaT_gettmbyobj :: proc "c" (L: ^lua_State, o: ^TValue, event: c.int) -> ^TValue {
	context = runtime.default_context()
	mt: ^Table = nil
	switch ttype(o) {
	case LUA_TTABLE:
		mt = hvalue(o).metatable
	case LUA_TUSERDATA:
		// mt = uvalue(o).uv.metatable
		return nilobject // Luam disabled metatables for userdata
	case:
		tag := ttype(o)
		if tag < 0 || tag >= i32(len(G(L).mt)) {
			return nilobject
		}
		mt = G(L).mt[tag]
	}

	if mt == nil {
		return nilobject
	}

	return fasttm(L, mt, TM(event))
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
	return luaT_gettm(et, c.int(e), g.tmname[e])
}

// Fast tag method lookup from lua_State
fasttm :: #force_inline proc(L: ^lua_State, et: ^Table, e: TM) -> ^TValue {
	return gfasttm(G(L), et, e)
}
