package lib

import "../lua"
import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:mem"
import "core:strings"

LUA_MAXCAPTURES :: 32
CAP_UNFINISHED :: -1
CAP_POSITION :: -2
L_ESC :: '%'
SPECIALS :: "^$*+?.([%-"

MAX_ITEM :: 512
FLAGS :: "-+ #0"
MAX_FORMAT :: 32 // FLAGS + length + buffer

MatchState :: struct {
	src_init: cstring,
	src_end:  cstring,
	L:        ^lua.State,
	level:    c.int,
	capture:  [LUA_MAXCAPTURES]struct {
		init: cstring,
		len:  int,
	},
}

uchar :: #force_inline proc(ch: c.char) -> c.int {
	return c.int(cast(u8)ch)
}

// posrelat from lstrlib.c
posrelat :: #force_inline proc(pos: int, len: c.size_t) -> int {
	if pos >= 0 {
		return pos
	} else if -pos > int(len) {
		return 0
	} else {
		return int(len) + pos + 1
	}
}

check_capture :: proc "c" (ms: ^MatchState, l: c.int) -> c.int {
	context = runtime.default_context()
	l := l - '1'
	if l < 0 || l >= ms.level || ms.capture[l].len == CAP_UNFINISHED {
		return lua.luaL_error(ms.L, "invalid capture index")
	}
	return l
}

capture_to_close :: proc "c" (ms: ^MatchState) -> c.int {
	context = runtime.default_context()
	level := ms.level
	for level -= 1; level >= 0; level -= 1 {
		if ms.capture[level].len == CAP_UNFINISHED {
			return level
		}
	}
	return lua.luaL_error(ms.L, "invalid pattern capture")
}

classend :: proc "c" (ms: ^MatchState, p: cstring) -> cstring {
	context = runtime.default_context()
	p_ptr := cast([^]u8)p
	ch := p_ptr[0]; p_ptr = &(p_ptr[1])
	switch ch {
	case L_ESC:
		if p_ptr[0] == '\x00' {
			lua.luaL_error(ms.L, "malformed pattern (ends with '%%')")
		}
		return cstring(&(p_ptr[1]))
	case '[':
		if p_ptr[0] == '^' {
			p_ptr = &(p_ptr[1])
		}
		for {
			if p_ptr[0] == '\x00' {
				lua.luaL_error(ms.L, "malformed pattern (missing ']')")
			}
			c2 := p_ptr[0]; p_ptr = &(p_ptr[1])
			if c2 == L_ESC && p_ptr[0] != '\x00' {
				p_ptr = &(p_ptr[1]) // skip escapes (e.g. '%]')
			}
			if p_ptr[0] == ']' {
				break
			}
		}
		return cstring(&(p_ptr[1]))
	case:
		return cstring(&(p_ptr[0]))
	}
}

match_class :: proc "c" (ch: c.int, cl: c.int) -> bool {
	res: bool
	switch libc.tolower(cl) {
	case 'a':
		res = libc.isalpha(ch) != 0
	case 'c':
		res = libc.iscntrl(ch) != 0
	case 'd':
		res = libc.isdigit(ch) != 0
	case 'l':
		res = libc.islower(ch) != 0
	case 'p':
		res = libc.ispunct(ch) != 0
	case 's':
		res = libc.isspace(ch) != 0
	case 'u':
		res = libc.isupper(ch) != 0
	case 'w':
		res = libc.isalnum(ch) != 0
	case 'x':
		res = libc.isxdigit(ch) != 0
	case 'z':
		res = (ch == 0)
	case:
		return cl == ch
	}
	return (libc.islower(cl) != 0) == res
}

matchbracketclass :: proc "c" (ch: c.int, p: cstring, ec: cstring) -> bool {
	context = runtime.default_context()
	sig := true
	p_ptr := cast([^]u8)p
	ec_ptr := cast([^]u8)ec

	if p_ptr[1] == '^' {
		sig = false
		p_ptr = &(p_ptr[1]) // skip the '^'
	}

	for {
		p_ptr = &(p_ptr[1])
		if uintptr(p_ptr) >= uintptr(ec_ptr) {
			break
		}

		if p_ptr[0] == L_ESC {
			p_ptr = &(p_ptr[1])
			if match_class(ch, uchar(cast(c.char)p_ptr[0])) {
				return sig
			}
		} else if p_ptr[1] == '-' && uintptr(&(p_ptr[2])) < uintptr(ec_ptr) {
			p_ptr = &(p_ptr[2])
			if uchar(cast(c.char)p_ptr[-2]) <= ch && ch <= uchar(cast(c.char)p_ptr[0]) {
				return sig
			}
		} else if uchar(cast(c.char)p_ptr[0]) == ch {
			return sig
		}
	}

	return !sig
}

singlematch :: proc "c" (ch: c.int, p: cstring, ep: cstring) -> bool {
	context = runtime.default_context()
	p_ptr := cast([^]u8)p
	switch p_ptr[0] {
	case '.':
		return true
	case L_ESC:
		return match_class(ch, uchar(cast(c.char)p_ptr[1]))
	case '[':
		ep_ptr := cast([^]u8)ep
		return matchbracketclass(ch, p, cstring(&(ep_ptr[-1])))
	case:
		return uchar(cast(c.char)p_ptr[0]) == ch
	}
}

matchbalance :: proc "c" (ms: ^MatchState, s: cstring, p: cstring) -> cstring {
	context = runtime.default_context()
	s_ptr := cast([^]u8)s
	p_ptr := cast([^]u8)p
	if p_ptr[0] == '\x00' || p_ptr[1] == '\x00' {
		lua.luaL_error(ms.L, "unbalanced pattern")
	}
	if s_ptr[0] != p_ptr[0] {
		return nil
	} else {
		b := p_ptr[0]
		e := p_ptr[1]
		cont := 1
		s_ptr = &(s_ptr[1])
		src_end_ptr := cast([^]u8)ms.src_end
		for uintptr(rawptr(s_ptr)) < uintptr(rawptr(src_end_ptr)) {
			if s_ptr[0] == e {
				cont -= 1
				if cont == 0 {
					return cstring(&(s_ptr[1]))
				}
			} else if s_ptr[0] == b {
				cont += 1
			}
			s_ptr = &(s_ptr[1])
		}
	}
	return nil
}

max_expand :: proc "c" (ms: ^MatchState, s: cstring, p: cstring, ep: cstring) -> cstring {
	context = runtime.default_context()
	i: int = 0
	s_ptr := cast([^]u8)s
	src_end_ptr := cast([^]u8)ms.src_end
	for uintptr(rawptr(&(s_ptr[i]))) < uintptr(rawptr(src_end_ptr)) &&
	    singlematch(uchar(cast(c.char)s_ptr[i]), p, ep) {
		i += 1
	}
	for i >= 0 {
		ep_ptr := cast([^]u8)ep
		res := match(ms, cstring(&(s_ptr[i])), cstring(&(ep_ptr[1])))
		if res != nil {
			return res
		}
		i -= 1
	}
	return nil
}

min_expand :: proc "c" (ms: ^MatchState, s: cstring, p: cstring, ep: cstring) -> cstring {
	context = runtime.default_context()
	s_ptr := cast([^]u8)s
	src_end_ptr := cast([^]u8)ms.src_end
	for {
		ep_ptr := cast([^]u8)ep
		res := match(ms, cstring(rawptr(s_ptr)), cstring(&(ep_ptr[1])))
		if res != nil {
			return res
		} else if uintptr(rawptr(s_ptr)) < uintptr(rawptr(src_end_ptr)) &&
		   singlematch(uchar(cast(c.char)s_ptr[0]), p, ep) {
			s_ptr = &(s_ptr[1])
		} else {
			return nil
		}
	}
}

// Core recursive match function
match :: proc "c" (ms: ^MatchState, s: cstring, p: cstring) -> cstring {
	context = runtime.default_context()
	s_ptr := cast([^]u8)s
	p_ptr := cast([^]u8)p
	src_end_ptr := cast([^]u8)ms.src_end
	src_init_ptr := cast([^]u8)ms.src_init

	init_label: for {
		p_char := p_ptr[0]

		handle_dflt := false

		switch p_char {
		case '(':
			if p_ptr[1] == ')' {
				return start_capture(ms, cstring(s_ptr), cstring(&(p_ptr[2])), CAP_POSITION)
			} else {
				return start_capture(ms, cstring(s_ptr), cstring(&(p_ptr[1])), CAP_UNFINISHED)
			}
		case ')':
			return end_capture(ms, cstring(s_ptr), cstring(&(p_ptr[1])))
		case L_ESC:
			switch p_ptr[1] {
			case 'b':
				res_s := matchbalance(ms, cstring(s_ptr), cstring(&(p_ptr[2])))
				if res_s == nil {
					return nil
				}
				s_ptr = cast([^]u8)res_s
				p_ptr = &(p_ptr[4])
				continue init_label
			case 'f':
				p_ptr = &(p_ptr[2])
				if p_ptr[0] != '[' {
					lua.luaL_error(ms.L, "missing '[' after '%%f' in pattern")
				}
				ep := classend(ms, cstring(p_ptr))
				ep_ptr := cast([^]u8)ep
				previous := u8(0) if s_ptr == src_init_ptr else cast(u8)s_ptr[-1]
				if matchbracketclass(c.int(previous), cstring(p_ptr), cstring(&(ep_ptr[-1]))) ||
				   !matchbracketclass(
						   uchar(cast(c.char)s_ptr[0]),
						   cstring(p_ptr),
						   cstring(&(ep_ptr[-1])),
					   ) {
					return nil
				}
				p_ptr = ep_ptr
				continue init_label
			case:
				if libc.isdigit(c.int(p_ptr[1])) != 0 {
					res_s := match_capture(ms, cstring(s_ptr), c.int(p_ptr[1]))
					if res_s == nil {
						return nil
					}
					s_ptr = cast([^]u8)res_s
					p_ptr = &(p_ptr[2])
					continue init_label
				}
				handle_dflt = true
			}
		case '\x00':
			return cstring(s_ptr)
		case '$':
			if p_ptr[1] == '\x00' {
				return cstring(s_ptr) if s_ptr == src_end_ptr else nil
			}
			handle_dflt = true
		case:
			handle_dflt = true
		}

		if handle_dflt {
			ep := classend(ms, cstring(p_ptr))
			ep_ptr := cast([^]u8)ep
			m :=
				uintptr(rawptr(s_ptr)) < uintptr(rawptr(src_end_ptr)) &&
				singlematch(uchar(cast(c.char)s_ptr[0]), cstring(p_ptr), ep)

			switch ep_ptr[0] {
			case '?':
				if m {
					res := match(ms, cstring(&(s_ptr[1])), cstring(&(ep_ptr[1])))
					if res != nil {
						return res
					}
				}
				p_ptr = &(ep_ptr[1])
				continue init_label
			case '*':
				return max_expand(ms, cstring(s_ptr), cstring(p_ptr), ep)
			case '+':
				return max_expand(ms, cstring(&(s_ptr[1])), cstring(p_ptr), ep) if m else nil
			case '-':
				return min_expand(ms, cstring(s_ptr), cstring(p_ptr), ep)
			case:
				if !m {
					return nil
				}
				s_ptr = &(s_ptr[1])
				p_ptr = ep_ptr
				continue init_label
			}
		}
	}
}

start_capture :: proc "c" (ms: ^MatchState, s: cstring, p: cstring, what: int) -> cstring {
	context = runtime.default_context()
	level := ms.level
	if level >= LUA_MAXCAPTURES {
		lua.luaL_error(ms.L, "too many captures")
	}
	ms.capture[level].init = s
	ms.capture[level].len = what
	ms.level = level + 1
	res := match(ms, s, p)
	if res == nil {
		ms.level -= 1
	}
	return res
}

end_capture :: proc "c" (ms: ^MatchState, s: cstring, p: cstring) -> cstring {
	l := capture_to_close(ms)
	s_ptr := cast([^]u8)s
	init_ptr := cast([^]u8)ms.capture[l].init
	ms.capture[l].len = int(uintptr(rawptr(s_ptr)) - uintptr(rawptr(init_ptr)))
	res := match(ms, s, p)
	if res == nil {
		ms.capture[l].len = CAP_UNFINISHED
	}
	return res
}

match_capture :: proc "c" (ms: ^MatchState, s: cstring, l: c.int) -> cstring {
	l := check_capture(ms, l)
	len := ms.capture[l].len
	src_end_ptr := cast([^]u8)ms.src_end
	s_ptr := cast([^]u8)s
	init_ptr := cast([^]u8)ms.capture[l].init

	if int(uintptr(rawptr(src_end_ptr)) - uintptr(rawptr(s_ptr))) >= len &&
	   libc.memcmp(rawptr(init_ptr), rawptr(s_ptr), c.size_t(len)) == 0 {
		return cstring(&(s_ptr[len]))
	}
	return nil
}

mem_find :: proc "c" (s1: cstring, l1: c.size_t, s2: cstring, l2: c.size_t) -> cstring {
	l1 := int(l1)
	l2 := int(l2)
	s1_ptr := cast([^]u8)s1
	s2_ptr := cast([^]u8)s2

	if l2 == 0 {
		return s1
	} else if l2 > l1 {
		return nil
	} else {
		init: [^]u8
		l2 -= 1
		l1 = l1 - l2
		for l1 > 0 {
			init = cast([^]u8)libc.memchr(rawptr(s1_ptr), c.int(s2_ptr[0]), c.size_t(l1))
			if init == nil {
				break
			}
			init = &(init[1])
			if libc.memcmp(rawptr(init), rawptr(&(s2_ptr[1])), c.size_t(l2)) == 0 {
				return cstring(&(init[-1]))
			}
			l1 -= int(uintptr(rawptr(init)) - uintptr(rawptr(s1_ptr)))
			s1_ptr = init
		}
		return nil
	}
}

push_onecapture :: proc "c" (ms: ^MatchState, i: c.int, s: cstring, e: cstring) {
	if i >= ms.level {
		if i == 0 {
			s_ptr := cast([^]u8)s
			e_ptr := cast([^]u8)e
			lua.lua_pushlstring(ms.L, s, c.size_t(uintptr(rawptr(e_ptr)) - uintptr(rawptr(s_ptr))))
		} else {
			lua.luaL_error(ms.L, "invalid capture index")
		}
	} else {
		len := ms.capture[i].len
		if len == CAP_UNFINISHED {
			lua.luaL_error(ms.L, "unfinished capture")
		}
		if len == CAP_POSITION {
			init_ptr := cast([^]u8)ms.capture[i].init
			src_init_ptr := cast([^]u8)ms.src_init
			lua.lua_pushinteger(
				ms.L,
				int(uintptr(rawptr(init_ptr)) - uintptr(rawptr(src_init_ptr))) + 1,
			)
		} else {
			lua.lua_pushlstring(ms.L, ms.capture[i].init, c.size_t(len))
		}
	}
}

push_captures :: proc "c" (ms: ^MatchState, s: cstring, e: cstring) -> c.int {
	nlevels := ms.level if !(ms.level == 0 && s != nil) else 1
	lua.luaL_checkstack(ms.L, nlevels, "too many captures")
	for i: c.int = 0; i < nlevels; i += 1 {
		push_onecapture(ms, i, s, e)
	}
	return nlevels
}

str_find_aux :: proc(L: ^lua.State, find: bool) -> c.int {
	context = runtime.default_context()
	l1, l2: c.size_t
	s := lua.luaL_checklstring(L, 1, &l1)
	p := lua.luaL_checklstring(L, 2, &l2)
	init := posrelat(lua.luaL_optinteger(L, 3, 1), l1) - 1
	if init < 0 {
		init = 0
	} else if c.size_t(init) > l1 {
		init = int(l1)
	}

	p_ptr := cast([^]u8)p
	if find && (lua.lua_toboolean(L, 4) != 0 || libc.strpbrk(p, SPECIALS) == nil) {
		// Plain search
		s2 := mem_find(cstring(&(cast([^]u8)s)[init]), l1 - c.size_t(init), p, l2)
		if s2 != nil {
			s_ptr := cast([^]u8)s
			s2_ptr := cast([^]u8)s2
			lua.lua_pushinteger(L, int(uintptr(rawptr(s2_ptr)) - uintptr(rawptr(s_ptr))) + 1)
			lua.lua_pushinteger(L, int(uintptr(rawptr(s2_ptr)) - uintptr(rawptr(s_ptr))) + int(l2))
			return 2
		}
	} else {
		ms: MatchState
		anchor := false
		if p_ptr[0] == '^' {
			anchor = true
			p_ptr = &(p_ptr[1])
		}
		s_ptr := cast([^]u8)s
		s1 := &(s_ptr[init])
		ms.L = L
		ms.src_init = s
		ms.src_end = cstring(&(s_ptr[l1]))

		for {
			ms.level = 0
			res := match(&ms, cstring(rawptr(s1)), cstring(rawptr(p_ptr)))
			if res != nil {
				res_ptr := cast([^]u8)res
				lua.lua_pushinteger(L, int(uintptr(rawptr(s1)) - uintptr(rawptr(s_ptr))) + 1)
				lua.lua_pushinteger(L, int(uintptr(rawptr(res_ptr)) - uintptr(rawptr(s_ptr))))
				return push_captures(&ms, nil, nil) + 2
			}
			s1_arr := cast([^]u8)s1
			s1 = &(s1_arr[1])
			if !(uintptr(rawptr(s1)) <= uintptr(rawptr(ms.src_end)) && !anchor) {
				break
			}
		}
	}
	lua.lua_pushnil(L)
	return 1
}

str_find :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	return str_find_aux(L, true)
}

str_match :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	l1, l2: c.size_t
	s := lua.luaL_checklstring(L, 1, &l1)
	p := lua.luaL_checklstring(L, 2, &l2)
	init := posrelat(lua.luaL_optinteger(L, 3, 1), l1) - 1
	if init < 0 {
		init = 0
	} else if c.size_t(init) > l1 {
		init = int(l1)
	}

	ms: MatchState
	p_ptr := cast([^]u8)p
	anchor := false
	if p_ptr[0] == '^' {
		anchor = true
		p_ptr = &(p_ptr[1])
	}
	s_ptr := cast([^]u8)s
	s1 := &(s_ptr[init])
	ms.L = L
	ms.src_init = s
	ms.src_end = cstring(&(s_ptr[l1]))

	for {
		ms.level = 0
		res := match(&ms, cstring(rawptr(s1)), cstring(rawptr(p_ptr)))
		if res != nil {
			return push_captures(&ms, cstring(rawptr(s1)), res)
		}
		s1_arr := cast([^]u8)s1
		s1 = &(s1_arr[1])
		if !(uintptr(rawptr(s1)) <= uintptr(rawptr(ms.src_end)) && !anchor) {
			break
		}
	}
	lua.lua_pushnil(L)
	return 1
}

gmatch_aux :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	ms: MatchState
	ls: c.size_t
	s := lua.lua_tolstring(L, lua.lua_upvalueindex(1), &ls)
	p := lua.lua_tostring(L, lua.lua_upvalueindex(2))
	s_ptr := cast([^]u8)s
	p_ptr := cast([^]u8)p

	ms.L = L
	ms.src_init = s
	ms.src_end = cstring(&(s_ptr[ls]))

	start_idx := lua.lua_tointeger(L, lua.lua_upvalueindex(3))
	src_ptr := &(s_ptr[start_idx])

	for uintptr(rawptr(src_ptr)) <= uintptr(rawptr(ms.src_end)) {
		ms.level = 0
		e := match(&ms, cstring(rawptr(src_ptr)), p)
		if e != nil {
			e_ptr := cast([^]u8)e
			newstart := int(uintptr(rawptr(e_ptr)) - uintptr(rawptr(s_ptr)))
			if e_ptr == src_ptr {
				newstart += 1 // empty match? go at least one position
			}
			lua.lua_pushinteger(L, newstart)
			lua.lua_replace(L, lua.lua_upvalueindex(3))
			return push_captures(&ms, cstring(rawptr(src_ptr)), e)
		}
		if uintptr(rawptr(src_ptr)) == uintptr(rawptr(ms.src_end)) {
			break
		}
		src_ptr_arr := cast([^]u8)src_ptr
		src_ptr = &(src_ptr_arr[1])
	}

	return 0 // not found
}

gmatch :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	lua.luaL_checkstring(L, 1)
	lua.luaL_checkstring(L, 2)
	lua.lua_settop(L, 2)
	lua.lua_pushinteger(L, 0)
	lua.lua_pushcclosure(L, gmatch_aux, 3)
	return 1
}

add_s :: proc "c" (ms: ^MatchState, b: ^lua.Buffer, s: cstring, e: cstring) {
	context = runtime.default_context()
	l: c.size_t
	news := lua.lua_tolstring(ms.L, 3, &l)
	news_ptr := cast([^]u8)news
	for i: c.size_t = 0; i < l; i += 1 {
		if news_ptr[i] != L_ESC {
			lua.luaL_addlstring(b, cstring(&(news_ptr[i])), 1)
		} else {
			i += 1 // skip ESC
			if libc.isdigit(c.int(news_ptr[i])) == 0 {
				lua.luaL_addlstring(b, cstring(&(news_ptr[i])), 1)
			} else if news_ptr[i] == '0' {
				s_ptr := cast([^]u8)s
				e_ptr := cast([^]u8)e
				lua.luaL_addlstring(
					b,
					s,
					c.size_t(uintptr(rawptr(e_ptr)) - uintptr(rawptr(s_ptr))),
				)
			} else {
				push_onecapture(ms, c.int(news_ptr[i] - '1'), s, e)
				lua.luaL_addvalue(b)
			}
		}
	}
}

add_value :: proc "c" (ms: ^MatchState, b: ^lua.Buffer, s: cstring, e: cstring) {
	context = runtime.default_context()
	L := ms.L
	type := lua.lua_type(L, 3)
	switch type {
	case lua.LUA_TNUMBER, lua.LUA_TSTRING:
		add_s(ms, b, s, e)
		return
	case lua.LUA_TFUNCTION:
		lua.lua_pushvalue(L, 3)
		n := push_captures(ms, s, e)
		lua.lua_call(L, n, 1)
	case lua.LUA_TTABLE:
		push_onecapture(ms, 0, s, e)
		lua.lua_gettable(L, 3)
	}

	if lua.lua_toboolean(L, -1) == 0 && lua.lua_type(L, -1) == lua.LUA_TNIL {
		lua.lua_pop(L, 1)
		s_ptr := cast([^]u8)s
		e_ptr := cast([^]u8)e
		lua.lua_pushlstring(L, s, c.size_t(uintptr(rawptr(e_ptr)) - uintptr(rawptr(s_ptr))))
	} else if lua.lua_type(L, -1) != lua.LUA_TSTRING && lua.lua_type(L, -1) != lua.LUA_TNUMBER {
		lua.luaL_error(L, "invalid replacement value (a %s)", lua.lua_typename(L, -1))
	}
	lua.luaL_addvalue(b)
}

str_gsub :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	srcl: c.size_t
	src := lua.luaL_checklstring(L, 1, &srcl)
	p := lua.luaL_checkstring(L, 2)
	tr := lua.lua_type(L, 3)
	max_s := int(lua.luaL_optint(L, 4, c.int(srcl + 1)))

	p_ptr := cast([^]u8)p
	anchor := false
	if p_ptr[0] == '^' {
		anchor = true
		p_ptr = &(p_ptr[1])
	}

	n := 0
	ms: MatchState
	b: lua.Buffer

	if !(tr == lua.LUA_TNUMBER ||
		   tr == lua.LUA_TSTRING ||
		   tr == lua.LUA_TFUNCTION ||
		   tr == lua.LUA_TTABLE) {
		lua.luaL_argerror(L, 3, "string/function/table expected")
	}

	lua.luaL_buffinit(L, &b)
	ms.L = L
	ms.src_init = src
	src_base_ptr := cast([^]u8)src
	ms.src_end = cstring(&(src_base_ptr[srcl]))

	curr_src := src_base_ptr
	for n < max_s {
		ms.level = 0
		e := match(&ms, cstring(rawptr(curr_src)), cstring(rawptr(p_ptr)))
		if e != nil {
			n += 1
			add_value(&ms, &b, cstring(rawptr(curr_src)), e)
			e_ptr := cast([^]u8)e
			if e_ptr > curr_src {
				curr_src = e_ptr
			} else if uintptr(rawptr(curr_src)) < uintptr(rawptr(ms.src_end)) {
				lua.luaL_addlstring(&b, cstring(rawptr(curr_src)), 1)
				curr_src_arr := cast([^]u8)curr_src
				curr_src = &(curr_src_arr[1])
			} else {
				break
			}
		} else if uintptr(rawptr(curr_src)) < uintptr(rawptr(ms.src_end)) {
			lua.luaL_addlstring(&b, cstring(rawptr(curr_src)), 1)
			curr_src_arr := cast([^]u8)curr_src
			curr_src = &(curr_src_arr[1])
		} else {
			break
		}
		if anchor {
			break
		}
	}

	lua.luaL_addlstring(
		&b,
		cstring(rawptr(curr_src)),
		c.size_t(uintptr(rawptr(ms.src_end)) - uintptr(rawptr(curr_src))),
	)
	lua.luaL_pushresult(&b)
	lua.lua_pushinteger(L, n)
	return 2
}

str_sub :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	l: c.size_t
	s := lua.luaL_checklstring(L, 1, &l)
	start := posrelat(lua.luaL_optinteger(L, 2, 1), l)
	end := posrelat(lua.luaL_optinteger(L, 3, -1), l)
	if start < 1 {
		start = 1
	}
	if end > int(l) {
		end = int(l)
	}
	if start <= end {
		s_ptr := cast([^]u8)s
		lua.lua_pushlstring(L, cstring(&(s_ptr[start - 1])), c.size_t(end - start + 1))
	} else {
		lua.lua_pushliteral(L, "")
	}
	return 1
}

// str_len
str_len :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	l: c.size_t
	lua.luaL_checklstring(L, 1, &l)
	lua.lua_pushinteger(L, int(l))
	return 1
}

// str_reverse
str_reverse :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	l: c.size_t
	s := lua.luaL_checklstring(L, 1, &l)

	// We need to construct a new string reversed
	// Use format "LualL_Buffer" for efficiency if exposed?
	// Or just use Odin strings and push back.
	// Given we just bound Lua Buffer, let's try to use it!

	b: lua.Buffer
	lua.luaL_buffinit(L, &b)

	// Iterate backwards
	ptr := uintptr(transmute(rawptr)s) + uintptr(l) - 1
	for i := 0; i < int(l); i += 1 {
		// We need a helper to add char. The macro check is:
		// ((B)->p < ((B)->buffer + LUAL_BUFFERSIZE) || luaL_prepbuffer(B))
		// (*(B)->p++ = (char)(c))

		// This is tricky to do in Odin without the macro.
		// Safer way: luaL_addlstring with 1 char. Slow but safe for now.
		char_ptr := cast(^u8)(ptr)
		lua.luaL_addlstring(&b, cstring(char_ptr), 1)
		ptr -= 1
	}

	lua.luaL_pushresult(&b)
	return 1
}

// str_lower
str_lower :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	l: c.size_t
	s := lua.luaL_checklstring(L, 1, &l)

	b: lua.Buffer
	lua.luaL_buffinit(L, &b)

	ptr := uintptr(transmute(rawptr)s)
	for i := 0; i < int(l); i += 1 {
		c_val := (cast(^u8)ptr)^
		lower := libc.tolower(c.int(c_val))

		// Add char
		// Again, using simplified addlstring for safety
		temp: u8 = u8(lower)
		lua.luaL_addlstring(&b, cstring(&temp), 1)

		ptr += 1
	}
	lua.luaL_pushresult(&b)
	return 1
}

// str_upper
str_upper :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	l: c.size_t
	s := lua.luaL_checklstring(L, 1, &l)

	b: lua.Buffer
	lua.luaL_buffinit(L, &b)

	ptr := uintptr(transmute(rawptr)s)
	for i := 0; i < int(l); i += 1 {
		c_val := (cast(^u8)ptr)^
		upper := libc.toupper(c.int(c_val))

		temp: u8 = u8(upper)
		lua.luaL_addlstring(&b, cstring(&temp), 1)

		ptr += 1
	}
	lua.luaL_pushresult(&b)
	return 1
}

// str_rep
str_rep :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	l: c.size_t
	s := lua.luaL_checklstring(L, 1, &l)
	n := lua.luaL_checkinteger(L, 2)

	b: lua.Buffer
	lua.luaL_buffinit(L, &b)

	for i := 0; i < n; i += 1 {
		lua.luaL_addlstring(&b, s, l)
	}

	lua.luaL_pushresult(&b)
	return 1
}

// str_char (variable args)
str_char :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	n := lua.lua_gettop(L) // number of args

	b: lua.Buffer
	lua.luaL_buffinit(L, &b)

	for i := 1; i <= int(n); i += 1 {
		c_val := lua.luaL_checkinteger(L, c.int(i))
		// luaL_argcheck is a macro expanding to: ((void)((cond) || luaL_argerror(L, (numarg), (extramsg))))
		if !(u8(c_val) == u8(c_val)) { 	// This check seems redundant if c_val fits in u8?
			// In C: luaL_argcheck(L, (unsigned char)c == c, i, "value out of range");
			// If c is an integer, check if it fits in byte.
			lua.luaL_argerror(L, c.int(i), "value out of range")
		}
		// Actually, we must cast to check if truncation occurs
		if c_val != lua.Integer(u8(c_val)) {
			lua.luaL_argerror(L, c.int(i), "value out of range")
		}

		temp: u8 = u8(c_val)
		lua.luaL_addlstring(&b, cstring(&temp), 1)
	}
	lua.luaL_pushresult(&b)
	return 1
}


// str_byte
str_byte :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	l: c.size_t
	s := lua.luaL_checklstring(L, 1, &l)
	pi := lua.luaL_optinteger(L, 2, 1)
	pose := lua.luaL_optinteger(L, 3, pi)

	if pi < 0 {pi += int(l) + 1}
	if pose < 0 {pose += int(l) + 1}
	if pi <= 0 {pi = 1}
	if pose > int(l) {pose = int(l)}
	if pi > pose {return 0} 	// empty interval

	n := pose - pi + 1
	// check stack? luaL_checkstack(L, n, "string slice too long")

	ptr := uintptr(transmute(rawptr)s) + uintptr(pi) - 1
	for i := 0; i < n; i += 1 {
		c_val := (cast(^u8)ptr)^
		lua.lua_pushinteger(L, int(c_val))
		ptr += 1
	}
	return c.int(n)
}

writer :: proc "c" (L: ^lua.State, p: rawptr, sz: c.size_t, ud: rawptr) -> c.int {
	context = runtime.default_context()
	B := cast(^lua.Buffer)ud
	lua.luaL_addlstring(B, cstring(p), sz)
	return 0
}

str_dump :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	b: lua.Buffer
	lua.luaL_checktype(L, 1, lua.LUA_TFUNCTION)
	lua.lua_settop(L, 1)
	lua.luaL_buffinit(L, &b)
	if lua.lua_dump(L, writer, &b) != 0 {
		lua.luaL_error(L, "unable to dump given function")
	}
	lua.luaL_pushresult(&b)
	return 1
}

addquoted :: proc "c" (L: ^lua.State, b: ^lua.Buffer, arg: c.int) {
	context = runtime.default_context()
	l: c.size_t
	s := lua.luaL_checklstring(L, arg, &l)
	s_ptr := cast([^]u8)s
	lua.luaL_addlstring(b, "\"", 1)
	for i: c.size_t = 0; i < l; i += 1 {
		switch s_ptr[i] {
		case '"', '\\', '\n':
			lua.luaL_addlstring(b, "\\", 1)
			lua.luaL_addlstring(b, cstring(&(s_ptr[i])), 1)
		case '\r':
			lua.luaL_addlstring(b, "\\r", 2)
		case '\x00':
			lua.luaL_addlstring(b, "\\000", 4)
		case:
			lua.luaL_addlstring(b, cstring(&(s_ptr[i])), 1)
		}
	}
	lua.luaL_addlstring(b, "\"", 1)
}

scanformat :: proc "c" (L: ^lua.State, strfrmt: cstring, form: [^]u8) -> cstring {
	context = runtime.default_context()
	p := cast([^]u8)strfrmt
	for p[0] != '\x00' && libc.strchr(FLAGS, c.int(p[0])) != nil {
		p = &(p[1])
	}
	if uintptr(rawptr(p)) - uintptr(rawptr(strfrmt)) >= len(FLAGS) {
		lua.luaL_error(L, "invalid format (repeated flags)")
	}
	if libc.isdigit(c.int(p[0])) != 0 {
		p = &(p[1])
	}
	if libc.isdigit(c.int(p[0])) != 0 {
		p = &(p[1])
	}
	if p[0] == '.' {
		p = &(p[1])
		if libc.isdigit(c.int(p[0])) != 0 {
			p = &(p[1])
		}
		if libc.isdigit(c.int(p[0])) != 0 {
			p = &(p[1])
		}
	}
	if libc.isdigit(c.int(p[0])) != 0 {
		lua.luaL_error(L, "invalid format (width or precision too long)")
	}
	form[0] = '%'
	len_fmt := uintptr(rawptr(p)) - uintptr(rawptr(strfrmt)) + 1
	mem.copy(rawptr(&(form[1])), rawptr(strfrmt), int(len_fmt))
	form[len_fmt + 1] = '\x00'
	return cstring(rawptr(p))
}

addintlen :: proc "c" (form: [^]u8) {
	context = runtime.default_context()
	l := libc.strlen(cast(cstring)rawptr(form))
	spec := form[l - 1]
	// In Luam it seems LUA_INTFRMLEN is "l"
	form[l - 1] = 'l'
	form[l] = spec
	form[l + 1] = '\x00'
}

str_format :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	top := lua.lua_gettop(L)
	arg := 1
	sfl: c.size_t
	strfrmt := lua.luaL_checklstring(L, c.int(arg), &sfl)
	strfrmt_ptr := cast([^]u8)strfrmt
	strfrmt_end := &(strfrmt_ptr[sfl])

	b: lua.Buffer
	lua.luaL_buffinit(L, &b)

	p := strfrmt_ptr
	for uintptr(rawptr(p)) < uintptr(rawptr(strfrmt_end)) {
		if p[0] != L_ESC {
			lua.luaL_addlstring(&b, cstring(rawptr(p)), 1)
			p = &(p[1])
		} else if p[1] == L_ESC {
			lua.luaL_addlstring(&b, cstring(rawptr(p)), 1)
			p = &(p[2])
		} else {
			p = &(p[1]) // skip ESC
			arg += 1
			if arg > int(top) {
				lua.luaL_argerror(L, c.int(arg), "no value")
			}
			form: [MAX_FORMAT]u8
			buff: [MAX_ITEM]u8

			next_p := scanformat(L, cstring(rawptr(p)), &form[0])
			p = cast([^]u8)next_p
			ch := p[0]
			p = &(p[1])

			switch ch {
			case 'c':
				lua.sprintf(
					cast([^]u8)(&buff[0]),
					cstring(&form[0]),
					cast(c.int)lua.luaL_checknumber(L, c.int(arg)),
				)
			case 'd', 'i':
				addintlen(cast([^]u8)(&form[0]))
				lua.sprintf(
					cast([^]u8)(&buff[0]),
					cstring(&form[0]),
					cast(c.long)lua.luaL_checknumber(L, c.int(arg)),
				)
			case 'o', 'u', 'x', 'X':
				addintlen(cast([^]u8)(&form[0]))
				lua.sprintf(
					cast([^]u8)(&buff[0]),
					cstring(&form[0]),
					cast(c.ulong)lua.luaL_checknumber(L, c.int(arg)),
				)
			case 'e', 'E', 'f', 'g', 'G':
				lua.sprintf(
					cast([^]u8)(&buff[0]),
					cstring(&form[0]),
					cast(f64)lua.luaL_checknumber(L, c.int(arg)),
				)
			case 'q':
				addquoted(L, &b, c.int(arg))
				continue
			case 's':
				l: c.size_t
				s := lua.luaL_checklstring(L, c.int(arg), &l)
				if libc.strchr(cast(cstring)(&form[0]), '.') == nil && l >= 100 {
					lua.lua_pushvalue(L, c.int(arg))
					lua.luaL_addvalue(&b)
					continue
				} else {
					lua.sprintf(cast([^]u8)(&buff[0]), cstring(&form[0]), s)
				}
			case:
				lua.luaL_error(L, "invalid option '%%%c' to 'format'", ch)
			}
			lua.luaL_addlstring(&b, cstring(&buff[0]), libc.strlen(cast(cstring)(&buff[0])))
		}
	}

	lua.luaL_pushresult(&b)
	return 1
}

createmetatable :: proc "c" (L: ^lua.State) {
	context = runtime.default_context()
	lua.lua_createtable(L, 0, 1) // metatable for strings
	lua.lua_pushliteral(L, "") // dummy string
	lua.lua_pushvalue(L, -2)
	lua.lua_setmetatable(L, -2) // set metatable for dummy string (and all strings)
	lua.lua_pop(L, 1) // pop dummy
	lua.lua_pushvalue(L, -2) // push string library
	lua.lua_setfield(L, -2, "__index")
	lua.lua_pop(L, 1) // pop metatable
}


@(export, link_name = "luaopen_string")
open_string :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	strlib := [?]lua.Reg {
		{"len", str_len},
		{"reverse", str_reverse},
		{"lower", str_lower},
		{"upper", str_upper},
		{"rep", str_rep},
		{"char", str_char},
		{"byte", str_byte},
		{"sub", str_sub},
		{"find", str_find},
		{"match", str_match},
		{"gsub", str_gsub},
		{"gmatch", gmatch},
		{"format", str_format},
		{"dump", str_dump},
		{nil, nil},
	}

	lua.luaL_register(L, "string", &strlib[0])
	createmetatable(L)
	return 1
}
