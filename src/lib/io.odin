package lib

import "../lua"
import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:mem"
import "core:strings"

// IO_INPUT / IO_OUTPUT indices for function environment
IO_INPUT :: 1
IO_OUTPUT :: 2

fnames := [?]cstring{"input", "output"}

io_pushresult :: proc "c" (L: ^lua.State, i: c.int, filename: cstring) -> c.int {
	context = runtime.default_context()
	en := libc.errno()^
	if i != 0 {
		lua.lua_pushboolean(L, 1)
		return 1
	} else {
		lua.lua_pushnil(L)
		if filename != nil {
			lua.lua_pushfstring(L, "%s: %s", filename, lua.strerror(en))
		} else {
			lua.lua_pushstring(L, lua.strerror(en))
		}
		lua.lua_pushinteger(L, lua.Integer(en))
		return 3
	}
}

fileerror :: proc "c" (L: ^lua.State, arg: c.int, filename: cstring) {
	context = runtime.default_context()
	lua.lua_pushfstring(L, "%s: %s", filename, lua.strerror(libc.errno()^))
	lua.luaL_argerror(L, arg, lua.lua_tostring(L, -1))
}

tofilep :: #force_inline proc "c" (L: ^lua.State) -> ^rawptr {
	return (^rawptr)(lua.luaL_checkudata(L, 1, lua.LUA_FILEHANDLE))
}

tofile :: proc "c" (L: ^lua.State) -> rawptr {
	f := tofilep(L)^
	if f == nil {
		lua.luaL_error(L, "attempt to use a closed file")
	}
	return f
}

newfile :: proc "c" (L: ^lua.State) -> ^rawptr {
	pf := (^rawptr)(lua.lua_newuserdata(L, size_of(rawptr)))
	pf^ = nil // closed
	lua.luaL_getmetatable(L, lua.LUA_FILEHANDLE)
	lua.lua_setmetatable(L, -2)
	return pf
}

io_type :: proc "c" (L: ^lua.State) -> c.int {
	lua.luaL_checkany(L, 1)
	ud := lua.lua_touserdata(L, 1)
	lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, lua.LUA_FILEHANDLE)
	if ud == nil || lua.lua_getmetatable(L, 1) == 0 || lua.lua_rawequal(L, -2, -1) == 0 {
		lua.lua_pushnil(L)
	} else if (^rawptr)(ud)^ == nil {
		lua.lua_pushliteral(L, "closed file")
	} else {
		lua.lua_pushliteral(L, "file")
	}
	return 1
}

io_noclose :: proc "c" (L: ^lua.State) -> c.int {
	lua.lua_pushnil(L)
	lua.lua_pushliteral(L, "cannot close standard file")
	return 2
}

io_pclose :: proc "c" (L: ^lua.State) -> c.int {
	p := tofilep(L)
	ok := lua.pclose(p^)
	p^ = nil
	return io_pushresult(L, c.int(ok != -1 ? 1 : 0), nil)
}

io_fclose :: proc "c" (L: ^lua.State) -> c.int {
	p := tofilep(L)
	ok := lua.fclose(p^)
	p^ = nil
	return io_pushresult(L, c.int(ok == 0 ? 1 : 0), nil)
}

aux_close :: proc "c" (L: ^lua.State) -> c.int {
	lua.lua_getfenv(L, 1)
	lua.lua_getfield(L, -1, "__close")
	lua.lua_pushvalue(L, 1) // arg 1: file handle
	lua.lua_call(L, 1, lua.LUA_MULTRET)
	return lua.lua_gettop(L) - 1
}

io_close :: proc "c" (L: ^lua.State) -> c.int {
	if lua.lua_isnone(L, 1) {
		lua.lua_rawgeti(L, lua.LUA_ENVIRONINDEX, IO_OUTPUT)
	}
	tofile(L)
	return aux_close(L)
}

io_gc :: proc "c" (L: ^lua.State) -> c.int {
	f := tofilep(L)^
	if f != nil {
		aux_close(L)
	}
	return 0
}

io_tostring :: proc "c" (L: ^lua.State) -> c.int {
	f := tofilep(L)^
	if f == nil {
		lua.lua_pushliteral(L, "file (closed)")
	} else {
		lua.lua_pushfstring(L, "file (%p)", f)
	}
	return 1
}

io_open :: proc "c" (L: ^lua.State) -> c.int {
	filename := lua.luaL_checkstring(L, 1)
	mode := lua.luaL_optstring(L, 2, "r")
	pf := newfile(L)
	pf^ = lua.fopen(filename, mode)
	return (pf^ == nil) ? io_pushresult(L, 0, filename) : 1
}

io_popen :: proc "c" (L: ^lua.State) -> c.int {
	filename := lua.luaL_checkstring(L, 1)
	mode := lua.luaL_optstring(L, 2, "r")
	pf := newfile(L)
	pf^ = lua.popen(filename, mode)
	return (pf^ == nil) ? io_pushresult(L, 0, filename) : 1
}

io_tmpfile :: proc "c" (L: ^lua.State) -> c.int {
	pf := newfile(L)
	pf^ = lua.tmpfile()
	return (pf^ == nil) ? io_pushresult(L, 0, nil) : 1
}

getiofile :: proc "c" (L: ^lua.State, findex: c.int) -> rawptr {
	lua.lua_rawgeti(L, lua.LUA_ENVIRONINDEX, findex)
	f := (^rawptr)(lua.lua_touserdata(L, -1))^
	if f == nil {
		lua.luaL_error(L, "standard %s file is closed", fnames[findex - 1])
	}
	return f
}

g_iofile :: proc "c" (L: ^lua.State, f: c.int, mode: cstring) -> c.int {
	if lua.lua_isnoneornil(L, 1) == false {
		filename := lua.lua_tostring(L, 1)
		if filename != nil {
			pf := newfile(L)
			pf^ = lua.fopen(filename, mode)
			if pf^ == nil {
				fileerror(L, 1, filename)
			}
		} else {
			tofile(L)
			lua.lua_pushvalue(L, 1)
		}
		lua.lua_rawseti(L, lua.LUA_ENVIRONINDEX, f)
	}
	lua.lua_rawgeti(L, lua.LUA_ENVIRONINDEX, f)
	return 1
}

io_input :: proc "c" (L: ^lua.State) -> c.int {return g_iofile(L, IO_INPUT, "r")}
io_output :: proc "c" (L: ^lua.State) -> c.int {return g_iofile(L, IO_OUTPUT, "w")}

// --- Read/Write Implementation ---

read_number :: proc "c" (L: ^lua.State, f: rawptr) -> c.int {
	d: lua.Number
	if lua.fscanf(f, lua.LUA_NUMBER_SCAN, &d) == 1 {
		lua.lua_pushnumber(L, d)
		return 1
	} else {
		lua.lua_pushnil(L)
		return 0
	}
}

test_eof :: proc "c" (L: ^lua.State, f: rawptr) -> c.int {
	ch := lua.getc(f)
	lua.ungetc(ch, f)
	lua.lua_pushlstring(L, nil, 0)
	return c.int(ch != -1 ? 1 : 0)
}

read_line :: proc "c" (L: ^lua.State, f: rawptr) -> c.int {
	b: lua.Buffer
	lua.luaL_buffinit(L, &b)
	for {
		p := lua.luaL_prepbuffer(&b)
		if lua.fgets(p, lua.LUAL_BUFFERSIZE, f) == nil {
			lua.luaL_pushresult(&b)
			return c.int(lua.lua_objlen(L, -1) > 0 ? 1 : 0)
		}
		l := c.size_t(libc.strlen(cstring(&p[0])))
		if l == 0 || p[l - 1] != '\n' {
			lua.luaL_addsize(&b, l)
		} else {
			lua.luaL_addsize(&b, l - 1)
			lua.luaL_pushresult(&b)
			return 1
		}
	}
}

read_chars :: proc "c" (L: ^lua.State, f: rawptr, n: c.size_t) -> c.int {
	n := n
	b: lua.Buffer
	lua.luaL_buffinit(L, &b)
	rlen: c.size_t = lua.LUAL_BUFFERSIZE
	nr: c.size_t = 0
	for {
		p := lua.luaL_prepbuffer(&b)
		cur_rlen := rlen
		if cur_rlen > n do cur_rlen = n
		nr = lua.fread(p, 1, cur_rlen, f)
		lua.luaL_addsize(&b, nr)
		n -= nr
		if !(n > 0 && nr == cur_rlen) do break
	}
	lua.luaL_pushresult(&b)
	return c.int(n == 0 || lua.lua_objlen(L, -1) > 0 ? 1 : 0)
}

g_read :: proc "c" (L: ^lua.State, f: rawptr, first: c.int) -> c.int {
	nargs := lua.lua_gettop(L) - 1
	success: c.int
	n: c.int
	lua.clearerr(f)
	if nargs == 0 {
		success = read_line(L, f)
		n = first + 1
	} else {
		lua.luaL_checkstack(L, nargs + 20, "too many arguments")
		success = 1
		for n = first; nargs > 0 && success != 0; {
			nargs -= 1
			if lua.lua_type(L, n) == lua.LUA_TNUMBER {
				l := (c.size_t)(lua.lua_tointeger(L, n))
				success = (l == 0) ? test_eof(L, f) : read_chars(L, f, l)
			} else {
				p := ([^]u8)(lua.lua_tostring(L, n))
				lua.luaL_argcheck(L, c.int(p != nil && p[0] == '*' ? 1 : 0), n, "invalid option")
				switch p[1] {
				case 'n':
					success = read_number(L, f)
				case 'l':
					success = read_line(L, f)
				case 'a':
					read_chars(L, f, ~((c.size_t)(0)))
					success = 1
				case:
					return lua.luaL_argerror(L, n, "invalid format")
				}
			}
			n += 1
		}
	}
	if lua.ferror(f) != 0 {
		return io_pushresult(L, 0, nil)
	}
	if success == 0 {
		lua.lua_pop(L, 1)
		lua.lua_pushnil(L)
	}
	return n - first
}

io_read :: proc "c" (L: ^lua.State) -> c.int {
	if lua.lua_type(L, 1) == lua.LUA_TUSERDATA {
		return g_read(L, tofile(L), 2)
	} else {
		return g_read(L, getiofile(L, IO_INPUT), 1)
	}
}

f_read :: proc "c" (L: ^lua.State) -> c.int {return g_read(L, tofile(L), 2)}

io_readline :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	f := (^rawptr)(lua.lua_touserdata(L, lua.lua_upvalueindex(1)))^
	if f == nil {
		lua.luaL_error(L, "file is already closed")
	}
	success := read_line(L, f)
	if lua.ferror(f) != 0 {
		return lua.luaL_error(L, "%s", lua.strerror(libc.errno()^))
	}
	if success != 0 {
		return 1
	} else {
		if lua.lua_toboolean(L, lua.lua_upvalueindex(2)) != 0 {
			lua.lua_settop(L, 0)
			lua.lua_pushvalue(L, lua.lua_upvalueindex(1))
			aux_close(L)
		}
		return 0
	}
}

g_write :: proc "c" (L: ^lua.State, f: rawptr, arg: c.int) -> c.int {
	nargs := lua.lua_gettop(L) - 1
	status := true
	arg := arg
	for nargs > 0 {
		nargs -= 1
		if lua.lua_type(L, arg) == lua.LUA_TNUMBER {
			status = status && (lua.fprintf(f, lua.LUA_NUMBER_FMT, lua.lua_tonumber(L, arg)) > 0)
		} else {
			l: c.size_t
			s := lua.luaL_checklstring(L, arg, &l)
			status = status && (lua.fwrite((rawptr)(s), 1, l, f) == l)
		}
		arg += 1
	}
	return io_pushresult(L, c.int(status ? 1 : 0), nil)
}

io_write :: proc "c" (L: ^lua.State) -> c.int {
	if lua.lua_type(L, 1) == lua.LUA_TUSERDATA {
		return g_write(L, tofile(L), 2)
	} else {
		return g_write(L, getiofile(L, IO_OUTPUT), 1)
	}
}

f_write :: proc "c" (L: ^lua.State) -> c.int {return g_write(L, tofile(L), 2)}

f_seek :: proc "c" (L: ^lua.State) -> c.int {
	mode := [?]c.int{libc.SEEK_SET, libc.SEEK_CUR, libc.SEEK_END}
	modenames := [?]cstring{"set", "cur", "end", nil}
	f := tofile(L)
	op := lua.luaL_checkoption(L, 2, "cur", &modenames[0])
	offset := (c.long)(lua.luaL_optinteger(L, 3, 0))
	res := lua.fseek(f, offset, mode[op])
	if res != 0 {
		return io_pushresult(L, 0, nil)
	} else {
		lua.lua_pushinteger(L, (lua.Integer)(lua.ftell(f)))
		return 1
	}
}

f_setvbuf :: proc "c" (L: ^lua.State) -> c.int {
	mode := [?]c.int{libc._IONBF, libc._IOFBF, libc._IOLBF}
	modenames := [?]cstring{"no", "full", "line", nil}
	f := tofile(L)
	op := lua.luaL_checkoption(L, 2, nil, &modenames[0])
	sz := (c.size_t)(lua.luaL_optinteger(L, 3, lua.LUAL_BUFFERSIZE))
	res := lua.setvbuf(f, nil, mode[op], sz)
	return io_pushresult(L, c.int(res == 0 ? 1 : 0), nil)
}

io_flush :: proc "c" (L: ^lua.State) -> c.int {
	f: rawptr
	if lua.lua_type(L, 1) == lua.LUA_TUSERDATA {
		f = tofile(L)
	} else {
		f = getiofile(L, IO_OUTPUT)
	}
	return io_pushresult(L, c.int(lua.fflush(f) == 0 ? 1 : 0), nil)
}

f_flush :: proc "c" (L: ^lua.State) -> c.int {
	return io_pushresult(L, c.int(lua.fflush(tofile(L)) == 0 ? 1 : 0), nil)
}

aux_lines :: proc "c" (L: ^lua.State, idx: c.int, toclose: bool) {
	lua.lua_pushvalue(L, idx)
	lua.lua_pushboolean(L, c.int(toclose ? 1 : 0))
	lua.lua_pushcclosure(L, io_readline, 2)
}

f_lines :: proc "c" (L: ^lua.State) -> c.int {
	tofile(L)
	aux_lines(L, 1, false)
	return 1
}

io_lines :: proc "c" (L: ^lua.State) -> c.int {
	if lua.lua_isnoneornil(L, 1) {
		lua.lua_rawgeti(L, lua.LUA_ENVIRONINDEX, IO_INPUT)
		return f_lines(L)
	} else if lua.lua_type(L, 1) == lua.LUA_TUSERDATA {
		return f_lines(L)
	} else {
		filename := lua.luaL_checkstring(L, 1)
		pf := newfile(L)
		pf^ = lua.fopen(filename, "r")
		if pf^ == nil {
			fileerror(L, 1, filename)
		}
		aux_lines(L, lua.lua_gettop(L), true)
		return 1
	}
}

// --- Registration ---

iolib := [?]lua.Reg {
	{"close", io_close},
	{"flush", io_flush},
	{"input", io_input},
	{"lines", io_lines},
	{"open", io_open},
	{"output", io_output},
	{"popen", io_popen},
	{"read", io_read},
	{"seek", f_seek},
	{"setvbuf", f_setvbuf},
	{"tmpfile", io_tmpfile},
	{"type", io_type},
	{"write", io_write},
	{nil, nil},
}

flib_meta := [?]lua.Reg{{"__gc", io_gc}, {"__tostring", io_tostring}, {nil, nil}}

createmeta :: proc "c" (L: ^lua.State) {
	lua.luaL_newmetatable(L, lua.LUA_FILEHANDLE)
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

newfenv :: proc "c" (L: ^lua.State, cls: lua.CFunction) {
	lua.lua_createtable(L, 0, 1)
	lua.lua_pushcfunction(L, cls)
	lua.lua_setfield(L, -2, "__close")
}

open_io :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	createmeta(L)
	newfenv(L, io_fclose)
	lua.lua_replace(L, lua.LUA_ENVIRONINDEX)
	lua.luaL_register(L, "io", &iolib[0])

	newfenv(L, io_noclose)
	createstdfile(L, lua.luaL_get_stdin(), IO_INPUT, "stdin")
	createstdfile(L, lua.luaL_get_stdout(), IO_OUTPUT, "stdout")
	createstdfile(L, lua.luaL_get_stderr(), 0, "stderr")
	lua.lua_pop(L, 1) // pop env

	lua.lua_getfield(L, -1, "popen")
	newfenv(L, io_pclose)
	lua.lua_setfenv(L, -2)
	lua.lua_pop(L, 1) // pop popen

	return 1
}
