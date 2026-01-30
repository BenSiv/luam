package lua

import "base:runtime"
import "core:c"
import "core:mem"

// Basic types
State :: distinct rawptr
CFunction :: #type proc "c" (L: ^State) -> c.int

// Constants
LUA_MULTRET :: -1
LUA_YIELD :: 1
LUA_ERRERR :: 5

LUA_VERSION :: "Lua 5.1"
LUA_RELEASE :: "Luam"

LUA_GCSTOP :: 0
LUA_GCRESTART :: 1
LUA_GCCOLLECT :: 2
LUA_GCCOUNT :: 3
LUA_GCCOUNTB :: 4
LUA_GCSTEP :: 5
LUA_GCSETPAUSE :: 6
LUA_GCSETSTEPMUL :: 7

LUA_HOOKCALL :: 0
LUA_HOOKRET :: 1
LUA_HOOKLINE :: 2
LUA_HOOKCOUNT :: 3
LUA_HOOKTAILRET :: 4

LUA_MASKCALL :: (1 << LUA_HOOKCALL)
LUA_MASKRET :: (1 << LUA_HOOKRET)
LUA_MASKLINE :: (1 << LUA_HOOKLINE)
LUA_MASKCOUNT :: (1 << LUA_HOOKCOUNT)

LUA_FILEHANDLE :: "FILE*"

LUA_NUMBER_SCAN :: "%lf"
LUA_NUMBER_FMT :: "%.14g"

// Dynamic library bindings
foreign import liblua "system:c"
foreign import libc "system:c"

@(default_calling_convention = "c")
foreign libc {
	fopen :: proc(filename: cstring, mode: cstring) -> rawptr ---
	fclose :: proc(stream: rawptr) -> c.int ---
	fflush :: proc(stream: rawptr) -> c.int ---
	fread :: proc(ptr: rawptr, size: c.size_t, nmemb: c.size_t, stream: rawptr) -> c.size_t ---
	fwrite :: proc(ptr: rawptr, size: c.size_t, nmemb: c.size_t, stream: rawptr) -> c.size_t ---
	fseek :: proc(stream: rawptr, offset: c.long, whence: c.int) -> c.int ---
	ftell :: proc(stream: rawptr) -> c.long ---
	setvbuf :: proc(stream: rawptr, buf: [^]u8, mode: c.int, size: c.size_t) -> c.int ---
	fprintf :: proc(stream: rawptr, format: cstring, #c_vararg args: ..any) -> c.int ---
	fscanf :: proc(stream: rawptr, format: cstring, #c_vararg args: ..any) -> c.int ---
	getc :: proc(stream: rawptr) -> c.int ---
	ungetc :: proc(ch: c.int, stream: rawptr) -> c.int ---
	getenv :: proc(name: cstring) -> cstring ---

	// dynamic loading
	dlopen :: proc(filename: cstring, flag: c.int) -> rawptr ---
	dlclose :: proc(handle: rawptr) -> c.int ---
	dlsym :: proc(handle: rawptr, symbol: cstring) -> rawptr ---
	dlerror :: proc() -> cstring ---
	fgets :: proc(s: [^]u8, n: c.int, stream: rawptr) -> [^]u8 ---
	popen :: proc(command: cstring, mode: cstring) -> rawptr ---
	pclose :: proc(stream: rawptr) -> c.int ---
	tmpfile :: proc() -> rawptr ---
	clearerr :: proc(stream: rawptr) ---
	ferror :: proc(stream: rawptr) -> c.int ---
	feof :: proc(stream: rawptr) -> c.int ---
	strerror :: proc(errnum: c.int) -> cstring ---

	luaL_get_stdin :: proc() -> rawptr ---
	luaL_get_stdout :: proc() -> rawptr ---
	luaL_get_stderr :: proc() -> rawptr ---
}

@(default_calling_convention = "c")
foreign liblua {
	lua_pushcclosure :: proc(L: ^State, fn: CFunction, n: c.int) ---
	lua_pushstring :: proc(L: ^State, s: cstring) ---
	lua_pushlstring :: proc(L: ^State, s: cstring, len: c.size_t) ---
	lua_call :: proc(L: ^State, nargs: c.int, nresults: c.int) ---
	lua_pushvalue :: proc(L: ^State, idx: c.int) ---
	lua_settop :: proc(L: ^State, idx: c.int) ---
	lua_replace :: proc(L: ^State, idx: c.int) ---
	lua_gettable :: proc(L: ^State, idx: c.int) ---
	lua_settable :: proc(L: ^State, idx: c.int) ---
	lua_toboolean :: proc(L: ^State, idx: c.int) -> c.int ---
	lua_tointeger :: proc(L: ^State, idx: c.int) -> Integer ---
	lua_tonumber :: proc(L: ^State, idx: c.int) -> Number ---
	lua_tolstring :: proc(L: ^State, idx: c.int, len: ^c.size_t) -> cstring ---
	lua_objlen :: proc(L: ^State, idx: c.int) -> c.size_t ---
	lua_next :: proc(L: ^State, idx: c.int) -> c.int ---
	lua_rawget :: proc(L: ^State, idx: c.int) ---
	lua_rawset :: proc(L: ^State, idx: c.int) ---
	lua_rawequal :: proc(L: ^State, idx1: c.int, idx2: c.int) -> c.int ---
	lua_rawgeti :: proc(L: ^State, idx: c.int, n: c.int) ---
	lua_rawseti :: proc(L: ^State, idx: c.int, n: c.int) ---
	lua_lessthan :: proc(L: ^State, idx1: c.int, idx2: c.int) -> c.int ---
	lua_typename :: proc(L: ^State, tp: c.int) -> cstring ---
	lua_topointer :: proc(L: ^State, idx: c.int) -> rawptr ---
	lua_tothread :: proc(L: ^State, idx: c.int) -> ^State ---
	lua_newthread :: proc(L: ^State) -> ^State ---
	lua_setfield :: proc(L: ^State, idx: c.int, k: cstring) ---
	lua_getfield :: proc(L: ^State, idx: c.int, k: cstring) ---
	lua_createtable :: proc(L: ^State, narr, nrec: c.int) ---
	lua_newuserdata :: proc(L: ^State, size: c.size_t) -> rawptr ---
	lua_getmetatable :: proc(L: ^State, objindex: c.int) -> c.int ---
	lua_setmetatable :: proc(L: ^State, objindex: c.int) -> c.int ---
	lua_type :: proc(L: ^State, idx: c.int) -> c.int ---

	@(link_name = "lua_isnumber")
	_lua_isnumber :: proc(L: ^State, idx: c.int) -> c.int ---
	@(link_name = "lua_isstring")
	_lua_isstring :: proc(L: ^State, idx: c.int) -> c.int ---
	@(link_name = "lua_iscfunction")
	_lua_iscfunction :: proc(L: ^State, idx: c.int) -> c.int ---
	@(link_name = "lua_isuserdata")
	_lua_isuserdata :: proc(L: ^State, idx: c.int) -> c.int ---

	lua_touserdata :: proc(L: ^State, idx: c.int) -> rawptr ---
	lua_concat :: proc(L: ^State, n: c.int) ---
	lua_pushnumber :: proc(L: ^State, n: Number) ---
	lua_pushfstring :: proc(L: ^State, format: cstring, #c_vararg args: ..any) -> cstring ---
	lua_pushvfstring :: proc(L: ^State, fmt: cstring, argp: rawptr) -> cstring ---
	lua_pushinteger :: proc(L: ^State, n: Integer) ---
	lua_pushnil :: proc(L: ^State) ---
	lua_pushboolean :: proc(L: ^State, b: c.int) ---
	lua_pushlightuserdata :: proc(L: ^State, p: rawptr) ---
	lua_pcall :: proc(L: ^State, nargs: c.int, nresults: c.int, errfunc: c.int) -> c.int ---
	lua_cpcall :: proc(L: ^State, func: CFunction, ud: rawptr) -> c.int ---
	lua_close :: proc(L: ^State) ---
	lua_insert :: proc(L: ^State, idx: c.int) ---
	lua_remove :: proc(L: ^State, idx: c.int) ---
	lua_checkstack :: proc(L: ^State, sz: c.int) -> c.int ---
	lua_setfenv :: proc(L: ^State, idx: c.int) -> c.int ---
	lua_getfenv :: proc(L: ^State, idx: c.int) ---
	lua_getstack :: proc(L: ^State, level: c.int, ar: ^Debug) -> c.int ---
	lua_getinfo :: proc(L: ^State, what: cstring, ar: ^Debug) -> c.int ---
	lua_getlocal :: proc(L: ^State, ar: ^Debug, n: c.int) -> cstring ---
	lua_setlocal :: proc(L: ^State, ar: ^Debug, n: c.int) -> cstring ---
	lua_getupvalue :: proc(L: ^State, funcindex: c.int, n: c.int) -> cstring ---
	lua_setupvalue :: proc(L: ^State, funcindex: c.int, n: c.int) -> cstring ---
	lua_sethook :: proc(L: ^State, func: Hook, mask: c.int, count: c.int) -> c.int ---
	lua_gethook :: proc(L: ^State) -> Hook ---
	lua_gethookmask :: proc(L: ^State) -> c.int ---
	lua_gethookcount :: proc(L: ^State) -> c.int ---
	lua_error :: proc(L: ^State) -> c.int ---
	lua_load :: proc(L: ^State, reader: Reader, dt: rawptr, chunkname: cstring) -> c.int ---
	lua_setlevel :: proc(from: ^State, to: ^State) ---
	lua_xmove :: proc(from: ^State, to: ^State, n: c.int) ---
	lua_pushthread :: proc(L: ^State) -> c.int ---
	lua_resume :: proc(Co: ^State, narg: c.int) -> c.int ---
	lua_yield :: proc(L: ^State, nresults: c.int) -> c.int ---
	lua_status :: proc(L: ^State) -> c.int ---
	lua_gc :: proc(L: ^State, what: c.int, data: c.int) -> c.int ---
	lua_gettop :: proc(L: ^State) -> c.int ---

	luaL_register :: proc(L: ^State, libname: cstring, l: ^Reg) ---
	luaL_checkstack :: proc(L: ^State, sz: c.int, msg: cstring) ---
	luaL_checknumber :: proc(L: ^State, numArg: c.int) -> Number ---
	luaL_checkinteger :: proc(L: ^State, numArg: c.int) -> Integer ---
	luaL_optinteger :: proc(L: ^State, nArg: c.int, def: Integer) -> Integer ---
	luaL_optlstring :: proc(L: ^State, narg: c.int, d: cstring, l: ^c.size_t) -> cstring ---
	luaL_checklstring :: proc(L: ^State, narg: c.int, l: ^c.size_t) -> cstring ---
	luaL_checktype :: proc(L: ^State, narg: c.int, t: c.int) ---
	luaL_checkany :: proc(L: ^State, narg: c.int) ---
	luaL_checkudata :: proc(L: ^State, narg: c.int, tname: cstring) -> rawptr ---
	luaL_argerror :: proc(L: ^State, narg: c.int, extramsg: cstring) -> c.int ---
	luaL_where :: proc(L: ^State, lvl: c.int) ---
	luaL_error :: proc(L: ^State, fmt: cstring, #c_vararg args: ..any) -> c.int ---
	luaL_loadfile :: proc(L: ^State, filename: cstring) -> c.int ---
	luaL_loadbuffer :: proc(L: ^State, buff: cstring, sz: c.size_t, name: cstring) -> c.int ---
	luaL_getmetafield :: proc(L: ^State, obj: c.int, e: cstring) -> c.int ---
	luaL_callmeta :: proc(L: ^State, obj: c.int, e: cstring) -> c.int ---
	luaL_checkoption :: proc(L: ^State, narg: c.int, def: cstring, lst: [^]cstring) -> c.int ---
	luaL_newmetatable :: proc(L: ^State, tname: cstring) -> c.int ---
	luaL_ref :: proc(L: ^State, t: c.int) -> c.int ---
	luaL_unref :: proc(L: ^State, t: c.int, ref: c.int) ---
	luaL_gsub :: proc(L: ^State, s: cstring, p: cstring, r: cstring) -> cstring ---
	luaL_findtable :: proc(L: ^State, idx: c.int, fname: cstring, szhint: c.int) -> cstring ---

	luaL_buffinit :: proc(L: ^State, B: ^Buffer) ---
	luaL_prepbuffer :: proc(B: ^Buffer) -> [^]u8 ---
	luaL_addlstring :: proc(B: ^Buffer, s: cstring, l: c.size_t) ---
	luaL_addstring :: proc(B: ^Buffer, s: cstring) ---
	luaL_addvalue :: proc(B: ^Buffer) ---
	luaL_pushresult :: proc(B: ^Buffer) ---

	lua_dump :: proc(L: ^State, writer: Writer, data: rawptr) -> c.int ---
	sprintf :: proc(s: [^]u8, format: cstring, #c_vararg args: ..any) -> c.int ---

	// Standard Library Open Functions
	luaopen_base :: proc(L: ^State) -> c.int ---
	luaopen_package :: proc(L: ^State) -> c.int ---
	luaopen_table :: proc(L: ^State) -> c.int ---
	luaopen_io :: proc(L: ^State) -> c.int ---
	luaopen_os :: proc(L: ^State) -> c.int ---
	luaopen_string :: proc(L: ^State) -> c.int ---
	luaopen_math :: proc(L: ^State) -> c.int ---
	luaopen_debug :: proc(L: ^State) -> c.int ---
	luaopen_bit :: proc(L: ^State) -> c.int ---
	luaopen_struct :: proc(L: ^State) -> c.int ---
}

Writer :: #type proc "c" (L: ^State, p: rawptr, sz: c.size_t, ud: rawptr) -> c.int
Reader :: #type proc "c" (L: ^State, ud: rawptr, sz: ^c.size_t) -> cstring
Hook :: #type proc "c" (L: ^State, ar: ^Debug)

Debug :: struct {
	event:           c.int,
	name:            cstring,
	namewhat:        cstring,
	what:            cstring,
	source:          cstring,
	currentline:     c.int,
	nups:            c.int,
	linedefined:     c.int,
	lastlinedefined: c.int,
	short_src:       [60]c.char, // LUA_IDSIZE
	i_ci:            c.int,
}

// Helper wrappers
luaL_checkstring :: proc "c" (L: ^State, narg: c.int) -> cstring {
	return luaL_checklstring(L, narg, nil)
}

luaL_getmetatable :: #force_inline proc "c" (L: ^State, tname: cstring) {
	lua_getfield(L, LUA_REGISTRYINDEX, tname)
}

lua_pop :: #force_inline proc "c" (L: ^State, n: c.int) {
	lua_settop(L, -(n) - 1)
}

luaL_optint :: #force_inline proc "c" (L: ^State, narg: c.int, def: c.int) -> c.int {
	return c.int(luaL_optinteger(L, narg, Integer(def)))
}

luaL_checkint :: #force_inline proc "c" (L: ^State, narg: c.int) -> c.int {
	return c.int(luaL_checkinteger(L, narg))
}

luaL_optstring :: proc "c" (L: ^State, narg: c.int, d: cstring) -> cstring {
	return luaL_optlstring(L, narg, d, nil)
}

lua_tostring :: proc "c" (L: ^State, idx: c.int) -> cstring {
	return lua_tolstring(L, idx, nil)
}

lua_getglobal :: #force_inline proc "c" (L: ^State, s: cstring) {
	lua_getfield(L, LUA_GLOBALSINDEX, s)
}

lua_setglobal :: #force_inline proc "c" (L: ^State, s: cstring) {
	lua_setfield(L, LUA_GLOBALSINDEX, s)
}

lua_newtable :: #force_inline proc "c" (L: ^State) {
	lua_createtable(L, 0, 0)
}

lua_pushliteral :: proc "c" (L: ^State, s: cstring) {
	lua_pushlstring(L, s, c.size_t(len(s)))
}

lua_strlen :: #force_inline proc "c" (L: ^State, i: c.int) -> c.size_t {
	return lua_objlen(L, i)
}

luaL_getn :: #force_inline proc "c" (L: ^State, i: c.int) -> int {
	return int(lua_objlen(L, i))
}

luaL_setn :: #force_inline proc "c" (L: ^State, i: c.int, j: int) {
	// No-op in Lua 5.1
}

lua_isthread :: #force_inline proc "c" (L: ^State, n: c.int) -> bool {
	return lua_type(L, n) == LUA_TTHREAD
}

lua_isnumber :: #force_inline proc "c" (L: ^State, n: c.int) -> bool {
	return _lua_isnumber(L, n) != 0
}

lua_isstring :: #force_inline proc "c" (L: ^State, n: c.int) -> bool {
	return _lua_isstring(L, n) != 0
}

lua_iscfunction :: #force_inline proc "c" (L: ^State, n: c.int) -> bool {
	return _lua_iscfunction(L, n) != 0
}

lua_isuserdata :: #force_inline proc "c" (L: ^State, n: c.int) -> bool {
	return _lua_isuserdata(L, n) != 0
}

lua_isfunction :: #force_inline proc "c" (L: ^State, n: c.int) -> bool {
	return lua_type(L, n) == LUA_TFUNCTION
}

lua_istable :: #force_inline proc "c" (L: ^State, n: c.int) -> bool {
	return lua_type(L, n) == LUA_TTABLE
}

lua_islightuserdata :: #force_inline proc "c" (L: ^State, n: c.int) -> bool {
	return lua_type(L, n) == LUA_TLIGHTUSERDATA
}

lua_isnil :: #force_inline proc "c" (L: ^State, n: c.int) -> bool {
	return lua_type(L, n) == LUA_TNIL
}

lua_isboolean :: #force_inline proc "c" (L: ^State, n: c.int) -> bool {
	return lua_type(L, n) == LUA_TBOOLEAN
}

lua_isnone :: #force_inline proc "c" (L: ^State, n: c.int) -> bool {
	return lua_type(L, n) == LUA_TNONE
}

lua_isnoneornil :: #force_inline proc "c" (L: ^State, n: c.int) -> bool {
	return lua_type(L, n) <= 0
}

luaL_optnumber :: #force_inline proc "c" (L: ^State, narg: c.int, def: Number) -> Number {
	return lua_isnoneornil(L, narg) ? def : luaL_checknumber(L, narg)
}

luaL_addchar :: #force_inline proc "c" (B: ^Buffer, ch: u8) {
	p := luaL_prepbuffer(B)
	p[0] = ch
	luaL_addsize(B, 1)
}

luaL_argcheck :: #force_inline proc "c" (L: ^State, cond: c.int, narg: c.int, extramsg: cstring) {
	if cond == 0 {
		luaL_argerror(L, narg, extramsg)
	}
}

luaL_addsize :: #force_inline proc "c" (B: ^Buffer, s: c.size_t) {
	B.p = ([^]u8)(mem.ptr_offset((^u8)(B.p), int(s)))
}

LUA_REGISTRYINDEX :: -10000
LUA_ENVIRONINDEX :: -10001
LUA_GLOBALSINDEX :: -10002

LUA_DIRSEP :: "/"
LUA_PATHSEP :: ";"
LUA_PATH_MARK :: "?"
LUA_EXECDIR :: "!"
LUA_IGMARK :: "-"

LUA_PATH_VAR :: "LUA_PATH"
LUA_CPATH_VAR :: "LUA_CPATH"

LUA_PATH_DEFAULT :: "./?.lua;/usr/local/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?/init.lua;/usr/local/lib/lua/5.1/?.lua;/usr/local/lib/lua/5.1/?/init.lua"
LUA_CPATH_DEFAULT :: "./?.so;/usr/local/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/loadall.so"

LUA_LOADLIBNAME :: "package"

RTLD_LAZY :: 1
RTLD_NOW :: 2

lua_upvalueindex :: #force_inline proc "c" (i: c.int) -> c.int {
	return LUA_GLOBALSINDEX - i
}

LUA_QL :: #force_inline proc(s: cstring) -> cstring {
	return s
}

LUA_TNONE :: -1
LUA_TNIL :: 0
LUA_TBOOLEAN :: 1
LUA_TLIGHTUSERDATA :: 2
LUA_TNUMBER :: 3
LUA_TSTRING :: 4
LUA_TTABLE :: 5
LUA_TFUNCTION :: 6
LUA_TUSERDATA :: 7
LUA_TTHREAD :: 8

// Lua Types
Number :: f64
Integer :: int

LUAL_BUFFERSIZE :: 8192

Buffer :: struct {
	p:      [^]u8,
	lvl:    c.int,
	L:      ^State,
	buffer: [LUAL_BUFFERSIZE]u8,
}

// Library registration struct
Reg :: struct {
	name: cstring,
	func: CFunction,
}

// Helper wrappers
pushcfunction :: #force_inline proc "c" (L: ^State, fn: CFunction) {
	lua_pushcclosure(L, fn, 0)
}

lua_pushcfunction :: #force_inline proc "c" (L: ^State, fn: CFunction) {
	lua_pushcclosure(L, fn, 0)
}
