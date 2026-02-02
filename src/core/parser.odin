package core

import "base:runtime"
import "core:c"
import "core:mem"
import "core:strings"

// --- Constants from llimits.h and luaconf.h ---
LUAI_MAXUPVALUES :: 60
LUAI_MAXVARS :: 200
// LUAI_MAXCCALLS :: 200 // Already defined in do.odin

// --- Enums ---

// Expression kind (expkind)
expkind :: enum c.int {
	VVOID, /* no value */
	VNIL,
	VTRUE,
	VFALSE,
	VK, /* info = index of constant in `k' */
	VKNUM, /* nval = numerical value */
	VLOCAL, /* info = local register */
	VUPVAL, /* info = index of upvalue in `upvalues' */
	VGLOBAL, /* info = index of table; aux = index of global name in `k' */
	VINDEXED, /* info = table register; aux = index register (or `k') */
	VJMP, /* info = instruction pc */
	VRELOCABLE, /* info = instruction pc */
	VNONRELOC, /* info = result register */
	VCALL, /* info = instruction pc */
	VVARARG, /* info = instruction pc */
}

// Inferred type for local variables (from lparser.h)
InferredType :: enum c.int {
	INFERRED_UNKNOWN,
	INFERRED_NIL,
	INFERRED_BOOLEAN,
	INFERRED_NUMBER,
	INFERRED_STRING,
	INFERRED_TABLE,
	INFERRED_FUNCTION,
}

// Binary Operators (from lcode.h)
BinOpr :: enum c.int {
	OPR_ADD,
	OPR_SUB,
	OPR_MUL,
	OPR_DIV,
	OPR_MOD,
	OPR_POW,
	OPR_CONCAT,
	OPR_NE,
	OPR_EQ,
	OPR_LT,
	OPR_LE,
	OPR_GT,
	OPR_GE,
	OPR_AND,
	OPR_OR,
	OPR_NOBINOPR,
}

// Unary Operators (from lcode.h)
UnOpr :: enum c.int {
	OPR_MINUS,
	OPR_NOT,
	OPR_LEN,
	OPR_NOUNOPR,
}

// --- Structs ---

// expdesc (Expression Descriptor)
expdesc :: struct {
	k:        expkind,
	u:        struct #raw_union {
		s:    struct {
			info, aux: c.int,
		},
		nval: lua_Number,
	},
	t:        c.int, /* patch list of `exit when true' */
	f:        c.int, /* patch list of `exit when false' */
	inferred: InferredType,
}

// upvaldesc
upvaldesc :: struct {
	k:    u8,
	info: u8,
}

// BlockCnt (Block Context)
BlockCnt :: struct {
	previous:    ^BlockCnt, /* chain */
	breaklist:   c.int, /* list of jumps out of this loop */
	nactvar:     u8, /* # active locals outside the breakable structure */
	upval:       u8, /* true if some variable in the block is an upvalue */
	isbreakable: u8, /* true if `block' is a loop */
}

// LHS_assign (Left-Hand Side of an assignment)
LHS_assign :: struct {
	prev: ^LHS_assign,
	v:    expdesc, /* variable (global, local, upvalue, or indexed) */
}

// FuncState (Function State)
// Must match C layout exactly for lcode.o compatibility
FuncState :: struct {
	f:           ^Proto, /* current function header */
	h:           ^Table, /* table to find (and reuse) elements in `k' */
	prev:        ^FuncState, /* enclosing function */
	ls:          ^LexState, /* lexical state */
	L:           ^lua_State, /* copy of the Lua state */
	bl:          ^BlockCnt, /* chain of current blocks */
	pc:          c.int, /* next position to code (equivalent to `ncode') */
	lasttarget:  c.int, /* `pc' of last `jump target' */
	jpc:         c.int, /* list of pending jumps to `pc' */
	freereg:     c.int, /* first free register */
	nk:          c.int, /* number of elements in `k' */
	np:          c.int, /* number of elements in `p' */
	nlocvars:    c.short, /* number of elements in `locvars' */
	nactvar:     u8, /* number of active local variables */
	upvalues:    [LUAI_MAXUPVALUES]upvaldesc, /* upvalues */
	actvar:      [LUAI_MAXVARS]c.ushort, /* declared-variable stack */
	actvartypes: [LUAI_MAXVARS]InferredType, /* inferred types for locals */
}


// --- Foreign Imports (lcode, etc) ---
// Linking against GCC compiled objects, we need to match the symbol names.
// lcode.c functions are usually LUAI_FUNC which means 'extern' or 'hidden'.
// If they are hidden, we might have linking issues if we don't link correct objects.
// Assuming we link against 'liblua.a' or objects directly.

foreign import lua_core "../../obj/liblua.a"

foreign lua_core {
	// luaK functions are now in code.odin

	// lfunc functions
	// luaF_newproto imported from func.odin

	// lgc functions
	// luaC_barrierf and luaC_step imported from gc.odin

	// lmem functions (if not ported) or use mem.odin
	// luaM_realloc_ :: proc(L: ^lua_State, block: rawptr, osize: c.size_t, nsize: c.size_t) -> rawptr ---
}

// Imports from other files in package core
// (These are implicit since we are in the same package)
// luaM_reallocvector is a wrapper in mem.odin usually?
// logic: reallocvector(L, v, oldn, n, t) -> cast(^t)luaM_realloc_(L, v, oldn*size_of(t), n*size_of(t))

luaM_growvector :: proc(
	L: ^lua_State,
	v: rawptr,
	nelems: c.int,
	size_ptr: ^c.int,
	type_size: int,
	limit: c.int,
	e: cstring,
) -> rawptr {
	// Macro logic: if (nelems + 1 > size) ...
	// Note: 'size' is passed by value in macro but updated via pointer in growaux.
	// BUT the macro in C takes &(size).
	// Here we pass 'size' as value. This helper function seems to assume it returns the new pointer.
	// BUT it needs to update the size variable in the struct!
	// The C macro: ((v)=cast(t *, luaM_growaux_(L,v,&(size),sizeof(t),limit,e)))
	// implies 'size' is an lvalue.
	// In Odin, we probably can't easily replicate the macro's side effect on 'size' unless we pass a pointer to it.
	// So my definition of luaM_growvector signature was slightly wrong if I wanted it to update size.
	// Let's change strictly to what is needed.
	// In Lparser.c usage:
	// luaM_growvector(ls->L, f->locvars, fs->nlocvars, f->sizelocvars, LocVar, SHRT_MAX, "too many local variables");
	// f->sizelocvars is the size variable.

	// So I should change the signature to take a pointer to size.
	return nil // Placeholder, function signature change required
}

// Actual implementation with pointer to size
grow_vector :: proc(
	L: ^lua_State,
	v: rawptr,
	nelems: c.int,
	size_ptr: ^c.int,
	type_size: int,
	limit: c.int,
	e: cstring,
) -> rawptr {
	if nelems + 1 > size_ptr^ {
		old_size := size_ptr^
		v := luaM_growaux_(L, v, size_ptr, c.size_t(type_size), limit, e)
		if type_size == size_of(LocVar) {
			f := cast([^]LocVar)v
			for i := old_size; i < size_ptr^; i += 1 {
				f[i].varname = nil
			}
		}
		return v
	}
	return v
}


// Macro replacements (helpers)
@(private)
enterblock :: proc(fs: ^FuncState, bl: ^BlockCnt, isbreakable: u8) {
	bl.breaklist = NO_JUMP
	bl.isbreakable = isbreakable
	bl.nactvar = fs.nactvar
	bl.upval = 0
	bl.previous = fs.bl
	fs.bl = bl
	// assert(fs.freereg == c.int(fs.nactvar))
}

@(private)
leaveblock :: proc(fs: ^FuncState) {
	bl := fs.bl
	fs.bl = bl.previous
	removevars(cast(^LexState)fs.ls, int(bl.nactvar))
	if bl.upval != 0 {
		luaK_codeABC(fs, .OP_CLOSE, int(bl.nactvar), 0, 0)
	}
	// assert(!bl.isbreakable || !bl.upval)
	// assert(bl.nactvar == fs.nactvar)
	fs.freereg = c.int(bl.nactvar) // free registers
	luaK_patchtohere(fs, bl.breaklist)
}

hasmultret :: #force_inline proc(k: expkind) -> bool {
	return k == .VCALL || k == .VVARARG
}

getlocvar :: #force_inline proc(fs: ^FuncState, i: int) -> ^LocVar {
	// ((fs)->f->locvars[(fs)->actvar[i]])
	idx := fs.actvar[i]
	return &fs.f.locvars[idx]
}

luaY_checklimit :: proc(fs: ^FuncState, v: int, l: int, m: cstring) {
	if v > l {
		errorlimit(fs, l, m)
	}
}

// --- Internal Functions ---

// Macros replacement
sethvalue2s :: #force_inline proc(L: ^lua_State, o: ^TValue, h: ^Table) {
	setgcvalue(o, cast(^GCObject)h, LUA_TTABLE)
}

setptvalue2s :: #force_inline proc(L: ^lua_State, o: ^TValue, p: ^Proto) {
	setgcvalue(o, cast(^GCObject)p, LUA_TPROTO)
}

@(private)
errorlimit :: proc(fs: ^FuncState, limit: int, what: cstring) {
	L := fs.L
	msg: cstring
	if fs.f.linedefined == 0 {
		msg = luaO_pushfstring(L, "main function has more than %d %s", cast(c.int)limit, what)
	} else {
		msg = luaO_pushfstring(
			L,
			"function at line %d has more than %d %s",
			fs.f.linedefined,
			cast(c.int)limit,
			what,
		)
	}
	luaX_lexerror(fs.ls, msg, 0)
}

@(private)
anchor_token :: proc(ls: ^LexState) {
	if ls.t.token == TK_NAME || ls.t.token == TK_STRING {
		ts := ls.t.seminfo.ts
		luaX_newstring(ls, getstr(ts), ts.tsv.len)
	}
}

@(private)
registerlocalvar :: proc(ls: ^LexState, varname: ^TString) -> int {
	fs := cast(^FuncState)ls.fs
	f := fs.f
	f.locvars = cast([^]LocVar)grow_vector(
		ls.L,
		rawptr(f.locvars),
		c.int(fs.nlocvars),
		&f.sizelocvars,
		size_of(LocVar),
		c.int(max(c.short)),
		"too many local variables",
	)
	f.locvars[fs.nlocvars].varname = varname
	luaC_barrierf(ls.L, cast(^GCObject)f, cast(^GCObject)varname)
	res := int(fs.nlocvars)
	fs.nlocvars += 1
	return res
}

@(private)
is_const_aux :: proc(fs: ^FuncState, k: expkind, info: int) -> bool {
	if k == .VLOCAL {
		return getlocvar(fs, info).is_const != 0
	} else if k == .VUPVAL {
		idx := info
		return is_const_aux(fs.prev, expkind(fs.upvalues[idx].k), int(fs.upvalues[idx].info))
	}
	return false
}

@(private)
is_const :: proc(fs: ^FuncState, v: ^expdesc) -> bool {
	if v.k == .VLOCAL {
		return getlocvar(fs, int(v.u.s.info)).is_const != 0
	} else if v.k == .VUPVAL {
		idx := int(v.u.s.info)
		return is_const_aux(fs.prev, expkind(fs.upvalues[idx].k), int(fs.upvalues[idx].info))
	}
	return false
}

@(private)
check_readonly :: proc(ls: ^LexState, v: ^expdesc) {
	if is_const(cast(^FuncState)ls.fs, v) {
		luaX_syntaxerror(ls, "attempt to assign to const variable")
	}
}

@(private)
check_conflict :: proc(ls: ^LexState, lh: ^LHS_assign, v: ^expdesc) {
	fs := cast(^FuncState)ls.fs
	extra := fs.freereg // temporary register
	conflict := false
	lh := lh
	for lh != nil {
		if lh.v.k == .VINDEXED {
			if lh.v.u.s.info == v.u.s.info { 	// conflict with base
				conflict = true
				lh.v.u.s.info = extra
			}
			if lh.v.u.s.aux == v.u.s.info { 	// conflict with index
				conflict = true
				lh.v.u.s.aux = extra
			}
		}
		lh = lh.prev
	}
	if conflict {
		luaK_codeABC(fs, .OP_MOVE, int(fs.freereg), int(v.u.s.info), 0)
		luaK_reserveregs(fs, 1)
	}
}

@(private)
markupval :: proc(fs: ^FuncState, level: int) {
	bl := fs.bl
	for bl != nil && int(bl.nactvar) > level {
		bl = bl.previous
	}
	if bl != nil {
		bl.upval = 1
	}
}

@(private)
indexupvalue :: proc(fs: ^FuncState, name: ^TString, v: ^expdesc) -> int {
	f := fs.f
	for i in 0 ..< int(f.nups) {
		if fs.upvalues[i].k == u8(v.k) && fs.upvalues[i].info == u8(v.u.s.info) {
			// assert(f.upvalues[i] == name)
			return i
		}
	}
	/* new one */
	luaY_checklimit(fs, int(f.nups) + 1, LUAI_MAXUPVALUES, "upvalues")
	// grow upvalues in Proto
	f.upvalues = cast([^]^TString)grow_vector(
		fs.L,
		rawptr(f.upvalues),
		c.int(f.nups),
		&f.sizeupvalues,
		size_of(^TString),
		LUAI_MAXUPVALUES,
		"upvalues overflow",
	)
	f.upvalues[f.nups] = name
	luaC_barrierf(fs.L, cast(^GCObject)f, cast(^GCObject)name)
	// fs.upvalues is fixed size array in Odin, so just fill it
	fs.upvalues[f.nups].k = u8(v.k)
	fs.upvalues[f.nups].info = u8(v.u.s.info)
	res := int(f.nups)
	f.nups += 1
	return res
}

@(private)
enterlevel :: proc(ls: ^LexState) {
	L := ls.L
	L.nCcalls += 1
	if L.nCcalls > LUAI_MAXCCALLS {
		luaX_lexerror(ls, "chunk has too many syntax levels", 0)
	}
}

leavelevel :: #force_inline proc(ls: ^LexState) {
	ls.L.nCcalls -= 1
}

@(private)
open_func :: proc(ls: ^LexState, fs: ^FuncState) {
	L := ls.L
	f := luaF_newproto(L)
	fs.f = f
	fs.prev = cast(^FuncState)ls.fs // linked list of funcstates
	fs.ls = ls
	fs.L = L
	ls.fs = cast(rawptr)fs

	fs.pc = 0
	fs.lasttarget = -1
	fs.jpc = -1 // NO_JUMP
	fs.freereg = 0
	fs.nk = 0
	fs.np = 0
	fs.nlocvars = 0
	fs.nactvar = 0
	fs.bl = nil
	f.source = ls.source
	f.maxstacksize = 2 // registers 0/1 are always valid
	fs.h = luaH_new(L, 0, 0)

	// anchor table of constants and prototype (to avoid being collected)
	sethvalue2s(L, L.top, fs.h)
	incr_top(L)
	setptvalue2s(L, L.top, f)
	incr_top(L)
}

@(private)
close_func :: proc(ls: ^LexState) {
	L := ls.L
	fs := cast(^FuncState)ls.fs
	f := fs.f
	removevars(ls, 0)
	luaK_ret(fs, 0, 0) // final return

	f.code = cast([^]Instruction)luaM_reallocvector(
		L,
		f.code,
		int(f.sizecode),
		int(fs.pc),
		Instruction,
	)
	f.sizecode = c.int(fs.pc)

	f.lineinfo = cast([^]c.int)luaM_reallocvector(
		L,
		f.lineinfo,
		int(f.sizelineinfo),
		int(fs.pc),
		c.int,
	)
	f.sizelineinfo = c.int(fs.pc)

	f.k = cast([^]TValue)luaM_reallocvector(L, f.k, int(f.sizek), int(fs.nk), TValue)
	f.sizek = c.int(fs.nk)

	f.p = cast([^]^Proto)luaM_reallocvector(L, f.p, int(f.sizep), int(fs.np), ^Proto)
	f.sizep = c.int(fs.np)

	f.locvars = cast([^]LocVar)luaM_reallocvector(
		L,
		f.locvars,
		int(f.sizelocvars),
		int(fs.nlocvars),
		LocVar,
	)
	f.sizelocvars = c.int(fs.nlocvars)

	f.upvalues = cast([^]^TString)luaM_reallocvector(
		L,
		f.upvalues,
		int(f.sizeupvalues),
		int(f.nups),
		^TString,
	)
	f.sizeupvalues = c.int(f.nups)

	// lua_assert(luaG_checkcode(f));
	// lua_assert(fs->bl == NULL);
	ls.fs = cast(rawptr)fs.prev

	// last token read was anchored in defunct function; must reanchor it
	if ls.fs != nil { 	// fs != NULL check from C (if fs != NULL) - wait, fs is the current one we are closing.
		// Logic in C: if (fs) anchor_token(ls);
		// But we just popped fs from ls->fs.
		// Wait, C code: ls->fs = fs->prev; if (fs) anchor...
		// But 'fs' variable still holds the closed funcstate.
		// Actually, if we closed the main function, fs->prev is NULL.
		// But 'fs' itself is valid until we leave.
		// However, the check `if (fs)` in C is checking if we HAVE a funcstate to anchor to?
		// No, `fs` is the one we just closed.
		// The point of anchor_token is to save the LAST token read (which triggered close) into the CURRENT function state (which is now fs->prev).
		// So we should check if `ls.fs` (which is now fs.prev) is not nil.
		// C code: does `fs` refer to the NEW current state? No, `fs` is the local variable for the old state.
		// Lparser.c:
		// ls->fs = fs->prev;
		// if (fs) anchor_token(ls); <-- This looks suspicious if anchor_token uses ls->fs.
		// }
		// static void anchor_token (LexState *ls) {
		// if (ls->t.token == TK_NAME || ls->t.token == TK_STRING) {
		// TString *ts = ls->t.seminfo.ts;
		// luaX_newstring(ls, getstr(ts), ts.tsv.len);
		// }
		// }
		// luaX_newstring uses ls->fs => "TValue *o = luaH_setstr(L, ls->fs->h, ts);"
		// So if `ls->fs` is NULL (we closed the main function), `luaX_newstring` will crash or fail?
		// But main function is only closed at end of parse.
		// `chunk` calls `close_func`.
		// If we act like C, we call `anchor_token` which calls `luaX_newstring`.
		// My `luaX_newstring` implementation (in previous tool output) checked `if ls.fs != nil`.
		// So it is safe.
		// But the condition `if fs` in C seems to imply `if (ls->fs)`? No `fs` is local.
		// Maybe C code meant `if (ls->fs)`? Or maybe `fs` was reused?
		// Actually the C code shown in some versions:
		// transform `fs` to `ls->fs`.
		// Let's assume the intent is to anchor if there is a parent function.
		anchor_token(ls)
	}
	L.top = cast(StkId)(cast(uintptr)L.top - 2 * size_of(TValue)) // pop table and prototype
}

@(private)
chunk :: proc(ls: ^LexState) {
	// enterlevel(ls);
	islast := false
	statement(ls)
	for !islast && !block_follow(ls.t.token) {
		statement(ls)
	}
	// leavelevel(ls);
}

@(private)
block_follow :: proc(token: c.int) -> bool {
	switch token {
	case TK_ELSE, TK_ELSEIF, TK_END, TK_UNTIL, TK_EOS:
		return true
	case:
		return false
	}
}


// --- Operator Priorities ---

Priority :: struct {
	left:  u8,
	right: u8,
}

UNARY_PRIORITY :: 8

priority := [BinOpr]Priority {
	.OPR_ADD      = {6, 6},
	.OPR_SUB      = {6, 6},
	.OPR_MUL      = {7, 7},
	.OPR_DIV      = {7, 7},
	.OPR_MOD      = {7, 7},
	.OPR_POW      = {10, 9},
	.OPR_CONCAT   = {5, 4},
	.OPR_EQ       = {3, 3},
	.OPR_NE       = {3, 3},
	.OPR_LT       = {3, 3},
	.OPR_LE       = {3, 3},
	.OPR_GT       = {3, 3},
	.OPR_GE       = {3, 3},
	.OPR_AND      = {2, 2},
	.OPR_OR       = {1, 1},
	.OPR_NOBINOPR = {0, 0},
}

@(private)
getunopr :: proc(op: c.int) -> UnOpr {
	switch op {
	case TK_NOT:
		return .OPR_NOT
	case '-':
		return .OPR_MINUS
	case '#':
		return .OPR_LEN
	case:
		return .OPR_NOUNOPR
	}
}

@(private)
getbinopr :: proc(op: c.int) -> BinOpr {
	switch op {
	case '+':
		return .OPR_ADD
	case '-':
		return .OPR_SUB
	case '*':
		return .OPR_MUL
	case '/':
		return .OPR_DIV
	case '%':
		return .OPR_MOD
	case '^':
		return .OPR_POW
	case TK_CONCAT:
		return .OPR_CONCAT
	case TK_NE:
		return .OPR_NE
	case TK_EQ:
		return .OPR_EQ
	case '<':
		return .OPR_LT
	case TK_LE:
		return .OPR_LE
	case '>':
		return .OPR_GT
	case TK_GE:
		return .OPR_GE
	case TK_AND:
		return .OPR_AND
	case TK_OR:
		return .OPR_OR
	case:
		return .OPR_NOBINOPR
	}
}


// Helper: testnext
@(private)
testnext :: proc(ls: ^LexState, c: c.int) -> bool {
	if ls.t.token == c {
		luaX_next(ls)
		return true
	}
	return false
}

// Helper: check_match
@(private)
check_match :: proc(ls: ^LexState, what, who: c.int, where_line: c.int) {
	if !testnext(ls, what) {
		if where_line == ls.linenumber {
			error_expected(ls, what)
		} else {
			luaX_syntaxerror(
				ls,
				luaO_pushfstring(
					ls.L,
					"%s expected (to close %s at line %d)",
					luaX_token2str(ls, what),
					luaX_token2str(ls, who),
					where_line,
				),
			)
		}
	}
}

@(private)
statement :: proc(ls: ^LexState) {
	line := ls.linenumber
	// enterlevel(ls)
	switch ls.t.token {
	case TK_IF:
		ifstat(ls, line)
	case TK_WHILE:
		whilestat(ls, line)
	case TK_DO:
		luaX_next(ls) // skip DO
		block(ls)
		check_match(ls, TK_END, TK_DO, line)
	case TK_FOR:
		forstat(ls, line)
	case TK_REPEAT:
		repeatstat(ls, line)
	case TK_FUNCTION:
		funcstat(ls, line)
	case TK_LOCAL:
		luaX_next(ls) // skip LOCAL
		if testnext(ls, TK_FUNCTION) {
			localfunc(ls)
		} else {
			localstat(ls)
		}
	case TK_DBCOLON:
		luaX_next(ls) // skip ::
		labelstat(ls, luaS_new(ls.L, getstr(str_checkname(ls))), line)
	case TK_RETURN:
		retstat(ls)
	case TK_BREAK:
		breakstat(ls)
	case ';':
		luaX_next(ls) // skip ;
	case:
		exprstat(ls)
	}
	// leavelevel(ls)
}

// --- Statement Implementations (Stubs for now) ---

@(private)
cond :: proc(ls: ^LexState) -> c.int {
	v: expdesc
	expr(ls, &v) /* read condition */
	if v.k == .VNIL do v.k = .VFALSE /* `nil' is false */
	luaK_goiftrue(cast(^FuncState)ls.fs, &v, 0)
	return v.f
}

@(private)
test_then_block :: proc(ls: ^LexState) -> c.int {
	/* test_then_block -> [IF | ELSEIF] cond THEN block */
	luaX_next(ls) /* skip IF or ELSEIF */
	condexit := cond(ls)
	checknext(ls, TK_THEN)
	block(ls) /* `then' part */
	return condexit
}

@(private)
ifstat :: proc(ls: ^LexState, line: c.int) {
	/* ifstat -> IF cond THEN block {ELSEIF cond THEN block} [ELSE block] END */
	fs := cast(^FuncState)ls.fs
	escapelist := c.int(NO_JUMP)
	flist := test_then_block(ls) /* IF cond THEN block */
	for ls.t.token == TK_ELSEIF {
		luaK_concat(fs, &escapelist, luaK_jump(fs))
		luaK_patchtohere(fs, flist)
		flist = test_then_block(ls) /* ELSEIF cond THEN block */
	}
	if ls.t.token == TK_ELSE {
		luaK_concat(fs, &escapelist, luaK_jump(fs))
		luaK_patchtohere(fs, flist)
		luaX_next(ls) /* skip ELSE */
		block(ls) /* `else' part */
	} else {
		luaK_concat(fs, &escapelist, flist)
	}
	luaK_patchtohere(fs, escapelist)
	check_match(ls, TK_END, TK_IF, line)
}

@(private)
whilestat :: proc(ls: ^LexState, line: c.int) {
	/* whilestat -> WHILE cond DO block END */
	fs := cast(^FuncState)ls.fs
	luaX_next(ls) /* skip WHILE */
	whileinit := luaK_getlabel(fs)
	condexit := cond(ls)
	bl: BlockCnt
	enterblock(fs, &bl, 1)
	checknext(ls, TK_DO)
	block(ls)
	luaK_patchlist(fs, luaK_jump(fs), whileinit)
	check_match(ls, TK_END, TK_WHILE, line)
	leaveblock(fs)
	luaK_patchtohere(fs, condexit) /* false conditions finish the loop */
}

@(private)
block :: proc(ls: ^LexState) {
	chunk(ls)
}

@(private)
new_localvarliteral :: proc(ls: ^LexState, name: string, n: int) {
	context = runtime.default_context()
	new_localvar(ls, luaX_newstring(ls, cstring(raw_data(name)), c.size_t(len(name))), n)
}

exp1 :: proc(ls: ^LexState) -> expkind {
	e: expdesc
	expr(ls, &e)
	k := e.k
	luaK_exp2nextreg(cast(^FuncState)ls.fs, &e)
	return k
}

forbody :: proc(ls: ^LexState, base, line, nvars: int, isnum: bool) {
	/* forbody -> DO block */
	bl: BlockCnt
	fs := cast(^FuncState)ls.fs
	prep, endfor: int
	adjustlocalvars(ls, 3) /* control variables */
	checknext(ls, .TK_DO)
	prep = isnum ? luaK_codeAsBx(fs, .OP_FORPREP, base, NO_JUMP) : int(luaK_jump(fs))
	enterblock(fs, &bl, 0) /* scope for declared variables */
	adjustlocalvars(ls, c.int(nvars))
	luaK_reserveregs(fs, nvars)
	block(ls)
	leaveblock(fs) /* end of scope for declared variables */
	luaK_patchtohere(fs, c.int(prep))
	if isnum {
		endfor = luaK_codeAsBx(fs, .OP_FORLOOP, base, NO_JUMP)
	} else {
		endfor = luaK_codeABC(fs, .OP_TFORLOOP, base, 0, nvars)
	}
	luaK_fixline(fs, line) /* pretend that `OP_FOR' starts the loop */
	luaK_patchlist(fs, c.int(isnum ? endfor : int(luaK_jump(fs))), c.int(prep + 1))
}

fornum :: proc(ls: ^LexState, varname: ^TString, line: c.int) {
	/* fornum -> NAME = exp1,exp1[,exp1] forbody */
	fs := cast(^FuncState)ls.fs
	base := int(fs.freereg)
	new_localvarliteral(ls, "(for index)", 0)
	new_localvarliteral(ls, "(for limit)", 1)
	new_localvarliteral(ls, "(for step)", 2)
	new_localvar(ls, varname, 3)
	checknext(ls, '=')
	exp1(ls) /* initial value */
	checknext(ls, ',')
	exp1(ls) /* limit */
	if testnext(ls, ',') {
		exp1(ls) /* optional step */
	} else { /* default step = 1 */
		luaK_codeABx(fs, .OP_LOADK, int(fs.freereg), int(luaK_numberK(fs, 1)))
		luaK_reserveregs(fs, 1)
	}
	forbody(ls, base, int(line), 1, true)
}

forlist :: proc(ls: ^LexState, indexname: ^TString) {
	/* forlist -> NAME {,NAME} IN explist1 forbody */
	fs := cast(^FuncState)ls.fs
	e: expdesc
	nvars := 0
	line: int
	base := int(fs.freereg)
	/* create control variables */
	new_localvarliteral(ls, "(for generator)", nvars); nvars += 1
	new_localvarliteral(ls, "(for state)", nvars); nvars += 1
	new_localvarliteral(ls, "(for control)", nvars); nvars += 1
	/* create declared variables */
	new_localvar(ls, indexname, nvars); nvars += 1
	for testnext(ls, ',') {
		new_localvar(ls, str_checkname(ls), nvars); nvars += 1
	}
	checknext(ls, .TK_IN)
	line = int(ls.linenumber)
	adjust_assign(ls, 3, int(explist1(ls, &e)), &e)
	luaK_checkstack(fs, 3) /* extra space to call generator */
	forbody(ls, base, line, nvars - 3, false)
}

forstat :: proc(ls: ^LexState, line: c.int) {
	/* forstat -> FOR (fornum | forlist) END */
	fs := cast(^FuncState)ls.fs
	varname: ^TString
	bl: BlockCnt
	enterblock(fs, &bl, 1) /* scope for loop and control variables */
	luaX_next(ls) /* skip `for' */
	varname = str_checkname(ls) /* first variable name */
	switch ls.t.token {
	case '=':
		fornum(ls, varname, line)
	case ',', .TK_IN:
		forlist(ls, varname)
	case:
		luaX_syntaxerror(ls, "'=' or 'in' expected")
	}
	check_match(ls, .TK_END, .TK_FOR, line)
	leaveblock(fs) /* loop scope (`break' jumps to this point) */
}

@(private)
string_constant :: proc(fs: ^FuncState, s: ^TString) -> c.int {
	return luaK_stringK(fs, s)
}

@(private)
searchvar :: proc(fs: ^FuncState, n: ^TString) -> int {
	for i := int(fs.nactvar) - 1; i >= 0; i -= 1 {
		if n == getlocvar(fs, i).varname {
			return i
		}
	}
	return -1
}

@(private)
singlevaraux :: proc(fs: ^FuncState, n: ^TString, var: ^expdesc, base: c.int) -> expkind {
	if fs == nil {
		return .VGLOBAL
	}
	v := searchvar(fs, n)
	if v >= 0 {
		init_exp(var, .VLOCAL, c.int(v))
		if base == 0 {
			markupval(fs, v)
		}
		return .VLOCAL
	}

	if singlevaraux(fs.prev, n, var, 0) == .VGLOBAL {
		return .VGLOBAL
	}
	var.u.s.info = c.int(indexupvalue(fs, n, var))
	var.k = .VUPVAL
	return .VUPVAL
}

@(private)
singlevar :: proc(ls: ^LexState, var: ^expdesc) {
	check(ls, TK_NAME)
	ts := ls.t.seminfo.ts
	luaX_next(ls)

	fs := cast(^FuncState)ls.fs
	if singlevaraux(fs, ts, var, 1) == .VGLOBAL {
		info := string_constant(fs, ts)
		init_exp(var, .VGLOBAL, info)
	}
}

@(private)
repeatstat :: proc(ls: ^LexState, line: c.int) {

	luaX_next(ls) // skip REPEAT
	chunk(ls)
	check_match(ls, TK_UNTIL, TK_REPEAT, line)
	v: expdesc
	expr(ls, &v) // condition
}


expr :: proc(ls: ^LexState, v: ^expdesc) {
	subexpr(ls, v, 0)
}

@(private)
subexpr :: proc(ls: ^LexState, v: ^expdesc, limit: u8) -> BinOpr {
	// enterlevel(ls)
	uop := getunopr(ls.t.token)
	if uop != .OPR_NOUNOPR {
		luaX_next(ls)
		subexpr(ls, v, UNARY_PRIORITY)
		// luaK_prefix(ls.fs, uop, v)
		luaK_prefix(cast(^FuncState)ls.fs, uop, v)
	} else {
		simpleexp(ls, v)
	}
	op := getbinopr(ls.t.token)
	for op != .OPR_NOBINOPR && priority[op].left > limit {
		v2: expdesc
		luaX_next(ls)
		// luaK_infix(ls.fs, op, v)
		luaK_infix(cast(^FuncState)ls.fs, op, v)
		nextop := subexpr(ls, &v2, priority[op].right)
		// luaK_posfix(ls.fs, op, v, &v2)
		luaK_posfix(cast(^FuncState)ls.fs, op, v, &v2)
		op = nextop
	}
	// leavelevel(ls)
	return op
}

@(private)
init_exp :: proc(e: ^expdesc, k: expkind, i: c.int) {
	e.f = NO_JUMP; e.t = NO_JUMP
	e.k = k
	e.u.s.info = i
}

@(private)
simpleexp :: proc(ls: ^LexState, v: ^expdesc) {
	/* simpleexp -> NUMBER | STRING | NIL | true | false | ... |
	                  constructor | FUNCTION body | primaryexp */
	fs := cast(^FuncState)ls.fs
	switch ls.t.token {
	case TK_NUMBER:
		init_exp(v, .VKNUM, 0)
		v.u.nval = ls.t.seminfo.r
	case TK_STRING:
		codestring(ls, v, ls.t.seminfo.ts)
	case TK_NIL:
		init_exp(v, .VNIL, 0)
	case TK_TRUE:
		init_exp(v, .VTRUE, 0)
	case TK_FALSE:
		init_exp(v, .VFALSE, 0)
	case TK_DOTS:
		luaY_checklimit(fs, int(fs.f.is_vararg), 0, "cannot use '...' outside a vararg function")
		init_exp(v, .VVARARG, c.int(luaK_codeABC(fs, .OP_VARARG, 0, 1, 0)))
	case '{':
		constructor(ls, v)
		return
	case TK_FUNCTION:
		luaX_next(ls)
		body(ls, v, 0, ls.linenumber)
		return
	case:
		primaryexp(ls, v)
		return
	}
	luaX_next(ls)
}

@(private)
is_binop :: proc(op: c.int) -> bool {
	switch op {
	case '+',
	     '-',
	     '*',
	     '/',
	     '%',
	     '^',
	     TK_CONCAT,
	     TK_NE,
	     TK_EQ,
	     '<',
	     TK_LE,
	     '>',
	     TK_GE,
	     TK_AND,
	     TK_OR:
		return true
	}
	return false
}

// Helper: checknext
@(private)
checknext :: proc(ls: ^LexState, c: c.int) {
	check(ls, c)
	luaX_next(ls)
}

@(private)
ConsControl :: struct {
	v:       expdesc, /* last list item read */
	t:       ^expdesc, /* table descriptor */
	nh:      int, /* total number of `record' elements */
	na:      int, /* total number of array elements */
	tostore: int, /* number of array elements pending to be stored */
}

recfield :: proc(ls: ^LexState, cc: ^ConsControl) {
	/* recfield -> (NAME | `['exp1`]') = exp1 */
	fs := cast(^FuncState)ls.fs
	reg := fs.freereg
	key, val: expdesc
	rkkey: int
	if ls.t.token == .TK_NAME {
		// luaY_checklimit(fs, cc.nh, MAX_INT, "items in a constructor");
		checkname(ls, &key)
	} else { /* ls->t.token == '[' */
		yindex(ls, &key)
	}
	cc.nh += 1
	checknext(ls, '=')
	rkkey = int(luaK_exp2RK(fs, &key))
	expr(ls, &val)
	luaK_codeABC(fs, .OP_SETTABLE, int(cc.t.u.s.info), rkkey, int(luaK_exp2RK(fs, &val)))
	fs.freereg = reg /* free registers */
}

closelistfield :: proc(fs: ^FuncState, cc: ^ConsControl) {
	if cc.v.k == .VVOID {
		return /* there is no list item */
	}
	luaK_exp2nextreg(fs, &cc.v)
	cc.v.k = .VVOID
	if cc.tostore == LFIELDS_PER_FLUSH {
		luaK_setlist(fs, cc.t.u.s.info, c.int(cc.na), c.int(cc.tostore)) /* flush */
		cc.tostore = 0 /* no more items pending */
	}
}

lastlistfield :: proc(fs: ^FuncState, cc: ^ConsControl) {
	if cc.tostore == 0 {
		return
	}
	if hasmultret(cc.v.k) {
		luaK_setmultret(fs, &cc.v)
		luaK_setlist(fs, cc.t.u.s.info, c.int(cc.na), LUA_MULTRET)
		cc.na -= 1 /* do not count last expression (unknown number of elements) */
	} else {
		if cc.v.k != .VVOID {
			luaK_exp2nextreg(fs, &cc.v)
		}
		luaK_setlist(fs, cc.t.u.s.info, c.int(cc.na), c.int(cc.tostore))
	}
}

listfield :: proc(ls: ^LexState, cc: ^ConsControl) {
	expr(ls, &cc.v)
	// luaY_checklimit(ls->fs, cc->na, MAX_INT, "items in a constructor");
	cc.na += 1
	cc.tostore += 1
}

yindex :: proc(ls: ^LexState, v: ^expdesc) {
	/* index -> `[' expr `]' */
	luaX_next(ls) /* skip `[' */
	expr(ls, v)
	luaK_exp2val(cast(^FuncState)ls.fs, v)
	checknext(ls, ']')
}

checkname :: proc(ls: ^LexState, e: ^expdesc) {
	codestring(ls, e, str_checkname(ls))
}

@(private)
constructor :: proc(ls: ^LexState, t: ^expdesc) {
	/* constructor -> ?? */
	fs := cast(^FuncState)ls.fs
	line := ls.linenumber
	pc := luaK_codeABC(fs, .OP_NEWTABLE, 0, 0, 0)
	cc: ConsControl
	cc.na = 0
	cc.nh = 0
	cc.tostore = 0
	cc.t = t
	init_exp(t, .VRELOCABLE, c.int(pc))
	init_exp(&cc.v, .VVOID, 0) /* no value (yet) */
	luaK_exp2nextreg(fs, t) /* fix it at stack top (for gc) */
	checknext(ls, '{')
	for {
		// lua_assert(cc.v.k == VVOID || cc.tostore > 0);
		if ls.t.token == '}' {
			break
		}
		closelistfield(fs, &cc)
		switch ls.t.token {
		case .TK_NAME:
			{ /* may be listfields or recfields */
				luaX_lookahead(ls)
				if ls.lookahead.token != '=' { /* expression? */
					listfield(ls, &cc)
				} else {
					recfield(ls, &cc)
				}
				break
			}
		case '[':
			{ /* constructor_item -> recfield */
				recfield(ls, &cc)
				break
			}
		case:
			{ /* constructor_part -> listfield */
				listfield(ls, &cc)
				break
			}
		}
		if !testnext(ls, ',') && !testnext(ls, ';') {
			break
		}
	}
	check_match(ls, '}', '{', line)
	lastlistfield(fs, &cc)

	instruction := &fs.f.code[pc]
	setarg_b(instruction, int(int2fb(u32(cc.na)))) /* set initial array size */
	setarg_c(instruction, int(int2fb(u32(cc.nh)))) /* set initial table size */
}

@(private)
field_stub :: proc(ls: ^LexState) {
	luaX_next(ls) // .
	str_checkname(ls)
}

@(private)
explist1 :: proc(ls: ^LexState, e: ^expdesc) -> c.int {
	n := 1 // number of expressions
	expr(ls, e)
	// cast fs
	fs := cast(^FuncState)ls.fs
	for testnext(ls, ',') {
		luaK_exp2nextreg(fs, e)
		expr(ls, e)
		n += 1
	}
	return c.int(n)
}

@(private)
funcargs :: proc(ls: ^LexState, f: ^expdesc) {
	args: expdesc
	line := ls.linenumber
	fs := cast(^FuncState)ls.fs
	switch ls.t.token {
	case '(':
		if line != ls.lastline {
			luaX_syntaxerror(ls, "ambiguous syntax (function call x new statement)")
		}
		luaX_next(ls)
		if ls.t.token == ')' { 	// arg list is empty
			args.k = .VVOID
		} else {
			explist1(ls, &args)
			luaK_setmultret(fs, &args)
		}
		check_match(ls, ')', '(', line)
	case '{':
		constructor(ls, &args)
	case TK_STRING:
		codestring(ls, &args, ls.t.seminfo.ts)
		luaX_next(ls)
	case:
		luaX_syntaxerror(ls, "function arguments expected")
		return
	}
	// assert(f.k == VNONRELOC)
	base := f.u.s.info // base register for call
	nparams: c.int
	if hasmultret(args.k) {
		nparams = LUA_MULTRET
	} else {
		if args.k != .VVOID {
			luaK_exp2nextreg(fs, &args)
		}
		nparams = fs.freereg - (base + 1)
	}
	init_exp(f, .VCALL, c.int(luaK_codeABC(fs, .OP_CALL, int(base), int(nparams + 1), 2)))
	luaK_fixline(fs, line)
	fs.freereg = base + 1 // call removes function and arguments
}


@(private)
funcstat :: proc(ls: ^LexState, line: c.int) {
	luaX_next(ls) // skip FUNCTION

	// Stub variables
	v, b: expdesc
	needself := funcname(ls, &v)
	body(ls, &b, needself, line)
	// luaK_storevar(ls.fs, &v, &b)
	// luaK_fixline(ls.fs, line)
}

@(private)
localfunc :: proc(ls: ^LexState) {
	// expdesc v, b
	// new_localvar(ls, str_checkname(ls), 0)
	// init_exp(&v, VLOCAL, ls.fs.freereg)
	// luaK_reserveregs(ls.fs, 1)
	// adjustlocalvar(ls, 1)

	// Stub: consume name
	str_checkname(ls)

	b: expdesc
	body(ls, &b, 0, ls.linenumber)
	// luaK_storevar(ls.fs, &v, &b)
}

@(private)
body :: proc(ls: ^LexState, e: ^expdesc, needself: c.int, line: c.int) {
	new_fs: FuncState
	open_func(ls, &new_fs)
	new_fs.f.linedefined = line
	parlist(ls)
	chunk(ls)
	new_fs.f.lastlinedefined = ls.linenumber
	check_match(ls, TK_END, TK_FUNCTION, line)
	close_func(ls)
	// pushclosure(ls, &new_fs, e)
}

@(private)
parlist :: proc(ls: ^LexState) {
	checknext(ls, '(')
	if ls.t.token != ')' {
		for {
			if ls.t.token == TK_NAME {
				str_checkname(ls)
				// new_localvar ...
			} else if ls.t.token == TK_DOTS {
				luaX_next(ls)
				// fs.f.is_vararg |= VARARG_ISVARARG
				break // ... cannot follow ...
			} else {
				luaX_syntaxerror(ls, "<name> or '...' expected")
			}
			if !testnext(ls, ',') {
				break
			}
		}
	}
	checknext(ls, ')')
}

@(private)
funcname :: proc(ls: ^LexState, v: ^expdesc) -> c.int {
	// funcname -> NAME {field} [: NAME]
	// singlevar(ls, v)
	str_checkname(ls) // stub: consume name

	for ls.t.token == '.' {
		field(ls, v)
	}
	if ls.t.token == ':' {
		field(ls, v)
		return 1 // needself
	}
	return 0
}

@(private)
field :: proc(ls: ^LexState, v: ^expdesc) {
	/* field -> `.' NAME */
	fs := cast(^FuncState)ls.fs
	key: expdesc
	luaK_exp2anyreg(fs, v)
	luaX_next(ls) /* skip dot or colon */
	checkname(ls, &key)
	luaK_indexed(fs, v, &key)
}

@(private)
codestring :: proc(ls: ^LexState, e: ^expdesc, s: ^TString) {
	init_exp(e, .VK, luaK_stringK(cast(^FuncState)ls.fs, s))
}

@(private)
checkname :: proc(ls: ^LexState, e: ^expdesc) {
	init_exp(e, .VK, luaK_stringK(cast(^FuncState)ls.fs, str_checkname(ls)))
}

// registerlocalvar moved to top

@(private)
new_localvar :: proc(ls: ^LexState, name: ^TString, n: int) {
	fs := cast(^FuncState)ls.fs
	luaY_checklimit(fs, int(fs.nactvar) + n + 1, LUAI_MAXVARS, "local variables")
	fs.actvar[fs.nactvar + u8(n)] = c.ushort(registerlocalvar(ls, name))
}

@(private)
adjustlocalvars :: proc(ls: ^LexState, nvars: c.int) {
	fs := cast(^FuncState)ls.fs
	fs.nactvar = u8(c.int(fs.nactvar) + nvars)
	for i := nvars; i > 0; i -= 1 {
		fs.f.locvars[fs.actvar[fs.nactvar - u8(i)]].startpc = fs.pc
	}
}


@(private)
localstat :: proc(ls: ^LexState) {
	// local var ...
	nexps := 0
	nvars := 0
	vars: [LUAI_MAXVARS]expdesc
	_ = vars // Suppress unused warning if vars not used yet

	for {
		// consume name
		check(ls, TK_NAME)
		ts := ls.t.seminfo.ts
		luaX_next(ls)

		new_localvar(ls, ts, nvars)
		nvars += 1

		if !testnext(ls, ',') {break}
	}

	if testnext(ls, '=') {
		nexps = int(explist1(ls, &vars[0]))
	} else {
		// e.k = VVOID;
		// e.u.info = 0;
	}
	// adjust_assign(ls, nvars, nexps, &e) substitute
	// For now, simpler adjustment:
	fs := cast(^FuncState)ls.fs
	adjustlocalvars(ls, c.int(nvars))
	// TODO: Proper assignment adjustment and code emission
}


@(private)
labelstat :: proc(ls: ^LexState, name: ^TString, line: c.int) {
	check_match(ls, TK_DBCOLON, TK_DBCOLON, line)
}

@(private)
retstat :: proc(ls: ^LexState) {
	luaX_next(ls)
	// return exprlist
	// Consume until EOS or block delimiter
	for !block_follow(ls.t.token) && ls.t.token != ';' {
		luaX_next(ls)
	}
	testnext(ls, ';')
}

@(private)
breakstat :: proc(ls: ^LexState) {
	luaX_next(ls)
}

@(private)
exprstat :: proc(ls: ^LexState) {
	// primaryexp ...
	// assignment or function call
	fs := cast(^FuncState)ls.fs
	v: LHS_assign
	primaryexp(ls, &v.v)
	if v.v.k == .VCALL { /* stat -> func */
		setarg_c(getcode_ref(fs, &v.v), 1) /* call statement uses no results */
	} else { /* stat -> assignment */
		v.prev = nil
		assignment(ls, &v, 1)
	}
}

@(private)
primaryexp :: proc(ls: ^LexState, v: ^expdesc) {
	/* primaryexp ->
	        prefixexp { `.' NAME | `[' exp `]' | `:' NAME funcargs | funcargs } */
	prefixexp(ls, v)
	for {
		switch ls.t.token {
		case '.':
			field(ls, v)
		case '[':
			expdesc_index(ls, v)
		case ':':
			v2: expdesc
			luaX_next(ls)
			str_checkname(ls)
			luaK_self(cast(^FuncState)ls.fs, v, &v2)
			funcargs(ls, v)
		case '(', '{', TK_STRING:
			luaK_exp2nextreg(cast(^FuncState)ls.fs, v)
			funcargs(ls, v)
		case:
			return
		}
	}
}

@(private)
prefixexp :: proc(ls: ^LexState, v: ^expdesc) {
	/* prefixexp -> NAME | `(' expr `)' */
	switch ls.t.token {
	case '(':
		line := ls.linenumber
		luaX_next(ls)
		expr(ls, v)
		check_match(ls, ')', '(', line)
		luaK_dischargevars(cast(^FuncState)ls.fs, v)
	case TK_NAME:
		singlevar(ls, v)
	case:
		luaX_syntaxerror(ls, "unexpected symbol")
	}
}

@(private)
assignment :: proc(ls: ^LexState, lh: ^LHS_assign, nvars: int) {
	e: expdesc
	check_condition :: #force_inline proc(ls: ^LexState, cond: bool, msg: cstring) {
		if !cond do luaX_syntaxerror(ls, msg)
	}
	check_condition(ls, .VLOCAL <= lh.v.k && lh.v.k <= .VINDEXED, "syntax error")
	check_readonly(ls, &lh.v)
	if testnext(ls, ',') { /* assignment -> `,' primaryexp assignment */
		nv: LHS_assign
		nv.prev = lh
		primaryexp(ls, &nv.v)
		if nv.v.k == .VLOCAL {
			check_conflict(ls, lh, &nv.v)
		}
		// checklimit omitted for now
		assignment(ls, &nv, nvars + 1)
	} else { /* assignment -> `=' explist1 */
		checknext(ls, '=')
		nexps := int(explist1(ls, &e))
		if nexps != nvars {
			adjust_assign(ls, nvars, nexps, &e)
			if nexps > nvars {
				(cast(^FuncState)ls.fs).freereg -= c.int(nexps - nvars)
			}
		} else {
			luaK_setoneret(cast(^FuncState)ls.fs, &e)
			luaK_storevar(cast(^FuncState)ls.fs, &lh.v, &e)
			assignment_recursive(ls, lh.prev, nvars - 1)
			return
		}
	}
	init_exp(&e, .VNONRELOC, c.int((cast(^FuncState)ls.fs).freereg - 1))
	luaK_storevar(cast(^FuncState)ls.fs, &lh.v, &e)
}

@(private)
assignment_recursive :: proc(ls: ^LexState, lh: ^LHS_assign, nvars: int) {
	if lh == nil do return
	e: expdesc
	init_exp(&e, .VNONRELOC, c.int((cast(^FuncState)ls.fs).freereg - 1 - c.int(nvars)))
	luaK_storevar(cast(^FuncState)ls.fs, &lh.v, &e)
	assignment_recursive(ls, lh.prev, nvars - 1)
}

@(private)
expdesc_index :: proc(ls: ^LexState, v: ^expdesc) {
	/* index -> `[' exp `]' */
	luaK_exp2anyreg(cast(^FuncState)ls.fs, v)
	luaX_next(ls)
	v2: expdesc
	expr(ls, &v2)
	luaK_indexed(cast(^FuncState)ls.fs, v, &v2)
	checknext(ls, ']')
}

// ... original registerlocalvar remove ...

@(private)
str_checkname :: proc(ls: ^LexState) -> ^TString {
	check(ls, TK_NAME)
	ts := ls.t.seminfo.ts
	luaX_next(ls)
	return ts
}

// hasmultret already defined

@(private)
adjust_assign :: proc(ls: ^LexState, nvars, nexps: int, e: ^expdesc) {
	fs := cast(^FuncState)ls.fs
	extra := nvars - nexps
	if hasmultret(e.k) {
		extra += 1 // includes call itself
		if extra < 0 do extra = 0
		luaK_setreturns(fs, e, c.int(extra)) // last exp. provides the difference
		if extra > 1 {
			luaK_reserveregs(fs, c.int(extra - 1))
		}
	} else {
		if e.k != .VVOID {
			luaK_exp2nextreg(fs, e) // close last expression
		}
		if extra > 0 {
			reg := fs.freereg
			luaK_reserveregs(fs, c.int(extra))
			luaK_nil(fs, reg, c.int(extra))
		}
	}
}


@(private)
removevars :: proc(ls: ^LexState, tolevel: int) {
	// Stub
}

// --- Main Parser Function ---

@(export, link_name = "luamY_parser")
luamY_parser :: proc "c" (L: ^lua_State, z: ^ZIO, buff: ^Mbuffer, name: cstring) -> ^Proto {
	context = runtime.default_context()

	lexstate: LexState
	funcstate: FuncState

	lexstate.buff = buff
	luaX_setinput(L, &lexstate, z, luaS_new(L, name))
	open_func(&lexstate, &funcstate)
	funcstate.f.is_vararg = VARARG_ISVARARG // main func. is always vararg

	luaX_next(&lexstate) // read first token
	chunk(&lexstate)
	check(&lexstate, TK_EOS)
	close_func(&lexstate)

	// lua_assert(funcstate.prev == NULL);
	// lua_assert(funcstate.f->nups == 0);
	// lua_assert(lexstate.fs == NULL);

	return funcstate.f
}

// Helper: check
@(private)
check :: proc(ls: ^LexState, c: c.int) {
	if ls.t.token != c {
		error_expected(ls, c)
	}
}

@(private)
error_expected :: proc(ls: ^LexState, token: c.int) {
	luaX_syntaxerror(ls, luaO_pushfstring(ls.L, "%s expected", luaX_token2str(ls, token)))
}
