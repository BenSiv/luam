package core

import "core:c"
import "core:fmt"
import "core:math"


// --- Constants ---
NO_JUMP :: -1

// --- Functions ---

luaK_codeABC :: proc(fs: ^FuncState, o: OpCode, A, B, C: int) -> int {
	// lua_assert(getOpMode(o) == iABC);
	// lua_assert(getBMode(o) != OpArgN || B == 0);
	// lua_assert(getCMode(o) != OpArgN || C == 0);
	// lua_assert(A <= MAXARG_A && B <= MAXARG_B && C <= MAXARG_C);
	return luaK_code(fs, create_abc(o, A, B, C))
}

luaK_codeABx :: proc(fs: ^FuncState, o: OpCode, A: int, Bx: int) -> int {
	// lua_assert(getOpMode(o) == iABx || getOpMode(o) == iAsBx);
	// lua_assert(getCMode(o) == OpArgN);
	// lua_assert(A <= MAXARG_A && Bx <= MAXARG_Bx);
	return luaK_code(fs, create_abx(o, A, Bx))
}

luaK_codeAsBx :: proc(fs: ^FuncState, o: OpCode, A: int, sBx: int) -> int {
	return luaK_codeABx(fs, o, A, sBx + MAXARG_sBx)
}

@(private)
luaK_code :: proc(fs: ^FuncState, i: Instruction) -> int {
	luaK_dischargejpc(fs) // `dischargejpc` might need to be implemented or stubbed

	// grow vector logic
	if fs.pc >= c.int(fs.f.sizecode) {
		fs.f.code = cast(^Instruction)grow_vector(
			fs.L,
			rawptr(fs.f.code),
			fs.pc,
			&fs.f.sizecode,
			size_of(Instruction),
			max(c.int),
			"code size overflow",
		)
	}

	fs.f.code[fs.pc] = i

	// line info
	if fs.pc >= c.int(fs.f.sizelineinfo) {
		fs.f.lineinfo = cast(^c.int)grow_vector(
			fs.L,
			rawptr(fs.f.lineinfo),
			fs.pc,
			&fs.f.sizelineinfo,
			size_of(c.int),
			max(c.int),
			"code size overflow",
		)
	}
	fs.f.lineinfo[fs.pc] = fs.ls.lastline

	fs.pc += 1
	return int(fs.pc - 1)
}

@(private)
luaK_dischargejpc :: proc(fs: ^FuncState) {
	if fs.jpc == NO_JUMP {return} 	// Optimization
	patchlistaux(fs, int(fs.jpc), int(fs.pc), NO_REG, int(fs.pc))
	fs.jpc = NO_JUMP
}

@(private)
patchlistaux :: proc(fs: ^FuncState, list: int, vtarget: int, reg: int, dtarget: int) {
	list := list
	for list != NO_JUMP {
		next := getjump(fs, list)
		if patchtestreg(fs, list, reg) != 0 {
			fixjump(fs, list, vtarget)
		} else {
			fixjump(fs, list, dtarget)
		}
		list = next
	}
}

// Helpers for patchlist
@(private)
patchtestreg :: proc(fs: ^FuncState, node: int, reg: int) -> int {
	i: ^Instruction = getjumpcontrol(fs, node)
	if get_opcode(i^) != .OP_TESTSET {
		return 0
	}
	if reg != NO_REG && reg != int(getarg_b(i^)) {
		setarg_a(i, reg)
	} else {
		// no register or register mismatch, change to OP_TEST
		// code := create_abc(.OP_TEST, getarg_b(i^), 0, getarg_c(i^)) // This line was problematic in original
		// set_opcode(i, .OP_TEST) // This line was problematic in original
		// setarg_a(i, getarg_b(i^)) // This line was problematic in original
		// setarg_b(i, 0) // Placeholder // This line was problematic in original
		// setarg_c(i, getarg_c(i^)) // Placeholder, actually instruction structure update needed? // This line was problematic in original
		// Lua 5.1 OP_TEST: A C (if not (R(A) <=> C) then pc++)
		// Lua 5.1 OP_TESTSET: A B C (if (R(B) <=> C) then R(A) := R(B) else pc++)

		// Correct conversion from TESTSET defined in lopcodes.c
		// i->op = OP_TEST; SETARG_A(*i, GETARG_B(*i));

		instr := i^
		instr = (instr & mask0(SIZE_OP, POS_OP)) | (Instruction(OpCode.OP_TEST) << POS_OP)

		// setarg_a(i, getarg_b(i^)) // tricky due to dereferencing
		b := getarg_b(i^)
		instr = (instr & mask0(SIZE_A, POS_A)) | (Instruction(b) << POS_A)

		i^ = instr
	}
	return 1
}

@(private)
getjumpcontrol :: proc(fs: ^FuncState, pc: int) -> ^Instruction {
	pi := &fs.f.code[pc]
	if pc >= 1 && test_tmode(get_opcode(fs.f.code[pc - 1])) {
		return &fs.f.code[pc - 1]
	}
	return pi
}

@(private)
getjump :: proc(fs: ^FuncState, pc: int) -> int {
	offset := getarg_sbx(fs.f.code[pc])
	if offset == NO_JUMP {return NO_JUMP}
	return (pc + 1) + offset
}

@(private)
fixjump :: proc(fs: ^FuncState, pc: int, dest: int) {
	jmp := &fs.f.code[pc]
	offset := dest - (pc + 1)
	if abs(offset) > MAXARG_sBx {
		luaX_syntaxerror(fs.ls, "control structure too long")
	}
	setarg_sbx(jmp, offset)
}


// --- Stubs for other luaK functions ---

luaK_fixline :: proc(fs: ^FuncState, line: c.int) {
	fs.f.lineinfo[fs.pc - 1] = line
}

luaK_nil :: proc(fs: ^FuncState, from, n: c.int) {
	if fs.pc > fs.lasttarget {
		if fs.pc == 0 {
			if from >= c.int(fs.nactvar) {return}
		} else {
			previous := &fs.f.code[fs.pc - 1]
			if get_opcode(previous^) == .OP_LOADNIL {
				pfrom := c.int(getarg_a(previous^))
				pto := c.int(getarg_b(previous^))
				if pfrom <= from && from <= pto + 1 {
					if from + n - 1 > pto {
						setarg_b(previous, int(from + n - 1))
					}
					return
				}
			}
		}
	}
	luaK_codeABC(fs, .OP_LOADNIL, int(from), int(from + n - 1), 0)
}

luaK_reserveregs :: proc(fs: ^FuncState, n: c.int) {
	luaY_checklimit(fs, int(fs.freereg + n), max(int), "registers")
	fs.freereg += n
}

luaK_checkstack :: proc(fs: ^FuncState, n: c.int) {
	newstack := int(fs.freereg + n)
	if newstack > int(fs.f.maxstacksize) {
		if newstack >= MAXSTACK {
			luaX_syntaxerror(fs.ls, "function or expression too complex")
		}
		fs.f.maxstacksize = u8(newstack)
	}
}

// Helper for adding constants
@(private)
addk :: proc(fs: ^FuncState, k: ^TValue, v: ^TValue) -> c.int {
	// Simple linear scan for deduplication
	for i := 0; i < int(fs.nk); i += 1 {
		old := &fs.f.k[i]
		if old.tt == k.tt {
			if old.tt == LUA_TNUMBER {
				if old.value.n == k.value.n {return c.int(i)}
			} else if old.tt == LUA_TSTRING {
				if old.value.gc == k.value.gc {return c.int(i)}
			} else if old.tt == LUA_TNIL {
				return c.int(i) // only one nil
			} else if old.tt == LUA_TBOOLEAN {
				if old.value.b == k.value.b {return c.int(i)}
			}
		}
	}

	// Grow vector
	if fs.nk + 1 > fs.f.sizek {
		fs.f.k = cast([^]TValue)grow_vector(
			fs.L,
			rawptr(fs.f.k),
			fs.nk,
			&fs.f.sizek,
			size_of(TValue),
			MAXARG_Bx,
			"constant table overflow",
		)
	}
	fs.f.k[fs.nk] = k^
	fs.nk += 1
	return fs.nk - 1


}

luaK_stringK :: proc(fs: ^FuncState, s: ^TString) -> c.int {
	o: TValue
	o.tt = LUA_TSTRING
	o.value.gc = cast(^GCObject)s
	return addk(fs, &o, &o)
}

luaK_numberK :: proc(fs: ^FuncState, r: lua_Number) -> c.int {
	o: TValue
	o.tt = LUA_TNUMBER
	o.value.n = r
	return addk(fs, &o, &o)
}

@(private)
luaK_boolK :: proc(fs: ^FuncState, b: bool) -> c.int {
	o: TValue
	o.tt = LUA_TBOOLEAN
	o.value.b = (b) ? 1 : 0
	return addk(fs, &o, &o)
}

@(private)
luaK_nilK :: proc(fs: ^FuncState) -> c.int {
	o: TValue
	o.tt = LUA_TNIL
	return addk(fs, &o, &o)
}

// --- Expression Evaluation ---

luaK_dischargevars :: proc(fs: ^FuncState, e: ^expdesc) {
	#partial switch e.k {
	case .VLOCAL:
		e.k = .VNONRELOC
	case .VUPVAL:
		e.u.s.info = c.int(luaK_codeABC(fs, .OP_GETUPVAL, 0, int(e.u.s.info), 0))
		e.k = .VRELOCABLE
	case .VGLOBAL:
		e.u.s.info = c.int(luaK_codeABx(fs, .OP_GETGLOBAL, 0, int(e.u.s.info)))
		e.k = .VRELOCABLE
	case .VINDEXED:
		freereg(fs, e.u.s.aux)
		freereg(fs, e.u.s.info)
		e.u.s.info = c.int(luaK_codeABC(fs, .OP_GETTABLE, 0, int(e.u.s.info), int(e.u.s.aux)))
		e.k = .VRELOCABLE
	case .VVARARG, .VCALL:
		luaK_setoneret(fs, e)
	}
}

luaK_setmultret :: proc(fs: ^FuncState, e: ^expdesc) {
	luaK_setoneret(fs, e)
	if e.k == .VCALL || e.k == .VVARARG {
		setarg_b(getcode_ref(fs, e), LUA_MULTRET)
		e.k = .VVOID
	}
}

luaK_setoneret :: proc(fs: ^FuncState, e: ^expdesc) {
	if e.k == .VCALL { 	// expression is an open function call?
		e.k = .VNONRELOC
		e.u.s.info = c.int(getarg_a(getcode(fs, e)))
	} else if e.k == .VVARARG {
		instruction := getcode_ref(fs, e)
		setarg_b(instruction, 2)
		e.k = .VRELOCABLE // can be relocated
	}
}

// Helper for getcode macro
@(private)
getcode :: #force_inline proc(fs: ^FuncState, e: ^expdesc) -> Instruction {
	return fs.f.code[e.u.s.info]
}

@(private)
getcode_ref :: #force_inline proc(fs: ^FuncState, e: ^expdesc) -> ^Instruction {
	return &fs.f.code[e.u.s.info]
}

luaK_exp2anyreg :: proc(fs: ^FuncState, e: ^expdesc) -> c.int {
	luaK_dischargevars(fs, e)
	if e.k == .VNONRELOC {
		if !hasjumps(e) {
			return e.u.s.info
		}
		if e.u.s.info >= c.int(fs.nactvar) { 	// exp is already in a register
			exp2reg(fs, e, int(e.u.s.info))
			return e.u.s.info
		}
	}
	luaK_exp2nextreg(fs, e)
	return e.u.s.info
}

luaK_exp2nextreg :: proc(fs: ^FuncState, e: ^expdesc) {
	luaK_dischargevars(fs, e)
	freeexp(fs, e)
	luaK_reserveregs(fs, 1)
	exp2reg(fs, e, int(fs.freereg - 1))
}

luaK_exp2val :: proc(fs: ^FuncState, e: ^expdesc) {
	if hasjumps(e) {
		luaK_exp2anyreg(fs, e)
	} else {
		luaK_dischargevars(fs, e)
	}
}

luaK_exp2RK :: proc(fs: ^FuncState, e: ^expdesc) -> c.int {
	luaK_exp2val(fs, e)
	#partial switch e.k {
	case .VKNUM, .VTRUE, .VFALSE, .VNIL:
		if fs.nk <= MAXINDEXRK {
			e.u.s.info =
				(e.k == .VNIL) ? luaK_nilK(fs) : (e.k == .VKNUM) ? luaK_numberK(fs, e.u.nval) : luaK_boolK(fs, e.k == .VTRUE)
			e.k = .VK
			return c.int(rkask(int(e.u.s.info)))
		}
	case .VK:
		if e.u.s.info <= MAXINDEXRK {
			return c.int(rkask(int(e.u.s.info)))
		}
	}
	return luaK_exp2anyreg(fs, e)
}

// Helpers for exp2reg
@(private)
exp2reg :: proc(fs: ^FuncState, e: ^expdesc, reg: int) {
	discharge2reg(fs, e, reg)
	if e.k == .VJMP {
		luaK_concat(fs, &e.t, e.u.s.info)
	}
	if hasjumps(e) {
		final_pos := NO_JUMP
		p_f := NO_JUMP // place of false jump
		p_t := NO_JUMP // place of true jump

		if need_value(fs, e.t) || need_value(fs, e.f) {
			p_j := (e.k == .VJMP) ? NO_JUMP : int(luaK_jump(fs))
			p_f = code_label(fs, reg, 0, 1)
			p_t = code_label(fs, reg, 1, 0)
			luaK_patchtohere(fs, c.int(p_j))
		}
		final_pos = int(luaK_getlabel(fs))
		luaK_patchlist(fs, e.f, c.int(final_pos))
		luaK_patchlist(fs, e.t, c.int(final_pos))
	}
	e.f = NO_JUMP
	e.t = NO_JUMP
	e.u.s.info = c.int(reg)
	e.k = .VNONRELOC
}

@(private)
discharge2reg :: proc(fs: ^FuncState, e: ^expdesc, reg: int) {
	luaK_dischargevars(fs, e)
	#partial switch e.k {
	case .VNIL:
		luaK_nil(fs, c.int(reg), 1)
	case .VFALSE, .VTRUE:
		luaK_codeABC(fs, .OP_LOADBOOL, reg, (e.k == .VTRUE) ? 1 : 0, 0)
	case .VK:
		luaK_codeABx(fs, .OP_LOADK, reg, int(e.u.s.info))
	case .VKNUM:
		luaK_codeABx(fs, .OP_LOADK, reg, int(luaK_numberK(fs, e.u.nval)))
	case .VRELOCABLE:
		instruction := &fs.f.code[e.u.s.info]
		setarg_a(instruction, reg)
	case .VNONRELOC:
		if reg != int(e.u.s.info) {
			luaK_codeABC(fs, .OP_MOVE, reg, int(e.u.s.info), 0)
		}
	case:
		// void, jump, etc.
		return
	}
	e.u.s.info = c.int(reg)
	e.k = .VNONRELOC
}

// Helpers
@(private)
hasjumps :: #force_inline proc(e: ^expdesc) -> bool {
	return e.t != e.f
}

@(private)
need_value :: proc(fs: ^FuncState, list: c.int) -> bool {
	return list != NO_JUMP
}

@(private)
code_label :: proc(fs: ^FuncState, A, b, jump: int) -> int {
	luaK_getlabel(fs) /* those instructions may be jump targets */
	return luaK_codeABC(fs, .OP_LOADBOOL, A, b, jump)
}


@(private)
freeexp :: proc(fs: ^FuncState, e: ^expdesc) {
	if e.k == .VNONRELOC {
		freereg(fs, e.u.s.info)
	}
}

@(private)
freereg :: proc(fs: ^FuncState, reg: c.int) {
	if !isk(int(reg)) && reg >= c.int(fs.nactvar) {
		fs.freereg -= 1
		// assert(reg == fs.freereg)
	}
}

luaK_jump :: proc(fs: ^FuncState, o: OpCode = .OP_JMP) -> c.int {
	jpc := fs.jpc
	fs.jpc = NO_JUMP
	j := luaK_codeAsBx(fs, o, 0, NO_JUMP)
	jc := c.int(j)
	luaK_concat(fs, &jc, c.int(jpc))
	return jc
}

luaK_ret :: proc(fs: ^FuncState, first, nret: c.int) {
	luaK_codeABC(fs, .OP_RETURN, int(first), int(nret + 1), 0)
}

luaK_patchlist :: proc(fs: ^FuncState, list, target: c.int) {
	if target == c.int(fs.pc) {
		luaK_patchtohere(fs, list)
	} else {
		// assert(target < c.int(fs.pc))
		patchlistaux(fs, int(list), int(target), NO_REG, int(target))
	}
}

luaK_patchtohere :: proc(fs: ^FuncState, list: c.int) {
	luaK_getlabel(fs)
	jpc_ptr := &fs.jpc
	luaK_concat(fs, jpc_ptr, list)
}

luaK_concat :: proc(fs: ^FuncState, l1: ^c.int, l2: c.int) {
	if l2 == NO_JUMP {return}
	if l1^ == NO_JUMP {
		l1^ = l2
	} else {
		list := int(l1^)
		next := 0
		for {
			next = getjump(fs, list)
			if next == NO_JUMP {break}
			list = next
		}
		fixjump(fs, list, int(l2))
	}
}

luaK_getlabel :: proc(fs: ^FuncState) -> c.int {
	fs.lasttarget = fs.pc
	return fs.pc
}

// --- Expression Code Gen ---

@(private)
constfolding :: proc(op: OpCode, e1, e2: ^expdesc) -> bool {
	if !isnumeral(e1) || !isnumeral(e2) {return false}
	v1 := e1.u.nval
	v2 := e2.u.nval
	r: lua_Number
	#partial switch op {
	case .OP_ADD:
		r = v1 + v2
	case .OP_SUB:
		r = v1 - v2
	case .OP_MUL:
		r = v1 * v2
	case .OP_DIV:
		if v2 == 0 {return false}
		r = v1 / v2
	case .OP_MOD:
		if v2 == 0 {return false}
		r = v1 - math.floor(v1 / v2) * v2
	case .OP_POW:
		r = math.pow(v1, v2)
	case .OP_UNM:
		r = -v1
	case .OP_LEN:
		return false
	case:
		return false
	}
	// Check NaN?
	e1.u.nval = r
	return true
}

@(private)
codearith :: proc(fs: ^FuncState, op: OpCode, e1, e2: ^expdesc) {
	if constfolding(op, e1, e2) {
		return
	}
	o2 := (op != .OP_UNM && op != .OP_LEN) ? luaK_exp2RK(fs, e2) : 0
	o1 := luaK_exp2RK(fs, e1)
	if o1 > o2 {
		freeexp(fs, e1)
		freeexp(fs, e2)
	} else {
		freeexp(fs, e2)
		freeexp(fs, e1)
	}
	e1.u.s.info = c.int(luaK_codeABC(fs, op, 0, int(o1), int(o2)))
	e1.k = .VRELOCABLE
}

@(private)
codecomp :: proc(fs: ^FuncState, op: OpCode, cond: int, e1, e2: ^expdesc) {
	o1 := luaK_exp2RK(fs, e1)
	o2 := luaK_exp2RK(fs, e2)
	freeexp(fs, e2)
	freeexp(fs, e1)
	cond := cond
	if cond == 0 && op != .OP_EQ {
		o1, o2 = o2, o1
		cond = 1
	}
	e1.u.s.info = c.int(condjump(fs, op, cond, int(o1), int(o2)))
	e1.k = .VJMP
}

@(private)
condjump :: proc(fs: ^FuncState, op: OpCode, A, B, C: int) -> int {
	luaK_codeABC(fs, op, A, B, C)
	return int(luaK_jump(fs, .OP_JMP))
}

luaK_prefix :: proc(fs: ^FuncState, op: UnOpr, e: ^expdesc) {
	e2: expdesc
	e2.t = NO_JUMP; e2.f = NO_JUMP
	e2.k = .VKNUM; e2.u.nval = 0
	switch op {
	case .OPR_MINUS:
		if !isnumeral(e) {
			luaK_exp2anyreg(fs, e)
		}
		codearith(fs, .OP_UNM, e, &e2)
	case .OPR_NOT:
		codenot(fs, e)
	case .OPR_LEN:
		luaK_exp2anyreg(fs, e)
		codearith(fs, .OP_LEN, e, &e2)
	case .OPR_NOUNOPR:
	// assert(0)
	}
}

luaK_infix :: proc(fs: ^FuncState, op: BinOpr, v: ^expdesc) {
	#partial switch op {
	case .OPR_AND:
		luaK_goiftrue(fs, v, 0)
	case .OPR_OR:
		luaK_goiffalse(fs, v, 0)
	case .OPR_CONCAT:
		luaK_exp2nextreg(fs, v)
	case .OPR_ADD, .OPR_SUB, .OPR_MUL, .OPR_DIV, .OPR_MOD, .OPR_POW:
		if !isnumeral(v) {luaK_exp2RK(fs, v)}
	case:
		luaK_exp2RK(fs, v)
	}
}

luaK_posfix :: proc(fs: ^FuncState, op: BinOpr, e1, e2: ^expdesc) {
	switch op {
	case .OPR_AND:
		// assert(e1.t == NO_JUMP)
		luaK_dischargevars(fs, e2)
		luaK_concat(fs, &e2.f, e1.f)
		e1^ = e2^
	case .OPR_OR:
		// assert(e1.f == NO_JUMP)
		luaK_dischargevars(fs, e2)
		luaK_concat(fs, &e2.t, e1.t)
		e1^ = e2^
	case .OPR_CONCAT:
		luaK_exp2val(fs, e2)
		if e2.k == .VRELOCABLE && get_opcode(getcode(fs, e2)) == .OP_CONCAT {
			// assert(e1.u.s.info == getarg_b(...) - 1)
			freeexp(fs, e1)
			setarg_b(getcode_ref(fs, e2), int(e1.u.s.info))
			e1.k = .VRELOCABLE
			e1.u.s.info = e2.u.s.info
		} else {
			luaK_exp2nextreg(fs, e2)
			codearith(fs, .OP_CONCAT, e1, e2)
		}
	case .OPR_ADD:
		codearith(fs, .OP_ADD, e1, e2)
	case .OPR_SUB:
		codearith(fs, .OP_SUB, e1, e2)
	case .OPR_MUL:
		codearith(fs, .OP_MUL, e1, e2)
	case .OPR_DIV:
		codearith(fs, .OP_DIV, e1, e2)
	case .OPR_MOD:
		codearith(fs, .OP_MOD, e1, e2)
	case .OPR_POW:
		codearith(fs, .OP_POW, e1, e2)
	case .OPR_EQ:
		codecomp(fs, .OP_EQ, 1, e1, e2)
	case .OPR_NE:
		codecomp(fs, .OP_EQ, 0, e1, e2)
	case .OPR_LT:
		codecomp(fs, .OP_LT, 1, e1, e2)
	case .OPR_LE:
		codecomp(fs, .OP_LE, 1, e1, e2)
	case .OPR_GT:
		codecomp(fs, .OP_LT, 0, e1, e2)
	case .OPR_GE:
		codecomp(fs, .OP_LE, 0, e1, e2)
	case .OPR_NOBINOPR:
	}
}

// Helpers
@(private)
codenot :: proc(fs: ^FuncState, e: ^expdesc) {
	luaK_dischargevars(fs, e)
	#partial switch e.k {
	case .VNIL, .VFALSE:
		e.k = .VTRUE
	case .VK, .VKNUM, .VTRUE:
		e.k = .VFALSE
	case .VJMP:
		invertjump(fs, e)
	case .VRELOCABLE, .VNONRELOC:
		discharge2anyreg(fs, e)
		freeexp(fs, e)
		e.u.s.info = c.int(luaK_codeABC(fs, .OP_NOT, 0, int(e.u.s.info), 0))
		e.k = .VRELOCABLE
	case:
	// assert(0)
	}
	// interchange true and false lists
	e.f, e.t = e.t, e.f
	removevalues(fs, e.f)
	removevalues(fs, e.t)
}

@(private)
isnumeral :: proc(e: ^expdesc) -> bool {
	return e.k == .VKNUM && e.t == NO_JUMP && e.f == NO_JUMP
}

@(private)
invertjump :: proc(fs: ^FuncState, e: ^expdesc) {
	instruction := getcode_ref(fs, e)
	setarg_a(instruction, (getarg_a(instruction^) == 0) ? 1 : 0)
}

@(private)
discharge2anyreg :: proc(fs: ^FuncState, e: ^expdesc) {
	if e.k != .VNONRELOC {
		luaK_reserveregs(fs, 1)
		discharge2reg(fs, e, int(fs.freereg - 1))
	}
}

@(private)
removevalues :: proc(fs: ^FuncState, list: c.int) {
	list := list
	for list != NO_JUMP {
		patchtestreg(fs, int(list), NO_REG)
		list = c.int(getjump(fs, int(list)))
	}
}

luaK_goiftrue :: proc(fs: ^FuncState, e: ^expdesc, strict: c.int) {
	// Stub or partial impl needed for infix
}

luaK_goiffalse :: proc(fs: ^FuncState, e: ^expdesc, strict: c.int) {
	// Stub
}

luaK_setlist :: proc(fs: ^FuncState, base, nelems, tostore: c.int) {
	c_val := (nelems - 1) / LFIELDS_PER_FLUSH + 1
	b := (tostore == LUA_MULTRET) ? 0 : tostore
	// assert(tostore != 0)
	if c_val <= MAXARG_C {
		luaK_codeABC(fs, .OP_SETLIST, int(base), int(b), int(c_val))
	} else {
		luaK_codeABC(fs, .OP_SETLIST, int(base), int(b), 0)
		luaK_code(fs, Instruction(c_val))
	}
	fs.freereg = base + 1 // free registers with list values
}
