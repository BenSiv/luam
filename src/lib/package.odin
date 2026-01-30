package lib

import "../lua"
import "base:runtime"
import "core:c"
import "core:strings"

@(private)
sentinel_val: c.int = 0
sentinel: rawptr = &sentinel_val

@(private)
LIBPREFIX :: "LOADLIB: "
POF :: "luaopen_"
LIB_FAIL :: "open"

ERRLIB :: 1
ERRFUNC :: 2

// Helper: Push concatenation of multiple strings onto stack
@(private)
push_concat :: proc "c" (L: ^lua.State, strs: ..cstring) {
	context = runtime.default_context()
	for s in strs {
		lua.lua_pushstring(L, s)
	}
	lua.lua_concat(L, c.int(len(strs)))
}

// Helper: Convert Odin string to cstring using temp allocator
// Must be called from a proc that has set context = runtime.default_context()
@(private)
to_cstr :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}

@(private)
readable :: proc "c" (filename: cstring) -> bool {
	f := lua.fopen(filename, "r")
	if f == nil {
		return false
	}
	lua.fclose(f)
	return true
}

@(private)
pushnexttemplate :: proc "c" (L: ^lua.State, path: cstring) -> cstring {
	context = runtime.default_context()
	if path == nil || (cast([^]u8)path)[0] == 0 do return nil

	p := cast([^]u8)path
	i := 0
	// Skip separators at the start
	for p[i] != 0 && p[i] == lua.LUA_PATHSEP[0] {
		i += 1
	}
	if p[i] == 0 {
		return nil
	}

	start := i
	// Find next separator
	for p[i] != 0 && p[i] != lua.LUA_PATHSEP[0] {
		i += 1
	}

	lua.lua_pushlstring(L, cast(cstring)&p[start], c.size_t(i - start))
	return p[i] == 0 ? nil : cast(cstring)&p[i + 1]
}

@(private)
findfile :: proc "c" (L: ^lua.State, name: cstring, pname: cstring) -> cstring {
	context = runtime.default_context()

	dot_name := lua.luaL_gsub(L, name, ".", lua.LUA_DIRSEP)
	lua.lua_getfield(L, lua.LUA_ENVIRONINDEX, pname)
	path := lua.lua_tostring(L, -1)
	if path == nil {
		lua.luaL_error(L, "package.%s must be a string", pname)
	}

	lua.lua_pushliteral(L, "") // error accumulator

	current_path := path
	for {
		next_path := pushnexttemplate(L, current_path)
		if next_path == nil {
			break
		}

		template := lua.lua_tostring(L, -1)
		filename := lua.luaL_gsub(L, template, lua.LUA_PATH_MARK, dot_name)
		lua.lua_remove(L, -2) // remove path template

		if readable(filename) {
			return filename
		}

		push_concat(L, "\n\tno file '", filename, "'")
		lua.lua_remove(L, -2) // remove filename
		lua.lua_concat(L, 2)

		if next_path == current_path do break // Avoid infinite loop
		current_path = next_path
	}

	return nil
}

@(private)
loaderror :: proc "c" (L: ^lua.State, filename: cstring) {
	lua.luaL_error(
		L,
		"error loading module '%s' from file '%s':\n\t%s",
		lua.lua_tostring(L, 1),
		filename,
		lua.lua_tostring(L, -1),
	)
}

@(private)
ll_unloadlib :: proc "c" (lib: rawptr) {
	lua.dlclose(lib)
}

@(private)
ll_load :: proc "c" (L: ^lua.State, path: cstring) -> rawptr {
	lib := lua.dlopen(path, lua.RTLD_NOW)
	if lib == nil {
		lua.lua_pushstring(L, lua.dlerror())
	}
	return lib
}

@(private)
ll_sym :: proc "c" (L: ^lua.State, lib: rawptr, sym: cstring) -> lua.CFunction {
	f := cast(lua.CFunction)lua.dlsym(lib, sym)
	if f == nil {
		lua.lua_pushstring(L, lua.dlerror())
	}
	return f
}

@(private)
ll_register :: proc "c" (L: ^lua.State, path: cstring) -> ^rawptr {
	push_concat(L, LIBPREFIX, path)
	lua.lua_gettable(L, lua.LUA_REGISTRYINDEX)
	if !lua.lua_isnil(L, -1) {
		return cast(^rawptr)lua.lua_touserdata(L, -1)
	} else {
		lua.lua_pop(L, 1)
		plib := cast(^rawptr)lua.lua_newuserdata(L, size_of(rawptr))
		plib^ = nil
		lua.luaL_getmetatable(L, "_LOADLIB")
		lua.lua_setmetatable(L, -2)
		push_concat(L, LIBPREFIX, path)
		lua.lua_pushvalue(L, -2)
		lua.lua_settable(L, lua.LUA_REGISTRYINDEX)
		return plib
	}
}

@(private)
gctm :: proc "c" (L: ^lua.State) -> c.int {
	lib := cast(^rawptr)lua.luaL_checkudata(L, 1, "_LOADLIB")
	if lib^ != nil {
		ll_unloadlib(lib^)
	}
	lib^ = nil
	return 0
}

@(private)
ll_loadfunc :: proc "c" (L: ^lua.State, path: cstring, sym: cstring) -> c.int {
	reg := ll_register(L, path)
	if reg^ == nil {
		reg^ = ll_load(L, path)
	}
	if reg^ == nil {
		return ERRLIB
	} else {
		f := ll_sym(L, reg^, sym)
		if f == nil {
			return ERRFUNC
		}
		lua.lua_pushcfunction(L, f)
		return 0
	}
}

ll_loadlib :: proc "c" (L: ^lua.State) -> c.int {
	path := lua.luaL_checkstring(L, 1)
	init := lua.luaL_checkstring(L, 2)
	stat := ll_loadfunc(L, path, init)
	if stat == 0 {
		return 1
	} else {
		lua.lua_pushnil(L)
		lua.lua_insert(L, -2)
		lua.lua_pushstring(L, (stat == ERRLIB) ? LIB_FAIL : "init")
		return 3
	}
}

@(private)
loader_preload :: proc "c" (L: ^lua.State) -> c.int {
	name := lua.luaL_checkstring(L, 1)
	lua.lua_getfield(L, lua.LUA_ENVIRONINDEX, "preload")
	if !lua.lua_istable(L, -1) {
		lua.luaL_error(L, "package.preload must be a table")
	}
	lua.lua_getfield(L, -1, name)
	if lua.lua_isnil(L, -1) {
		push_concat(L, "\n\tno field package.preload['", name, "']")
	}
	return 1
}

@(private)
loader_Lua :: proc "c" (L: ^lua.State) -> c.int {
	filename: cstring
	name := lua.luaL_checkstring(L, 1)
	filename = findfile(L, name, "path")
	if filename == nil {
		return 1
	}
	if lua.luaL_loadfile(L, filename) != 0 {
		loaderror(L, filename)
	}
	return 1
}

@(private)
mkfuncname :: proc "c" (L: ^lua.State, modname: cstring) -> cstring {
	context = runtime.default_context()
	// Strip any prefix up to and including the IGMARK
	s := strings.clone_from_cstring(modname, context.temp_allocator)
	mark := strings.index_any(s, lua.LUA_IGMARK)
	if mark != -1 {
		s = s[mark + 1:]
	}

	// Convert dots to underscores and prepend POF
	lua.luaL_gsub(L, to_cstr(s), ".", "_")
	push_concat(L, POF, lua.lua_tostring(L, -1))
	lua.lua_remove(L, -2) // remove gsub result
	return lua.lua_tostring(L, -1)
}

@(private)
loader_C :: proc "c" (L: ^lua.State) -> c.int {
	name := lua.luaL_checkstring(L, 1)
	filename := findfile(L, name, "cpath")
	if filename == nil {
		return 1
	}
	funcname := mkfuncname(L, name)
	if ll_loadfunc(L, filename, funcname) != 0 {
		loaderror(L, filename)
	}
	return 1
}

@(private)
loader_Croot :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	name := lua.luaL_checkstring(L, 1)
	s := strings.clone_from_cstring(name, context.temp_allocator)
	p := strings.index_byte(s, '.')
	if p == -1 {
		return 0
	}

	root_name := to_cstr(s[:p])
	lua.lua_pushstring(L, root_name)
	filename := findfile(L, root_name, "cpath")
	if filename == nil {
		return 1
	}

	funcname := mkfuncname(L, name)
	stat := ll_loadfunc(L, filename, funcname)
	if stat != 0 {
		if stat != ERRFUNC {
			loaderror(L, filename)
		}
		push_concat(L, "\n\tno module '", name, "' in file '", filename, "'")
		return 1
	}
	return 1
}

ll_require :: proc "c" (L: ^lua.State) -> c.int {
	name := lua.luaL_checkstring(L, 1)
	lua.lua_settop(L, 1)
	lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, "_LOADED")
	lua.lua_getfield(L, 2, name)
	if lua.lua_toboolean(L, -1) != 0 {
		if lua.lua_touserdata(L, -1) == sentinel {
			lua.luaL_error(L, "loop or previous error loading module '%s'", name)
		}
		return 1
	}

	lua.lua_getfield(L, lua.LUA_ENVIRONINDEX, "loaders")
	if !lua.lua_istable(L, -1) {
		lua.luaL_error(L, "package.loaders must be a table")
	}

	lua.lua_pushliteral(L, "") // error accumulator
	for i: c.int = 1;; i += 1 {
		lua.lua_rawgeti(L, -2, i)
		if lua.lua_isnil(L, -1) {
			lua.luaL_error(L, "module '%s' not found:%s", name, lua.lua_tostring(L, -2))
		}
		lua.lua_pushstring(L, name)
		lua.lua_call(L, 1, 1)
		if lua.lua_isfunction(L, -1) {
			break
		} else if lua.lua_isstring(L, -1) {
			lua.lua_concat(L, 2)
		} else {
			lua.lua_pop(L, 1)
		}
	}

	lua.lua_pushlightuserdata(L, sentinel)
	lua.lua_setfield(L, 2, name)
	lua.lua_pushstring(L, name)
	lua.lua_call(L, 1, 1)

	if !lua.lua_isnil(L, -1) {
		lua.lua_setfield(L, 2, name)
	}

	lua.lua_getfield(L, 2, name)
	if lua.lua_touserdata(L, -1) == sentinel {
		lua.lua_pushboolean(L, 1)
		lua.lua_pushvalue(L, -1)
		lua.lua_setfield(L, 2, name)
	}
	return 1
}

@(private)
setfenv :: proc "c" (L: ^lua.State) {
	ar: lua.Debug
	if lua.lua_getstack(L, 1, &ar) == 0 ||
	   lua.lua_getinfo(L, "f", &ar) == 0 ||
	   lua.lua_iscfunction(L, -1) {
		lua.luaL_error(L, "module not called from a Lua function")
	}
	lua.lua_pushvalue(L, -2)
	lua.lua_setfenv(L, -2)
	lua.lua_pop(L, 1)
}

@(private)
dooptions :: proc "c" (L: ^lua.State, n: c.int) {
	for i: c.int = 2; i <= n; i += 1 {
		lua.lua_pushvalue(L, i)
		lua.lua_pushvalue(L, -2)
		lua.lua_call(L, 1, 0)
	}
}

@(private)
modinit :: proc "c" (L: ^lua.State, modname: cstring) {
	context = runtime.default_context()
	lua.lua_pushvalue(L, -1)
	lua.lua_setfield(L, -2, "_M")
	lua.lua_pushstring(L, modname)
	lua.lua_setfield(L, -2, "_NAME")

	s := strings.clone_from_cstring(modname, context.temp_allocator)
	dot := strings.last_index_byte(s, '.')
	if dot == -1 {
		lua.lua_pushliteral(L, "")
	} else {
		lua.lua_pushlstring(L, cast(cstring)raw_data(s), c.size_t(dot + 1))
	}
	lua.lua_setfield(L, -2, "_PACKAGE")
}

ll_module :: proc "c" (L: ^lua.State) -> c.int {
	modname := lua.luaL_checkstring(L, 1)
	loaded := lua.lua_gettop(L) + 1
	lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, "_LOADED")
	lua.lua_getfield(L, loaded, modname)
	if !lua.lua_istable(L, -1) {
		lua.lua_pop(L, 1)
		if lua.luaL_findtable(L, lua.LUA_GLOBALSINDEX, modname, 1) != nil {
			lua.luaL_error(L, "name conflict for module '%s'", modname)
		}
		lua.lua_pushvalue(L, -1)
		lua.lua_setfield(L, loaded, modname)
	}

	lua.lua_getfield(L, -1, "_NAME")
	if lua.lua_isnil(L, -1) {
		lua.lua_pop(L, 1)
		modinit(L, modname)
	} else {
		lua.lua_pop(L, 1)
	}

	lua.lua_pushvalue(L, -1)
	setfenv(L)
	dooptions(L, loaded - 1)
	return 0
}

ll_seeall :: proc "c" (L: ^lua.State) -> c.int {
	lua.luaL_checktype(L, 1, lua.LUA_TTABLE)
	if lua.lua_getmetatable(L, 1) == 0 {
		lua.lua_createtable(L, 0, 1)
		lua.lua_pushvalue(L, -1)
		lua.lua_setmetatable(L, 1)
	}
	lua.lua_pushvalue(L, lua.LUA_GLOBALSINDEX)
	lua.lua_setfield(L, -2, "__index")
	return 0
}

@(private)
setpath :: proc "c" (L: ^lua.State, fieldname: cstring, envname: cstring, def: cstring) {
	context = runtime.default_context()
	path := lua.getenv(envname)
	if path == nil {
		lua.lua_pushstring(L, def)
	} else {
		auxmark := "\x01"
		path_sep_sep := strings.concatenate(
			{lua.LUA_PATHSEP, lua.LUA_PATHSEP},
			context.temp_allocator,
		)
		path_aux_sep := strings.concatenate(
			{lua.LUA_PATHSEP, auxmark, lua.LUA_PATHSEP},
			context.temp_allocator,
		)

		res := lua.luaL_gsub(L, path, to_cstr(path_sep_sep), to_cstr(path_aux_sep))
		lua.luaL_gsub(L, res, to_cstr(auxmark), def)
		lua.lua_remove(L, -2)
	}
	lua.lua_setfield(L, -2, fieldname)
}

open_package :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()

	lua.luaL_newmetatable(L, "_LOADLIB")
	lua.lua_pushcfunction(L, gctm)
	lua.lua_setfield(L, -2, "__gc")

	pk_funcs := [?]lua.Reg{{"loadlib", ll_loadlib}, {"seeall", ll_seeall}, {nil, nil}}

	lua.luaL_register(L, lua.LUA_LOADLIBNAME, &pk_funcs[0])

	lua.lua_pushvalue(L, -1)
	lua.lua_replace(L, lua.LUA_ENVIRONINDEX)

	loaders := [?]lua.CFunction{loader_preload, loader_Lua, loader_C, loader_Croot, nil}

	lua.lua_createtable(L, 4, 0)
	for f, i in loaders {
		if f == nil do break
		lua.lua_pushcfunction(L, f)
		lua.lua_rawseti(L, -2, c.int(i + 1))
	}

	lua.lua_pushvalue(L, -1)
	lua.lua_setfield(L, -3, "searchers")
	lua.lua_setfield(L, -2, "loaders")

	setpath(L, "path", lua.LUA_PATH_VAR, lua.LUA_PATH_DEFAULT)
	setpath(L, "cpath", lua.LUA_CPATH_VAR, lua.LUA_CPATH_DEFAULT)

	config := strings.concatenate(
		{
			lua.LUA_DIRSEP,
			"\n",
			lua.LUA_PATHSEP,
			"\n",
			lua.LUA_PATH_MARK,
			"\n",
			lua.LUA_EXECDIR,
			"\n",
			lua.LUA_IGMARK,
		},
		context.temp_allocator,
	)
	lua.lua_pushstring(L, to_cstr(config))

	lua.lua_setfield(L, -2, "config")

	lua.luaL_findtable(L, lua.LUA_REGISTRYINDEX, "_LOADED", 2)
	lua.lua_setfield(L, -2, "loaded")

	lua.lua_newtable(L)
	lua.lua_setfield(L, -2, "preload")

	ll_funcs := [?]lua.Reg{{"module", ll_module}, {"require", ll_require}, {nil, nil}}

	lua.lua_pushvalue(L, lua.LUA_GLOBALSINDEX)
	lua.luaL_register(L, nil, &ll_funcs[0])
	lua.lua_pop(L, 1)

	return 1
}
