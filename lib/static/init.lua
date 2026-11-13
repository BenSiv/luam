
-- The author disclaims copyright to this source code.

-- The C compiler used to compile and link the generated C source file.
CC = os.getenv("CC")
if CC == nil then
	CC = "cc"
end
-- The nm used to determine whether a library is liblua or a Lua binary module.
NM = os.getenv("NM")
if NM == nil then
	NM = "nm"
end

function file_exists(name)
	file = io.open(name, "r")
	if file != nil then
		io.close(file)
		return true
	end
	return false
end

-- Run a shell command, wait for it to finish, and return a string containing stdout.
function shellout(command)
	-- Try popen if available
	if io.popen != nil then
		ok, file = pcall(io.popen, command)
		if ok and file != nil then
			stdout = io.read(file, "*all")
			io.close(file)
			return stdout
		end
	end

	-- Fallback to os.execute and temp file
	tmpfile = os.tmpname()
	cmd = command .. " > " .. tmpfile
	if os.execute(cmd) == 0 then
		file = io.open(tmpfile, "r")
		if file != nil then
			stdout = io.read(file, "*all")
			io.close(file)
			os.remove(tmpfile)
			return stdout
		end
	end
	os.remove(tmpfile)
	return nil
end

-- Use execute() when stdout isn't needed instead of shellout() because io.popen() does 
-- not return the status code in Lua 5.1.
function execute(cmd)
	ok = os.execute(cmd)
	return (ok == true or ok == 0)
end

-- Return a comma separated hex string suitable for a C array definition.
function string_to_c_hex_literal(chars)
	if #chars == 0 then
		return "0x00"
	end
	hex = {}
	for idx = 1, #chars do
		table.insert(hex, string.format("0x%02x", string.byte(chars, idx)))
	end
	return table.concat(hex, ", ")
end
assert(string_to_c_hex_literal("hello") == "0x68, 0x65, 0x6c, 0x6c, 0x6f")

-- Strip the directory from a filename.
function basename(path)
	name = string.gsub(path, "(.*[\\/])(.*)", "%2")
	return name
end
assert(basename("/path/to/file.lua") == "file.lua")
assert(basename("C:\\path\\to\\file.lua") == "file.lua")

function is_source_file(extension)
	return
		-- Source file.
		extension == "lua" or
		-- Precompiled chunk.
		extension == "luac"
end

function is_binary_library(extension)
	return 
		-- Object file.
		extension == "o" or 
		-- Static library.
		extension == "a" or 
		-- Shared library.
		extension == "so" or
		-- Mach-O dynamic library.
		extension == "dylib"
end

-- Required Lua source files.
lua_source_files = {}
-- Libraries for required Lua binary modules.
module_library_files = {}
module_link_libraries = {}
-- Libraries other than Lua binary modules, including liblua.
dep_library_files = {}
-- Additional arguments are passed to the C compiler.
other_arguments = {}
-- Get the operating system name.
uname_output = shellout("uname -s")
if uname_output == nil then
	uname_output = "Unknown"
end
UNAME = string.match(uname_output, "%a+")
if UNAME == nil then
	UNAME = "Unknown"
end
link_with_libdl = ""
-- Parse command line arguments. main.lua must be the first argument. Static libraries are 
-- passed to the compiler in the order they appear and may be interspersed with arguments to 
-- the compiler. Arguments to the compiler are passed to the compiler in the order they 
-- appear.
for i, name in ipairs(arg) do
	extension = string.match(name, "%.(%a+)$")
	if i == 1 or (is_source_file(extension) or is_binary_library(extension)) then
		if not file_exists(name) then
			io.write(io.stderr, "file does not exist: " .. name .. "\n")
			os.exit(1)
		end

		info = {}
		info.path = name
		info.basename = basename(info.path)
		info.basename_noextension = string.match(info.basename, "(.+)%.")
		if info.basename_noextension == nil then
			info.basename_noextension = info.basename
		end
		-- Handle the common case of "./path/to/file.lua".
		-- This won't work in all cases.
		info.dotpath = string.gsub(info.path, "^%.%/", "")
		info.dotpath = string.gsub(info.dotpath, "[\\/]", ".")
		info.dotpath_noextension = string.match(info.dotpath, "(.+)%.")
		if info.dotpath_noextension == nil then
			info.dotpath_noextension = info.dotpath
		end
		info.dotpath_underscore = string.gsub(info.dotpath_noextension, "[.-]", "_")

		if i == 1 or is_source_file(extension) then
			table.insert(lua_source_files, info)
		elseif is_binary_library(extension) then
			-- The library is either a Lua module or a library dependency.
			nmout = shellout(NM .. " " .. info.path)
			if nmout == nil then
				io.write(io.stderr, "nm not found\n")
				os.exit(1)
			end
			is_module = false
			if string.find(nmout, "T _?luaL_newstate") != nil then
				if string.find(nmout, "U _?dlopen") != nil then
					if UNAME == "Linux" or UNAME == "SunOS" or UNAME == "Darwin" then
						-- Link with libdl because liblua was built with support loading 
						-- shared objects and the operating system depends on it.
						link_with_libdl = "-ldl"
					end
				end
			else
				for luaopen in string.gmatch(nmout, "[^dD] _?luaopen_([%a%p%d]+)") do
					modinfo = {}
					modinfo.path = info.path
					modinfo.dotpath_underscore = luaopen
					modinfo.dotpath = string.gsub(modinfo.dotpath_underscore, "_", ".")
					modinfo.dotpath_noextension = modinfo.dotpath
					is_module = true
					table.insert(module_library_files, modinfo)
				end
			end
			if is_module then
				table.insert(module_link_libraries, info.path)
			else
				table.insert(dep_library_files, info.path)
			end
		end
	else
		-- Forward the remaining arguments to the C compiler.
		table.insert(other_arguments, name)
	end
end

if #lua_source_files == 0 then
	version = "0.0.12"
	print("static " .. version)
	print("""
usage: static main.lua[1] require.lua[2] liblua.a[3] library.a[4] -I/include/lua[5] [6]
  [1]: The entry point to the Lua program
  [2]: One or more required Lua source files
  [3]: The path to the Lua interpreter static library
  [4]: One or more static libraries for a required Lua binary module
  [5]: The path to the directory containing lua.h
  [6]: Additional arguments are passed to the C compiler""")
	os.exit(1)
end

-- Warn (not fail the build) about a bare function defined in exactly
-- one bundled file but called, bare, from a different one -- the
-- pattern that made dkjson's own internal `replace` helper silently
-- collide with an unrelated same-named global elsewhere in the bundle,
-- back when a bare function statement wrote a real global instead of a
-- local (see luam/doc/changelog.md). Now that the parser gives a bare
-- `function name()` the same genuine-local treatment as `name = value`,
-- this class of bug can't happen silently any more -- the bare name in
-- the defining file is never visible to a different file at all, so a
-- cross-file reference like this fails loudly (an unresolved global,
-- `nil` at call time) instead of silently clobbering something. This
-- is a text-pattern heuristic over a dynamic language, not a sound
-- analysis -- it can't see a function reached via _G["name"], stored
-- in a table and called indirectly, or produced by load() at runtime,
-- and something matching the surface shape here could still be a
-- legitimate, safe pattern this doesn't understand. A hard build
-- failure on a heuristic that can be wrong in either direction would
-- be worse than not checking at all: it would block real code
-- sometimes and give false confidence ("build passed, so it's fine")
-- when a case slips past it the rest of the time. Warn, don't block --
-- the actual, precise safety net is the loud "attempt to call a nil
-- value" crash if a bare cross-file reference is ever really
-- exercised.
function check_bare_cross_file_calls(files)
	definers = {}
	for _, file in ipairs(files) do
		f = io.open(file.path, "r")
		if f != nil then
			content = io.read(f, "*all")
			io.close(f)
			for name in string.gmatch(content, "\nfunction ([%a_][%w_]*)%(") do
				if definers[name] == nil then
					definers[name] = {}
				end
				table.insert(definers[name], file.path)
			end
		end
	end

	sources = {}
	for _, file in ipairs(files) do
		f = io.open(file.path, "r")
		if f != nil then
			sources[file.path] = io.read(f, "*all")
			io.close(f)
		end
	end

	for name, defining_files in pairs(definers) do
		if #defining_files == 1 then
			definer = defining_files[1]
			module_name = string.match(basename(definer), "(.+)%.")
			if module_name == nil then
				module_name = basename(definer)
			end
			for path, content in pairs(sources) do
				if path != definer then
					-- A bare call: name( not preceded by a letter,
					-- digit, underscore, or dot (so module.name( and
					-- somename( don't false-match).
					if string.find(content, "[^%w_.]" .. name .. "%(") != nil then
						io.write(io.stderr, string.format(
							"warning: %s defines '%s' as a bare (unexported) function, but %s calls it directly without going through %s's own module table -- this only worked because both files share one flat global namespace; an unrelated same-named global anywhere else in the bundle could silently break it. Consider exporting it properly instead (e.g. function %s.%s(...)).\n",
							definer, name, path, definer, module_name, name
						))
					end
				end
			end
		end
	end
end
check_bare_cross_file_calls(lua_source_files)

-- The entry point to the Lua program.
mainlua = lua_source_files[1]
-- Generate a C program containing the Lua source files that uses the Lua C API to 
-- initialize any Lua libraries and run the program.
outfilename = mainlua.basename_noextension .. ".static.c"
outfile = io.open(outfilename, "w+")
function out(...)
	io.write(outfile, ...)
end
function outhex(str)
	io.write(outfile, string_to_c_hex_literal(str), ", ")
end
-- Precompile Lua program source code to bytecode (or pass .luac through)
-- so runtime startup skips lexing/parsing and loads directly from .rodata.
function compile_lua_file(file)
	f = io.open(file.path, "rb")
	if f == nil then
		io.write(io.stderr, "cannot open file: " .. tostring(file.path) .. "\n")
		os.exit(1)
	end
	source = io.read(f, "*all")
	io.close(f)
	if source == nil then
		source = ""
	end
	if string.sub(source, 1, 4) != "\x1bLua" then
		if string.sub(source, 1, 3) == "\xef\xbb\xbf" then
			-- Strip the UTF-8 byte order mark.
			source = string.sub(source, 4)
		end
		if string.sub(source, 1, 1) == "#" then
			-- Strip leading shebang while keeping line numbers aligned.
			nl = string.find(source, "\n", 1, true)
			if nl != nil then
				source = string.sub(source, nl)
			else
				source = "\n"
			end
		end
		compile_fn = load
		if loadstring != nil then
			compile_fn = loadstring
		end
		chunk, err = compile_fn(source, file.dotpath_noextension)
		if chunk == nil then
			io.write(io.stderr, "error compiling " .. tostring(file.path) .. ": " .. tostring(err) .. "\n")
			os.exit(1)
		end
		source = string.dump(chunk)
	end
	return source
end

function out_bytes_chunked(bytes)
	chunk_size = 4096
	total = #bytes
	if total == 0 then
		out("0x00")
		return
	end
	pos = 1
	while pos <= total do
		slice_end = pos + chunk_size - 1
		if slice_end > total then
			slice_end = total
		end
		out(string_to_c_hex_literal(string.sub(bytes, pos, slice_end)), ", ")
		pos = slice_end + 1
	end
end

out("""
#ifdef __cplusplus
extern "C" {
#endif
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
#ifdef __cplusplus
}
#endif
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if LUA_VERSION_NUM == 501
	#define LUA_OK 0
	#define BUNDLE_RAWLEN(L, idx) lua_objlen((L), (idx))
#else
	#define BUNDLE_RAWLEN(L, idx) lua_rawlen((L), (idx))
#endif

/* Copied from lua.c */

static lua_State *globalL = NULL;

static void lstop (lua_State *L, lua_Debug *ar) {
	(void)ar;  /* unused arg. */
	lua_sethook(L, NULL, 0, 0);  /* reset hook */
	luaL_error(L, "interrupted!");
}

static void laction (int i) {
	signal(i, SIG_DFL); /* if another SIGINT happens, terminate process */
	lua_sethook(globalL, lstop, LUA_MASKCALL | LUA_MASKRET | LUA_MASKCOUNT, 1);
}

static void createargtable (lua_State *L, char **argv, int argc, int script) {
	int i, narg;
	if (script == argc) script = 0;  /* no script name? */
	narg = argc - (script + 1);  /* number of positive indices */
	lua_createtable(L, narg, script + 1);
	for (i = 0; i < argc; i++) {
		lua_pushstring(L, argv[i]);
		lua_rawseti(L, -2, i - script);
	}
	lua_setglobal(L, "arg");
}

static int msghandler (lua_State *L) {
	const char *msg = lua_tostring(L, 1);
	if (msg == NULL) {  /* is error object not a string? */
		if (luaL_callmeta(L, 1, "__tostring") &&  /* does it have a metamethod */
				lua_type(L, -1) == LUA_TSTRING)  /* that produces a string? */
			return 1;  /* that is the message */
		else
			msg = lua_pushfstring(L, "(error object is a %s value)", luaL_typename(L, 1));
	}
	/* Call debug.traceback() instead of luaL_traceback() for Lua 5.1 compatibility. */
	lua_getglobal(L, "debug");
	lua_getfield(L, -1, "traceback");
	/* debug */
	lua_remove(L, -2);
	lua_pushstring(L, msg);
	/* original msg */
	lua_remove(L, -3);
	lua_pushinteger(L, 2);  /* skip this function and traceback */
	lua_call(L, 2, 1); /* call debug.traceback */
	return 1;  /* return the traceback */
}

static int docall (lua_State *L, int narg, int nres) {
	int status;
	int base = lua_gettop(L) - narg;  /* function index */
	lua_pushcfunction(L, msghandler);  /* push message handler */
	lua_insert(L, base);  /* put it under function and args */
	globalL = L;  /* to be available to 'laction' */
	signal(SIGINT, laction);  /* set C-signal handler */
	status = lua_pcall(L, narg, nres, base);
	signal(SIGINT, SIG_DFL); /* reset C-signal handler */
	lua_remove(L, base);  /* remove message handler from the stack */
	return status;
}

#ifdef __cplusplus
extern "C" {
#endif
""")

for _, library in ipairs(module_library_files) do
	out(string.format("	int luaopen_%s(lua_State *L);\n", library.dotpath_underscore))
end

out("""
#ifdef __cplusplus
}
#endif

typedef struct {
	const char *name;
	const unsigned char *data;
	size_t size;
} lua_bundle_entry;

""")

for i, file in ipairs(lua_source_files) do
	compiled = compile_lua_file(file)
	file.compiled_size = #compiled
	out(string.format("static const unsigned char lua_require_%i[] = {\n	", i))
	out_bytes_chunked(compiled)
	out("\n};\n\n")
end

out("static const lua_bundle_entry lua_bundle_entries[] = {\n")
for i, file in ipairs(lua_source_files) do
	out(string.format("\t{ \"%s\", lua_require_%i, %i },\n", file.dotpath_noextension, i, file.compiled_size))
end
out("\t{ NULL, NULL, 0 }\n};\n")

out("""

static const lua_bundle_entry *find_bundle_entry(const char *name) {
	const lua_bundle_entry *e;
	for (e = lua_bundle_entries; e->name != NULL; e++) {
		if (strcmp(e->name, name) == 0) {
			return e;
		}
	}
	return NULL;
}

static int c_bundle_loader(lua_State *L) {
	const char *raw_name = luaL_checkstring(L, 1);
	size_t len = strlen(raw_name);
	char norm_buf[512];
	char init_buf[520];
	char *norm = norm_buf;
	const lua_bundle_entry *entry = NULL;
	size_t i;

	if (len >= sizeof(norm_buf)) {
		norm = (char *)malloc(len + 1);
		if (norm == NULL) {
			return luaL_error(L, "out of memory loading module '%s'", raw_name);
		}
	}
	for (i = 0; i < len; i++) {
		char c = raw_name[i];
		norm[i] = (c == '/' || c == '\\\\') ? '.' : c;
	}
	norm[len] = '\\0';

	entry = find_bundle_entry(norm);
	if (entry == NULL && len + 5 < sizeof(init_buf)) {
		memcpy(init_buf, norm, len);
		memcpy(init_buf + len, ".init", 6);
		entry = find_bundle_entry(init_buf);
	}

	if (entry != NULL) {
		int load_status = luaL_loadbuffer(L, (const char *)entry->data, entry->size, entry->name);
		if (norm != norm_buf) free(norm);
		if (load_status != LUA_OK) {
			return luaL_error(L, "error loading module '%s' from static bundle:\\n\\t%s",
				raw_name, lua_tostring(L, -1));
		}
		return 1;
	}

	lua_pushfstring(L, "\\n\\tno module '%s' in static bundle", norm);
	if (norm != norm_buf) free(norm);
	return 1;
}

int main(int argc, char *argv[])
{
	int arg_i, narg;
	lua_State *L = luaL_newstate();
	luaL_openlibs(L);
	createargtable(L, argv, argc, 0);
""")

if #module_library_files > 0 then
	out("\tlua_getglobal(L, \"package\");\n\tlua_getfield(L, -1, \"preload\");\n")
	for _, library in ipairs(module_library_files) do
		out(string.format("\tlua_pushcfunction(L, luaopen_%s);\n", library.dotpath_underscore))
		out(string.format("\tlua_setfield(L, -2, \"%s\");\n", library.dotpath_noextension))
	end
	out("\tlua_pop(L, 2);\n")
end

out("""
	lua_getglobal(L, "package");
	lua_getfield(L, -1, "loaders");
	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);
		lua_getfield(L, -1, "searchers");
	}
	if (lua_istable(L, -1)) {
		int loader_len = (int)BUNDLE_RAWLEN(L, -1);
		int idx;
		for (idx = loader_len; idx >= 2; idx--) {
			lua_rawgeti(L, -1, idx);
			lua_rawseti(L, -2, idx + 1);
		}
		lua_pushcfunction(L, c_bundle_loader);
		lua_rawseti(L, -2, 2);
	}
	lua_pop(L, 2);

	if (luaL_loadbuffer(L, (const char *)lua_bundle_entries[0].data, lua_bundle_entries[0].size, lua_bundle_entries[0].name) != LUA_OK)
	{
		fprintf(stderr, "luaL_loadbuffer: %s\\n", lua_tostring(L, -1));
		lua_close(L);
		return 1;
	}

	narg = (argc > 1) ? (argc - 1) : 0;
	luaL_checkstack(L, narg + 2, "too many arguments to script");
	for (arg_i = 1; arg_i < argc; arg_i++) {
		lua_pushstring(L, argv[arg_i]);
	}

	if (docall(L, narg, LUA_MULTRET))
	{
		const char *errmsg = lua_tostring(L, 1);
		if (errmsg)
		{
			fprintf(stderr, "%s\\n", errmsg);
		}
		lua_close(L);
		return 1;
	}
	lua_close(L);
	return 0;
}
""")

io.close(outfile)

if os.getenv("CC") == "" then
	-- Disable compiling and exit with a success code.
	os.exit(0)
end

if not execute(CC .. " --version 1>/dev/null 2>/dev/null") then
	io.write(io.stderr, "C compiler not found.\n")
	os.exit(1)
end

-- http://lua-users.org/lists/lua-l/2009-05/msg00147.html
rdynamic = "-rdynamic"
binary_extension = ""
if string.match(shellout(CC .. " -dumpmachine"), "mingw") != nil then
	rdynamic = ""
	binary_extension = ".exe"
end

compile_command = table.concat({
	CC,
	"-Os",
	outfilename,
	-- Link with Lua modules first to avoid linking errors.
	table.concat(module_link_libraries, " "),
	table.concat(dep_library_files, " "),
	rdynamic,
	"-lm",
	link_with_libdl,
	"-o " .. mainlua.basename_noextension .. binary_extension,
	table.concat(other_arguments, " "),
}, " ")
print(compile_command)
ok = execute(compile_command)
if ok then
	os.exit(0)
else
	os.exit(1)
end
