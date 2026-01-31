// Garbage Collector
// Migrated from lgc.c/h
// Essential linking functions and write barriers
package core

import "core:c"

// GC step size and costs
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

// Other white calculation
otherwhite :: #force_inline proc(g: ^Global_State) -> u8 {
	return g.currentwhite ~ WHITEBITS
}

// Mask for clearing marks
maskmarks :: ~u8((1 << BLACKBIT) | WHITEBITS)

// Make object white
makewhite :: #force_inline proc(g: ^Global_State, x: ^GCObject) {
	x.gch.marked = (x.gch.marked & maskmarks) | luaC_white(g)
}

// Convert white to gray
white2gray :: #force_inline proc(x: ^GCObject) {
	x.gch.marked &= ~u8(WHITEBITS)
}

// Convert gray to black
gray2black :: #force_inline proc(x: ^GCObject) {
	x.gch.marked |= (1 << BLACKBIT)
}

// Convert black to gray
black2gray :: #force_inline proc(x: ^GCObject) {
	x.gch.marked &= ~u8(1 << BLACKBIT)
}

// Check if gray (not white and not black)
isgray :: #force_inline proc(x: ^GCObject) -> bool {
	return !iswhite(x) && !isblack(x)
}

// Set threshold for next GC
setthreshold :: #force_inline proc(g: ^Global_State) {
	g.GCthreshold = (g.estimate / 100) * c.size_t(g.gcpause)
}

// Check if we need GC
luaC_checkGC :: #force_inline proc(L: ^lua_State) {
	g := G(L)
	if g.totalbytes >= g.GCthreshold {
		luaC_step_c(L)
	}
}

// FFI to C functions for complex GC operations
foreign import lua_core "system:lua"

foreign lua_core {
	@(link_name = "luaC_step")
	luaC_step_c :: proc(L: ^lua_State) ---
	@(link_name = "luaC_barrierf")
	luaC_barrierf :: proc(L: ^lua_State, o: ^GCObject, v: ^GCObject) ---
	@(link_name = "luaC_barrierback")
	luaC_barrierback :: proc(L: ^lua_State, t: ^Table) ---
	@(link_name = "luaC_link")
	luaC_link :: proc(L: ^lua_State, o: ^GCObject, tt: u8) ---
	@(link_name = "luaC_linkupval")
	luaC_linkupval :: proc(L: ^lua_State, uv: ^UpVal) ---
}

// Foreigns defined above

// Foreigns defined above

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
