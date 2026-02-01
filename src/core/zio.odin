// Buffered streams
// Migrated from lzio.c/h
package core

import "base:runtime"
import "core:c"
import "core:mem"

// End of stream marker
EOZ :: -1

// Minimum buffer size
LUA_MINBUFFER :: 32

// Convert char to int (unsigned)
char2int :: #force_inline proc(ch: u8) -> int {
	return int(ch)
}

// Reader function type (same as lua_Reader)
Reader :: #type proc "c" (L: rawptr, data: rawptr, size: ^c.size_t) -> [^]u8

// Memory buffer - dynamic resizable buffer
Mbuffer :: struct {
	buffer:   [^]u8,
	n:        c.size_t, // current content size
	buffsize: c.size_t, // allocated size
}

// Initialize a memory buffer
initbuffer :: #force_inline proc(buff: ^Mbuffer) {
	buff.buffer = nil
	buff.buffsize = 0
	buff.n = 0
}

// Get buffer pointer
buffer :: #force_inline proc(buff: ^Mbuffer) -> [^]u8 {
	return buff.buffer
}

// Get buffer allocated size
sizebuffer :: #force_inline proc(buff: ^Mbuffer) -> c.size_t {
	return buff.buffsize
}

// Get buffer content length
bufflen :: #force_inline proc(buff: ^Mbuffer) -> c.size_t {
	return buff.n
}

// Reset buffer content (keep allocation)
resetbuffer :: #force_inline proc(buff: ^Mbuffer) {
	buff.n = 0
}

// Buffered input stream
ZIO :: struct {
	n:      c.size_t, // bytes still unread
	p:      [^]u8, // current position in buffer
	reader: Reader, // reader function
	data:   rawptr, // additional data for reader
	L:      rawptr, // Lua state (for reader)
}

// Initialize a ZIO stream
// Initialize a ZIO stream - REPLACED by luaZ_init
// init :: proc(L: rawptr, z: ^ZIO, reader: Reader, data: rawptr) { ... }

// Fill buffer - call reader for more data
// Returns first byte or EOZ if end of stream
// Fill buffer - call reader for more data
// Returns first byte or EOZ if end of stream
@(export, link_name = "luaZ_fill")
luaZ_fill :: proc "c" (z: ^ZIO) -> c.int {
	context = runtime.default_context()
	size: c.size_t = 0
	L := cast(^lua_State)z.L

	// Note: lua_unlock/lua_lock are no-ops in standard Lua
	buff := z.reader(L, z.data, &size)

	if buff == nil || size == 0 {
		return EOZ
	}

	z.n = size - 1
	z.p = buff
	result := char2int(z.p[0])
	z.p = z.p[1:] // advance pointer
	return c.int(result)
}

// Get character from stream (macro in C)
zgetc :: #force_inline proc(z: ^ZIO) -> int {
	if z.n > 0 {
		z.n -= 1
		result := char2int(z.p[0])
		z.p = z.p[1:]
		return result
	}
	return int(luaZ_fill(z))
}

// Look ahead one character without consuming
@(export, link_name = "luaZ_lookahead")
luaZ_lookahead :: proc "c" (z: ^ZIO) -> c.int {
	context = runtime.default_context()
	if z.n == 0 {
		if luaZ_fill(z) == c.int(EOZ) {
			return c.int(EOZ)
		} else {
			// fill removed first byte; put it back
			z.n += 1
			z.p = z.p[-1:] // back up pointer
		}
	}
	return c.int(char2int(z.p[0]))
}

// Initialize a ZIO stream
@(export, link_name = "luaZ_init")
luaZ_init :: proc "c" (L: ^lua_State, z: ^ZIO, reader: Reader, data: rawptr) {
	z.L = L
	z.reader = reader
	z.data = data
	z.n = 0
	z.p = nil
}

// Read n bytes from stream into buffer
// Returns number of bytes NOT read (0 = success)
@(export, link_name = "luaZ_read")
luaZ_read :: proc "c" (z: ^ZIO, b: rawptr, n: c.size_t) -> c.size_t {
	context = runtime.default_context()
	remaining := n
	dest := cast([^]u8)b
	offset: c.size_t = 0

	for remaining > 0 {
		if luaZ_lookahead(z) == c.int(EOZ) {
			return remaining // return number of missing bytes
		}

		// min(remaining, z.n)
		m := remaining if remaining <= z.n else z.n

		// Copy bytes
		mem.copy(&dest[offset], z.p, int(m))

		z.n -= m
		z.p = z.p[m:]
		offset += m
		remaining -= m
	}

	return 0
}

// Ensure buffer has at least n bytes of space
@(export, link_name = "luaZ_openspace")
luaZ_openspace :: proc "c" (L: ^lua_State, buff: ^Mbuffer, n: c.size_t) -> [^]u8 {
	context = runtime.default_context()
	if n > buff.buffsize {
		new_size := n
		if new_size < LUA_MINBUFFER {
			new_size = LUA_MINBUFFER
		}
		luaZ_resizebuffer(L, buff, new_size)
	}
	return buff.buffer
}

// Resize buffer
luaZ_resizebuffer :: proc(L: ^lua_State, buff: ^Mbuffer, size: c.size_t) {
	buff.buffer = luaM_reallocvector(L, buff.buffer, int(buff.buffsize), int(size), u8)
	buff.buffsize = size
}

// Free buffer
luaZ_freebuffer :: proc(L: ^lua_State, buff: ^Mbuffer) {
	luaZ_resizebuffer(L, buff, 0)
}
