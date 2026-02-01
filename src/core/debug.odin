// Debug Interface
// Migrated from ldebug.c/h
package core

import "core:c"

// Debug info struct (used by debug library)
LUA_IDSIZE :: 60

lua_Debug :: struct {
	event:           c.int,
	name:            cstring, // (n)
	namewhat:        cstring, // (n) 'global', 'local', 'field', 'method'
	what:            cstring, // (S) 'Lua', 'C', 'main', 'tail'
	source:          cstring, // (S)
	currentline:     c.int, // (l)
	nups:            c.int, // (u) number of upvalues
	linedefined:     c.int, // (S)
	lastlinedefined: c.int, // (S)
	short_src:       [LUA_IDSIZE]u8, // (S)
	// Private parts
	i_ci:            c.int, // active function
}

// Hook masks
LUA_MASKCALL :: 1 << 0
LUA_MASKRET :: 1 << 1
LUA_MASKLINE :: 1 << 2
LUA_MASKCOUNT :: 1 << 3

// Hook events
LUA_HOOKCALL :: 0
LUA_HOOKRET :: 1
LUA_HOOKLINE :: 2
LUA_HOOKCOUNT :: 3
LUA_HOOKTAILRET :: 4

// Maximum stack size
MAXSTACK :: 250

// Instruction constants
// MAX_A + 1

// lua_longjmp defined in state.odin
// Alloc defined in state.odin
foreign import lua_core "../../obj/liblua.a"

foreign lua_core {
	// luaD_throw_c defined in do.odin
	// luaD_call_c defined in do.odin
	luaO_pushvfstring_c :: proc(L: ^lua_State, fmt: cstring, argp: rawptr) -> cstring ---
	luaO_chunkid_c :: proc(out: [^]u8, source: cstring, bufflen: c.size_t) ---
	@(link_name = "luaG_errormsg")
	luaG_errormsg_c :: proc(L: ^lua_State) ---
}

// PC relative to function
pcRel :: #force_inline proc(pc: [^]Instruction, p: ^Proto) -> int {
	return int((cast(uintptr)pc - cast(uintptr)p.code) / size_of(Instruction)) - 1
}

// Get line info from proto
get_line_info :: #force_inline proc(p: ^Proto, pc: int) -> c.int {
	if p.lineinfo == nil || pc < 0 {
		return 0
	}
	return p.lineinfo[pc]
}

// Reset hook count
resethookcount :: #force_inline proc(L: ^lua_State) {
	L.hookcount = L.basehookcount
}

// Get current PC for a call info
currentpc :: proc(L: ^lua_State, ci: ^CallInfo) -> int {
	if !isLua(ci) {
		return -1
	}
	if ci == L.ci {
		L.savedpc = ci.savedpc // Ensure L.savedpc is up-to-date
	}
	return pcRel(ci.savedpc, ci_func(ci).l.p)
}

// Get current line for a call info
currentline :: proc(L: ^lua_State, ci: ^CallInfo) -> int {
	pc := currentpc(L, ci)
	if pc < 0 {
		return -1
	}
	return int(get_line_info(ci_func(ci).l.p, pc))
}

// Set debug hook
lua_sethook :: proc(L: ^lua_State, func: Hook, mask: int, count: int) -> int {
	if func == nil || mask == 0 {
		L.hookmask = 0
		L.hook = nil
	} else {
		L.hook = func
		L.basehookcount = c.int(count)
		resethookcount(L)
		L.hookmask = u8(mask)
	}
	return 1
}

// Get debug hook
lua_gethook :: proc(L: ^lua_State) -> Hook {
	return L.hook
}

// Get hook mask
lua_gethookmask :: proc(L: ^lua_State) -> int {
	return int(L.hookmask)
}

// Get hook count
lua_gethookcount :: proc(L: ^lua_State) -> int {
	return int(L.basehookcount)
}

// Get stack level
lua_getstack :: proc(L: ^lua_State, level: int, ar: ^lua_Debug) -> int {
	ci := L.ci
	lvl := level

	// Walk up the call stack
	for lvl > 0 && cast(uintptr)ci > cast(uintptr)L.base_ci {
		ci = cast(^CallInfo)(cast(uintptr)ci - size_of(CallInfo))
		lvl -= 1
		if f_isLua(ci) {
			lvl -= int(ci.tailcalls)
		}
	}

	if lvl == 0 && cast(uintptr)ci > cast(uintptr)L.base_ci {
		ar.i_ci = c.int((cast(uintptr)ci - cast(uintptr)L.base_ci) / size_of(CallInfo))
		return 1
	}
	if lvl < 0 {
		ar.i_ci = 0
		return 1
	}
	return 0
}

// Get proto from call info (if Lua function)
getluaproto :: proc(ci: ^CallInfo) -> ^Proto {
	if isLua(ci) {
		return ci_func(ci).l.p
	}
	return nil
}

// Check if pointer is in stack range
isinstack :: proc(ci: ^CallInfo, o: ^TValue) -> bool {
	p := ci.base
	for cast(uintptr)p < cast(uintptr)ci.top {
		if o == p {
			return true
		}
		p = cast(StkId)(cast(uintptr)p + size_of(TValue))
	}
	return false
}

// Check if instruction after an open call is valid
luaG_checkopenop :: proc(i: Instruction) -> int {
	#partial switch get_opcode(i) {
	case .OP_CALL, .OP_TAILCALL, .OP_RETURN, .OP_SETLIST:
		if getarg_b(i) == 0 {
			return 1
		}
		return 0
	case:
		return 0
	}
}

// Check bytecode validity
luaG_checkcode :: proc(pt: ^Proto) -> int {
	// Simplified check - full implementatino would use symbexec
	if pt.sizecode == 0 {
		return 0
	}
	// Check if the next instruction is a return
	// We need to decode the opcode
	if get_opcode(pt.code[pt.sizecode - 1]) != .OP_RETURN {
		return 0
	}
	return 1
}
