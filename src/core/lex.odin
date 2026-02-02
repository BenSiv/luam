package core

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"

// Constants
FIRST_RESERVED :: 257

// Token Constants
TK_AND :: 257
TK_BREAK :: 258
TK_DO :: 259
TK_ELSE :: 260
TK_ELSEIF :: 261
TK_END :: 262
TK_FALSE :: 263
TK_FOR :: 264
TK_FUNCTION :: 265
TK_IF :: 266
TK_IN :: 267
TK_LOCAL :: 268
TK_CONST :: 269
TK_NIL :: 270
TK_NOT :: 271
TK_OR :: 272
TK_REPEAT :: 273
TK_RETURN :: 274
TK_THEN :: 275
TK_TRUE :: 276
TK_UNTIL :: 277
TK_WHILE :: 278
TK_CONCAT :: 279
TK_DOTS :: 280
TK_EQ :: 281
TK_GE :: 282
TK_LE :: 283
TK_NE :: 284
TK_NUMBER :: 285
TK_NAME :: 286
TK_STRING :: 287
TK_EOS :: 288
TK_DBCOLON :: 289

NUM_RESERVED :: TK_WHILE - FIRST_RESERVED + 1

// SemInfo Union
SemInfo :: struct #raw_union {
	r:  lua_Number,
	ts: ^TString,
}

// Token Struct
Token :: struct {
	token:   c.int,
	seminfo: SemInfo,
}

// LexState Struct - Must match C layout exactly
LexState :: struct {
	current:    c.int,
	linenumber: c.int,
	lastline:   c.int,
	t:          Token,
	lookahead:  Token,
	fs:         rawptr, // struct FuncState *fs
	L:          ^lua_State,
	z:          ^ZIO,
	buff:       ^Mbuffer,
	source:     ^TString,
	decpoint:   c.char,
}

// Token Names
luaX_tokens := [?]string {
	"and",
	"break",
	"do",
	"else",
	"elseif",
	"end",
	"false",
	"for",
	"function",
	"if",
	"in",
	"local",
	"const",
	"nil",
	"not",
	"or",
	"repeat",
	"return",
	"then",
	"true",
	"until",
	"while",
	"..",
	"...",
	"==",
	">=",
	"<=",
	"~=",
	"<number>",
	"<name>",
	"<string>",
	"<eof>",
}

// Helper: Save character to buffer
@(private)
save :: proc(ls: ^LexState, c_char: c.int) {
	b := ls.buff
	if b.n + 1 > b.buffsize {
		if b.buffsize >= MAX_SIZET / 2 {
			luaX_lexerror(ls, "lexical element too long", 0)
		}
		newsize := b.buffsize * 2
		luaZ_resizebuffer(ls.L, b, newsize)
	}
	b.buffer[b.n] = u8(c_char)
	b.n += 1
}

// Helper: Read next char, return it, update Current
@(private)
next_char :: proc(ls: ^LexState) -> c.int {
	ls.current = c.int(zgetc(ls.z))
	return ls.current
}

// Helper: Save and read next
@(private)
save_and_next :: proc(ls: ^LexState) {
	save(ls, ls.current)
	next_char(ls)
}

// Helper: Current is newline?
@(private)
currIsNewline :: #force_inline proc(ls: ^LexState) -> bool {
	return ls.current == '\n' || ls.current == '\r'
}

// Helper: Increment line number
@(private)
inclinenumber :: proc(ls: ^LexState) {
	old := ls.current
	// lua_assert(currIsNewline(ls))
	next_char(ls) // skip '\n' or '\r'
	if currIsNewline(ls) && ls.current != old {
		next_char(ls) // skip '\n\r' or '\r\n'
	}
	ls.linenumber += 1
	if ls.linenumber >= MAX_INT {
		luaX_syntaxerror(ls, "chunk has too many lines")
	}
}

// Helper: Check next character
@(private)
check_next :: proc(ls: ^LexState, set: string) -> bool {
	if !strings.contains_rune(set, rune(ls.current)) {
		return false
	}
	save_and_next(ls)
	return true
}

// Helper: Read numerals
@(private)
read_numeral :: proc(ls: ^LexState, seminfo: ^SemInfo) {
	// lua_assert(isdigit(ls.current))
	for {
		save_and_next(ls)
		ch := ls.current
		if !((ch >= '0' && ch <= '9') || ch == '.') {
			break
		}
	}
	if check_next(ls, "Ee") {
		check_next(ls, "+-")
	}
	for {
		ch := ls.current
		if (ch >= '0' && ch <= '9') ||
		   (ch >= 'a' && ch <= 'z') ||
		   (ch >= 'A' && ch <= 'Z') ||
		   ch == '_' {
			save_and_next(ls)
		} else {
			break
		}
	}
	save(ls, 0)

	// Convert to number
	// TODO: Using crt strtod or luaO_str2d if ported
	// For now, assuming standard atof/strtod behavior works or use Lua's internal
	// We really should link to luaO_str2d or implement it.
	// Since luaO_str2d is complex (locale handling etc), we'll try to use a simple converter for now
	// or bind to luaO_str2d if it's available in lobject.o (it is!)

	str := cstring(ls.buff.buffer)
	if luaO_str2d(str, &seminfo.r) == 0 {
		luaX_lexerror(ls, "malformed number", TK_NUMBER)
	}
}

// Helper: Read strings
@(private)
read_string :: proc(ls: ^LexState, del: c.int, seminfo: ^SemInfo) {
	save_and_next(ls)
	for ls.current != del {
		switch ls.current {
		case EOZ:
			luaX_lexerror(ls, "unfinished string", TK_EOS)
		case '\n', '\r':
			luaX_lexerror(ls, "unfinished string", TK_STRING)
		case '\\':
			next_char(ls) // do not save '\'
			switch ls.current {
			case 'a':
				save(ls, '\a'); next_char(ls)
			case 'b':
				save(ls, '\b'); next_char(ls)
			case 'f':
				save(ls, '\f'); next_char(ls)
			case 'n':
				save(ls, '\n'); next_char(ls)
			case 'r':
				save(ls, '\r'); next_char(ls)
			case 't':
				save(ls, '\t'); next_char(ls)
			case 'v':
				save(ls, '\v'); next_char(ls)
			case '\n', '\r':
				save(ls, '\n')
				inclinenumber(ls)
			case:
				if !((ls.current >= '0' && ls.current <= '9')) {
					save_and_next(ls)
				} else {
					// \xxx
					ch := 0
					for i := 0; i < 3 && ls.current >= '0' && ls.current <= '9'; i += 1 {
						ch = 10 * ch + (int(ls.current) - '0')
						next_char(ls)
					}
					if ch > 255 {
						luaX_lexerror(ls, "escape sequence too large", TK_STRING)
					}
					save(ls, c.int(ch))
				}
			}
		case:
			save_and_next(ls)
		}
	}
	save_and_next(ls) // skip delimiter
	seminfo.ts = luaX_newstring(
		ls,
		cstring(mem.ptr_offset(ls.buff.buffer, 1)),
		bufflen(ls.buff) - 2,
	)
}

// Main Lex Function
@(private)
llex :: proc(ls: ^LexState, seminfo: ^SemInfo) -> c.int {
	resetbuffer(ls.buff)
	for {
		switch ls.current {
		case '\n', '\r':
			inclinenumber(ls)
			continue
		case '-':
			next_char(ls)
			if ls.current != '-' {
				return '-'
			}
			// Comment
			next_char(ls)
			// Short comment only for this port as per existing C code (removed long comments?)
			// The previous C code had: "/* [ANTIGRAVITY] Removed long comment support */"
			// Wait, standard Lua 5.1 supports long comments defined by --[[ ... ]]
			// The user C code specifically removed it?
			// "while (!currIsNewline(ls) && ls->current != EOZ) next(ls);"
			for !currIsNewline(ls) && ls.current != EOZ {
				next_char(ls)
			}
			continue
		case '[':
			// Long string or just '[' ... actually check for long string/comment bracket?
			// Standard Lua checks for long strings here if level >= 0, but C code simplified?
			// C code: case '[': next(ls); return '[';
			next_char(ls)
			return '['
		case '=':
			next_char(ls)
			if ls.current != '=' {
				return '='
			}
			next_char(ls)
			return TK_EQ
		case '<':
			next_char(ls)
			if ls.current != '=' {
				return '<'
			}
			next_char(ls)
			return TK_LE
		case '>':
			next_char(ls)
			if ls.current != '=' {
				return '>'
			}
			next_char(ls)
			return TK_GE
		case '!':
			next_char(ls)
			if ls.current != '=' {
				return '!'
			}
			next_char(ls)
			return TK_NE
		case '~':
			next_char(ls)
			if ls.current != '=' {
				return '~'
			}
			next_char(ls)
			return TK_NE
		case '"', '\'':
			// Handle strings
			read_string(ls, ls.current, seminfo)
			return TK_STRING
		case '.':
			save_and_next(ls)
			if check_next(ls, ".") {
				if check_next(ls, ".") {
					return TK_DOTS
				}
				return TK_CONCAT
			} else if !((ls.current >= '0' && ls.current <= '9')) {
				return '.'
			} else {
				read_numeral(ls, seminfo)
				return TK_NUMBER
			}
		case EOZ:
			return TK_EOS
		case:
			if ls.current == ' ' ||
			   ls.current == '\f' ||
			   ls.current == '\t' ||
			   ls.current == '\v' {
				next_char(ls)
				continue
			} else if ls.current >= '0' && ls.current <= '9' {
				read_numeral(ls, seminfo)
				return TK_NUMBER
			} else if (ls.current >= 'a' && ls.current <= 'z') ||
			   (ls.current >= 'A' && ls.current <= 'Z') ||
			   ls.current == '_' {
				// Identifier or reserved word
				for {
					save_and_next(ls)
					ch := ls.current
					is_alnum :=
						(ch >= '0' && ch <= '9') ||
						(ch >= 'a' && ch <= 'z') ||
						(ch >= 'A' && ch <= 'Z') ||
						ch == '_'
					if !is_alnum {
						break
					}
				}
				ts := luaX_newstring(ls, cstring(ls.buff.buffer), bufflen(ls.buff))
				if getstr(ts) == "if" {
					fmt.printf(
						"DEBUG: llex scanned 'if' at %p with reserved=%d\n",
						ts,
						ts.tsv.reserved,
					)
				}
				if ts.tsv.reserved > 0 {
					return c.int(ts.tsv.reserved) - 1 + FIRST_RESERVED
				} else {
					seminfo.ts = ts
					return TK_NAME
				}
			} else {
				ch := ls.current
				next_char(ls)
				return ch
			}
		}
	}
}


// --- Exported Functions ---

@(export, link_name = "luaX_init_unique")
luaX_init :: proc "c" (L: ^lua_State) {
	context = runtime.default_context()
	fmt.printf("DEBUG: luaX_init called\n")
	fmt.printf("DEBUG: size_of(TValue) = %d\n", size_of(TValue))
	fmt.printf("DEBUG: size_of(Value) = %d\n", size_of(Value))
	fmt.printf("DEBUG: size_of(Node) = %d\n", size_of(Node))
	fmt.printf("DEBUG: size_of(TKey) = %d\n", size_of(TKey))
	fmt.printf("DEBUG: offset_of(TValue, tt) = %d\n", offset_of(TValue, tt))
	// Initialize reserved words
	// In C: luaX_init_unique logic
	for i in 0 ..< NUM_RESERVED {
		name := strings.clone_to_cstring(luaX_tokens[i])
		ts := luaS_new(L, name)
		luaS_fix(ts)
		ts.tsv.reserved = u8(i + 1)
		if luaX_tokens[i] == "if" {
			fmt.printf("DEBUG: 'if' initialized at %p with reserved=%d\n", ts, ts.tsv.reserved)
		}
	}
}

@(export, link_name = "luaX_setinput")
luaX_setinput :: proc "c" (L: ^lua_State, ls: ^LexState, z: ^ZIO, source: ^TString) {
	context = runtime.default_context()
	ls.decpoint = '.'
	ls.L = L
	ls.lookahead.token = TK_EOS
	ls.z = z
	ls.fs = nil
	ls.linenumber = 1
	ls.lastline = 1
	ls.source = source
	luaZ_resizebuffer(ls.L, ls.buff, LUA_MINBUFFER)
	next_char(ls)
}

@(export, link_name = "luaX_newstring")
luaX_newstring :: proc "c" (ls: ^LexState, str: cstring, l: c.size_t) -> ^TString {
	context = runtime.default_context()
	L := ls.L
	ts := luaS_newlstr(L, str, l)
	// Anchor string to avoid GC
	// In C: TValue *o = luaH_setstr(L, ls->fs->h, ts);
	// We need access to ls.fs (FuncState) which is opaque here
	// But duplicate C logic:
	// TValue *o = luaH_setstr(L, ls->fs->h, ts);
	// if (ttisnil(o)) { setbvalue(o, 1); luaC_checkGC(L); }

	// Since we can't access struct fields of opaque ptr easily without definition,
	// We might need to assume FS layout OR import it.
	// However, looking at lparser.h, FuncState struct is visible.
	// For now, let's delay this anchoring or trust that the C parser does usage correctly?
	// No, llex calls this to PROTECT the string during parsing.

	// Hack: Define minimal FuncState struct here or import it?
	// It's defined in lparser.h but not core/parser.odin (doesn't exist).
	// Let's assume binary layout of FuncState start:
	// struct FuncState { Proto *f; Table *h; ... }

	val := cast(^rawptr)ls.fs
	// h is the second pointer?
	// struct FuncState { Proto *f; Table *h; ... } - yes usually.
	// Let's rely on an helper if possible, or skip anchoring IF we are not running GC?
	// But GC can run.

	// Better approach: Implement `luaX_newstring` in C (keep it there?) or fully port.
	// `llex.c` implementation of `luaX_newstring` is:
	// TValue *o = luaH_setstr(L, ls->fs->h, ts);

	// FIXME: This is dangerous without FS definition.
	// Let's assume strictly 64-bit pointers and `h` is at offset 8.
	// Check `lparser.h`?
	// struct FuncState { Proto *f; Table *h; ... }
	// Yes.

	if ls.fs != nil {
		fs_h := cast(^rawptr)(cast(uintptr)ls.fs + size_of(rawptr)) // Table *h
		h := cast(^Table)fs_h^

		o := luaH_setstr(L, h, ts)
		if ttisnil(o) {
			// setbvalue(o, 1) -> boolean true
			o.tt = LUA_TBOOLEAN
			o.value.b = 1
			luaC_checkGC(L)
		}
	}

	return ts
}

@(export, link_name = "luaX_next")
luaX_next :: proc "c" (ls: ^LexState) {
	context = runtime.default_context()
	ls.lastline = ls.linenumber
	if ls.lookahead.token != TK_EOS {
		ls.t = ls.lookahead
		ls.lookahead.token = TK_EOS
	} else {
		ls.t.token = llex(ls, &ls.t.seminfo)
	}
}

@(export, link_name = "luaX_lookahead")
luaX_lookahead :: proc "c" (ls: ^LexState) {
	context = runtime.default_context()
	// lua_assert(ls->lookahead.token == TK_EOS);
	ls.lookahead.token = llex(ls, &ls.lookahead.seminfo)
}

// Helper: txtToken
@(private)
txtToken :: proc(ls: ^LexState, token: c.int) -> cstring {
	switch token {
	case TK_NAME, TK_STRING, TK_NUMBER:
		save(ls, 0)
		return cstring(ls.buff.buffer)
	case:
		return luaX_token2str(ls, token)
	}
}

@(export, link_name = "luaX_lexerror")
luaX_lexerror :: proc "c" (ls: ^LexState, msg: cstring, token: c.int) {
	context = runtime.default_context()
	buff: [80]u8 // MAXSRC
	luaO_chunkid(cstring(&buff[0]), getstr(ls.source), 80)

	// Create formatted message
	msg_fmt := luaO_pushfstring(ls.L, "%s:%d: %s", cstring(&buff[0]), ls.linenumber, msg)

	if token != 0 {
		luaO_pushfstring(ls.L, "%s near '%s'", msg_fmt, txtToken(ls, token))
	}

	luaD_throw_c(ls.L, LUA_ERRSYNTAX)
}

@(export, link_name = "luaX_syntaxerror")
luaX_syntaxerror :: proc "c" (ls: ^LexState, s: cstring) {
	context = runtime.default_context()
	luaX_lexerror(ls, s, ls.t.token)
}

@(export, link_name = "luaX_token2str")
luaX_token2str :: proc "c" (ls: ^LexState, token: c.int) -> cstring {
	context = runtime.default_context()
	if token < FIRST_RESERVED {
		// return (iscntrl(token)) ? luaO_pushfstring(ls->L, "char(%d)", token) : luaO_pushfstring(ls->L, "%c", token);
		// Basic stub:
		if token < 0 {
			return "<eof>" // Should not happen with valid char, but good safety
		}
		// return luaO_pushfstring(ls.L, "%c", token) // Requires reimplementing helper or relying on C
		// For now simple stub for printable chars
		if token > 31 && token < 127 {
			// We can return a static buffer or push to stack.
			// luaO_pushfstring pushes to stack.
			return luaO_pushfstring(ls.L, "%c", token)
		}
		return luaO_pushfstring(ls.L, "char(%d)", token)
	} else {
		idx := token - FIRST_RESERVED
		if idx >= 0 && idx < len(luaX_tokens) {
			return strings.clone_to_cstring(luaX_tokens[idx])
		}
	}
	return "<unknown>"
}

// C Imports for functions we missed or need
foreign import lua_core "../../obj/liblua.a"

foreign lua_core {
	luaO_str2d :: proc(s: cstring, p: ^lua_Number) -> c.int ---
	luaO_pushfstring :: proc(L: ^lua_State, fmt: cstring, #c_vararg args: ..any) -> cstring ---
	luaO_chunkid :: proc(out: cstring, source: cstring, len: c.size_t) ---
}
