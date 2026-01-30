// Buffered streams
// Migrated from lzio.c/h
package core

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
init :: proc(L: rawptr, z: ^ZIO, reader: Reader, data: rawptr) {
	z.L = L
	z.reader = reader
	z.data = data
	z.n = 0
	z.p = nil
}

// Fill buffer - call reader for more data
// Returns first byte or EOZ if end of stream
fill :: proc(z: ^ZIO) -> int {
	size: c.size_t = 0
	L := z.L

	// Note: lua_unlock/lua_lock are no-ops in standard Lua
	buff := z.reader(L, z.data, &size)

	if buff == nil || size == 0 {
		return EOZ
	}

	z.n = size - 1
	z.p = buff
	result := char2int(z.p[0])
	z.p = z.p[1:] // advance pointer
	return result
}

// Get character from stream (macro in C)
zgetc :: #force_inline proc(z: ^ZIO) -> int {
	if z.n > 0 {
		z.n -= 1
		result := char2int(z.p[0])
		z.p = z.p[1:]
		return result
	}
	return fill(z)
}

// Look ahead one character without consuming
lookahead :: proc(z: ^ZIO) -> int {
	if z.n == 0 {
		if fill(z) == EOZ {
			return EOZ
		} else {
			// fill removed first byte; put it back
			z.n += 1
			z.p = z.p[-1:] // back up pointer
		}
	}
	return char2int(z.p[0])
}

// Read n bytes from stream into buffer
// Returns number of bytes NOT read (0 = success)
read :: proc(z: ^ZIO, b: rawptr, n: c.size_t) -> c.size_t {
	remaining := n
	dest := cast([^]u8)b
	offset: c.size_t = 0

	for remaining > 0 {
		if lookahead(z) == EOZ {
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
// Note: This requires memory allocation from lua_State
// For now, returns existing buffer - will be completed when lstate is integrated
openspace :: proc(L: rawptr, buff: ^Mbuffer, n: c.size_t) -> [^]u8 {
	// TODO: Integrate with mem.reallocv when lstate is migrated
	// For now, assume buffer is pre-allocated or caller handles it
	if n > buff.buffsize {
		// Would need: resizebuffer(L, buff, max(n, LUA_MINBUFFER))
	}
	return buff.buffer
}

// Resize buffer (requires Lua allocator - stub for now)
resizebuffer :: proc(L: rawptr, buff: ^Mbuffer, size: c.size_t) {
	// TODO: Implement when lstate is migrated
	// luaM_reallocvector(L, buff.buffer, buff.buffsize, size, u8)
	buff.buffsize = size
}

// Free buffer
freebuffer :: proc(L: rawptr, buff: ^Mbuffer) {
	resizebuffer(L, buff, 0)
}
