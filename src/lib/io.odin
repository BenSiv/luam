package lib

import "../core"
import "../lua"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:os"

LUA_FILEHANDLE :: "FILE*"

File :: struct {
	f: os.Handle,
}

io_funcs := [?]lua.Reg {
	{"close", io_close},
	{"flush", io_flush},
	{"input", io_input},
	{"lines", io_lines},
	{"open", io_open},
	{"output", io_output},
	{"popen", io_popen},
	{"read", io_read},
	{"tmpfile", io_tmpfile},
	{"type", io_type},
	{"write", io_write},
	{nil, nil},
}

flib_funcs := [?]lua.Reg {
	{"close", f_close},
	{"flush", f_flush},
	{"lines", f_lines},
	{"read", f_read},
	{"seek", f_seek},
	{"setvbuf", f_setvbuf},
	{"write", f_write},
	{"__gc", f_gc},
	{"__tostring", f_tostring},
	{nil, nil},
}

flib_meta := [?]lua.Reg{{"__gc", f_gc}, {"__tostring", f_tostring}, {nil, nil}}

createmeta :: proc "c" (L: ^lua.State) {
	context = runtime.default_context()
	lua.luaL_newmetatable(L, LUA_FILEHANDLE)
	lua.luaL_register(L, nil, &flib_meta[0])
}

createstdfile :: proc "c" (L: ^lua.State, f: rawptr, k: c.int, fname: cstring) {
	newfile(L)^ = f
	if k > 0 {
		lua.lua_pushvalue(L, -1)
		lua.lua_rawseti(L, lua.LUA_ENVIRONINDEX, k)
	}
	lua.lua_pushvalue(L, -2) // copy environment
	lua.lua_setfenv(L, -2)
	lua.lua_setfield(L, -3, fname)
}

newfile :: proc "c" (L: ^lua.State) -> ^rawptr {
	p := lua.lua_newuserdata(L, size_of(rawptr))
	lua.luaL_getmetatable(L, LUA_FILEHANDLE)
	lua.lua_setmetatable(L, -2)
	return cast(^rawptr)p
}

open_io :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	createmeta(L)
	// create (and set) environment
	lua.lua_createtable(L, 0, 2)
	lua.lua_pushvalue(L, -1)
	lua.lua_replace(L, lua.LUA_ENVIRONINDEX)
	// register functions
	lua.luaL_register(L, "io", &io_funcs[0])
	// set default input/output
	// createstdfile(L, stdin, 1, "stdin")
	// createstdfile(L, stdout, 2, "stdout")
	// createstdfile(L, stderr, 0, "stderr")
	return 1
}

// Stub implementations
io_close :: proc "c" (L: ^lua.State) -> c.int {return 0}
io_flush :: proc "c" (L: ^lua.State) -> c.int {return 0}
io_input :: proc "c" (L: ^lua.State) -> c.int {return 0}
io_lines :: proc "c" (L: ^lua.State) -> c.int {return 0}
io_open :: proc "c" (L: ^lua.State) -> c.int {return 0}
io_output :: proc "c" (L: ^lua.State) -> c.int {return 0}
io_popen :: proc "c" (L: ^lua.State) -> c.int {return 0}
io_read :: proc "c" (L: ^lua.State) -> c.int {return 0}
io_tmpfile :: proc "c" (L: ^lua.State) -> c.int {return 0}
io_type :: proc "c" (L: ^lua.State) -> c.int {return 0}
io_write :: proc "c" (L: ^lua.State) -> c.int {return 0}

f_close :: proc "c" (L: ^lua.State) -> c.int {return 0}
f_flush :: proc "c" (L: ^lua.State) -> c.int {return 0}
f_lines :: proc "c" (L: ^lua.State) -> c.int {return 0}
f_read :: proc "c" (L: ^lua.State) -> c.int {return 0}
f_seek :: proc "c" (L: ^lua.State) -> c.int {return 0}
f_setvbuf :: proc "c" (L: ^lua.State) -> c.int {return 0}
f_write :: proc "c" (L: ^lua.State) -> c.int {return 0}
f_gc :: proc "c" (L: ^lua.State) -> c.int {return 0}
f_tostring :: proc "c" (L: ^lua.State) -> c.int {return 0}
