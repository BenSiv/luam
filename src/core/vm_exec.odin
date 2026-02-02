// Lua Virtual Machine - Execution Loop
// Migrated from lvm.c/h
package core

import "base:runtime"
import libc "core:c"
import "core:fmt"
import "core:mem"

// Optimization for loops using gettable
// This procedure is likely intended to be defined elsewhere or its body is missing/incorrectly placed.
// For now, I will place it as a separate procedure as requested, but note the body seems to be a copy of luaV_execute's start.
// If this is meant to be an *internal* helper for luaV_execute, its definition might need to be nested or its body corrected.
luaV_gettable_helper :: proc(L: ^lua_State, t: ^TValue, key: ^TValue, val: StkId) {
	// The body provided here appears to be the start of luaV_execute.
	// This might be a placeholder or an error in the instruction.
	// Assuming it's a placeholder for a new helper function.
	// The original luaV_gettable is called from C, so this might be a new Go-native implementation.
	// Renamed to luaV_gettable_helper to avoid conflict with the C function called via FFI.
	_ = L
	_ = t
	_ = key
	_ = val
	// Original instruction had:
	// t := t // This shadows the parameter 't' and is likely an error.
	// for loop in 0 ..< MAXTAGLOOP {runtime.default_context() // This loop structure is incomplete and incorrect here.
	// ci := L.ci
	// cl := &clvalue(ci.func).l
	// p := cl.p
	// k := p.k
	// base := L.base
	// ... (rest of luaV_execute body)
}

// Execute bytecode
// Main execution loop
@(export)
luaV_execute :: proc "c" (L: ^lua_State, nexeccalls: libc.int) {
	ncalls := nexeccalls
	context = runtime.default_context()
	ci := L.ci
	cl := &clvalue(ci.func).l
	p := cl.p
	k := p.k
	base := L.base
	// pc is a pointer to instructions. Since instructions are stored in an array/slice,
	// we use a pointer to navigate.
	// L.savedpc points to the *next* instruction to execute.
	pc := L.savedpc

	// Helper for Protect macro pattern: save pc, do op, restore base
	// We cannot make this a procedure easily because it modifies local 'base'

	// Main loop

	loop: for {
		if nilobject.tt != LUA_TNIL {
			fmt.eprintln("FATAL: nilobject corruption detected in VM loop! tt =", nilobject.tt)
			// Break here to get a stack trace in GDB
			_ = (cast(^int)nil)^
		}
		// Fetch instruction
		i := pc[0]
		pc = cast([^]Instruction)(cast(uintptr)pc + size_of(Instruction))

		// Debug hooks (line/count)
		if (L.hookmask & (LUA_MASKLINE | LUA_MASKCOUNT)) != 0 {
			L.hookcount -= 1
			if L.hookcount == 0 || (L.hookmask & LUA_MASKLINE) != 0 {
				traceexec(L, pc)
				if L.status == LUA_YIELD {
					L.savedpc = cast([^]Instruction)(cast(uintptr)pc - size_of(Instruction))
					return
				}
				base = L.base
			}
		}

		// RA = base + getarg_a(i)
		ra := cast(StkId)(cast(uintptr)base + uintptr(getarg_a(i)) * size_of(TValue))

		op := get_opcode(i)

		switch op {
		case .OP_MOVE:
			rb := cast(StkId)(cast(uintptr)base + uintptr(getarg_b(i)) * size_of(TValue))
			setobjs2s(L, ra, rb)

		case .OP_LOADK:
			bx := getarg_bx(i)
			rb := &k[bx]
			setobj2s(L, ra, rb)

		case .OP_LOADBOOL:
			b := getarg_b(i)
			c := getarg_c(i)
			setbvalue(ra, libc.int(b))
			if c != 0 {
				pc = cast([^]Instruction)(cast(uintptr)pc + size_of(Instruction)) // skip next
			}

		case .OP_LOADNIL:
			b := getarg_b(i)
			rb := cast(StkId)(cast(uintptr)base + uintptr(b) * size_of(TValue))
			for {
				setnilvalue(rb)
				rb = cast(StkId)(cast(uintptr)rb - size_of(TValue))
				if cast(uintptr)rb < cast(uintptr)ra {break}
			}

		case .OP_GETUPVAL:
			b := getarg_b(i)
			upvals_ptr := cast([^]^UpVal)&cl.upvals[0]
			uv := upvals_ptr[b]
			setobj2s(L, ra, uv.v)

		case .OP_GETGLOBAL:
			bx := getarg_bx(i)
			rb := &k[bx]
			// Protect(luaV_gettable(L, &cl.env, rb, ra))
			L.savedpc = pc
			env_val: TValue
			sethvalue(L, &env_val, cl.env)
			luaV_gettable(L, &env_val, rb, ra)
			base = L.base


		case .OP_GETTABLE:
			// Protect(luaV_gettable(L, RB(i), RKC(i), ra))
			rb: ^TValue
			rc: ^TValue

			// RB(i)
			b := getarg_b(i)
			rb = cast(StkId)(cast(uintptr)base + uintptr(b) * size_of(TValue))

			// RKC(i)
			c := getarg_c(i)
			if isk(c) {
				rc = &k[indexk(c)]
			} else {
				rc = cast(StkId)(cast(uintptr)base + uintptr(c) * size_of(TValue))
			}

			L.savedpc = pc
			luaV_gettable(L, rb, rc, ra)
			base = L.base

		case .OP_SETGLOBAL:
			bx := getarg_bx(i)
			rb := &k[bx]
			// Protect(luaV_settable(L, &cl.env, rb, ra))
			L.savedpc = pc
			env_val: TValue
			sethvalue(L, &env_val, cl.env)
			luaV_settable(L, &env_val, rb, ra)
			base = L.base

		case .OP_SETUPVAL:
			b := getarg_b(i)
			parent_upvals := cast([^]^UpVal)&cl.upvals[0]
			uv := parent_upvals[b]
			setobj(uv.v, ra)
			luaC_barrier(L, uv, ra)

		case .OP_SETTABLE:
			// Protect(luaV_settable(L, ra, RKB(i), RKC(i)))
			rb: ^TValue
			rc: ^TValue

			// RKB(i)
			b := getarg_b(i)
			if isk(b) {
				rb = &k[indexk(b)]
			} else {
				rb = cast(StkId)(cast(uintptr)base + uintptr(b) * size_of(TValue))
			}

			// RKC(i)
			c := getarg_c(i)
			if isk(c) {
				rc = &k[indexk(c)]
			} else {
				rc = cast(StkId)(cast(uintptr)base + uintptr(c) * size_of(TValue))
			}

			L.savedpc = pc
			luaV_settable(L, ra, rb, rc)
			base = L.base

		case .OP_NEWTABLE:
			b := getarg_b(i)
			c := getarg_c(i)
			t := luaH_new(L, libc.int(fb2int(libc.int(b))), libc.int(fb2int(libc.int(c))))
			sethvalue(L, ra, t)
			L.savedpc = pc
			luaC_checkGC(L)
			base = L.base

		case .OP_SELF:
			// StkId rb = RB(i);
			b := getarg_b(i)
			rb := cast(StkId)(cast(uintptr)base + uintptr(b) * size_of(TValue))

			setobjs2s(L, mem.ptr_offset(ra, 1), rb)

			// RKC(i)
			c := getarg_c(i)
			rc: ^TValue
			if isk(c) {
				rc = &k[indexk(c)]
			} else {
				rc = cast(StkId)(cast(uintptr)base + uintptr(c) * size_of(TValue))
			}

			// Protect(luaV_gettable(L, rb, RKC(i), ra));
			L.savedpc = pc
			luaV_gettable(L, rb, rc, ra)
			base = L.base

		case .OP_ADD, .OP_SUB, .OP_MUL, .OP_DIV, .OP_MOD, .OP_POW:
			// arith_op logic
			b := getarg_b(i)
			c := getarg_c(i)
			rb: ^TValue
			rc: ^TValue

			if isk(
				b,
			) {rb = &k[indexk(b)]} else {rb = cast(StkId)(cast(uintptr)base + uintptr(b) * size_of(TValue))}
			if isk(
				c,
			) {rc = &k[indexk(c)]} else {rc = cast(StkId)(cast(uintptr)base + uintptr(c) * size_of(TValue))}

			if ttisnumber(rb) && ttisnumber(rc) {
				nb := nvalue(rb)
				nc := nvalue(rc)
				res: lua_Number
				#partial switch op {
				case .OP_ADD:
					res = luai_numadd(nb, nc)
				case .OP_SUB:
					res = luai_numsub(nb, nc)
				case .OP_MUL:
					res = luai_nummul(nb, nc)
				case .OP_DIV:
					res = luai_numdiv(nb, nc)
				case .OP_MOD:
					res = luai_nummod(nb, nc)
				case .OP_POW:
					res = luai_numpow(nb, nc)
				case:
					res = 0 // unreachable
				}
				setnvalue(ra, res)
			} else {
				tm: TM
				#partial switch op {
				case .OP_ADD:
					tm = .TM_ADD
				case .OP_SUB:
					tm = .TM_SUB
				case .OP_MUL:
					tm = .TM_MUL
				case .OP_DIV:
					tm = .TM_DIV
				case .OP_MOD:
					tm = .TM_MOD
				case .OP_POW:
					tm = .TM_POW
				case:
					tm = .TM_ADD // unreachable
				}
				L.savedpc = pc
				Arith(L, ra, rb, rc, tm)
				base = L.base
			}

		case .OP_UNM:
			b := getarg_b(i)
			rb := cast(StkId)(cast(uintptr)base + uintptr(b) * size_of(TValue))
			if ttisnumber(rb) {
				nb := nvalue(rb)
				setnvalue(ra, luai_numunm(nb))
			} else {
				L.savedpc = pc
				Arith(L, ra, rb, rb, .TM_UNM)
				base = L.base
			}

		case .OP_NOT:
			b := getarg_b(i)
			rb := cast(StkId)(cast(uintptr)base + uintptr(b) * size_of(TValue))
			res := l_isfalse(rb) ? 1 : 0
			setbvalue(ra, libc.int(res))

		case .OP_LEN:
			a := getarg_a(i)
			b := getarg_b(i)
			ra := cast(StkId)(cast(uintptr)base + uintptr(a) * size_of(TValue))
			rb := cast(StkId)(cast(uintptr)base + uintptr(b) * size_of(TValue))

			L.savedpc = pc
			if ttistable(rb) {
				// Inline length optimization for tables without metamethods
				h := hvalue(rb)
				// Check for TM_LEN
				tm := fasttm(L, h.metatable, .TM_LEN)
				if tm == nil {
					setnvalue(ra, lua_Number(luaH_getn(h)))
				} else {
					if !call_binTM(L, rb, nilobject, ra, .TM_LEN) {
						luaG_typeerror_c(L, rb, "get length of")
					}
				}
			} else if ttisstring(rb) {
				setnvalue(ra, lua_Number((&rb.value.gc.ts).tsv.len))
			} else {
				if !call_binTM(L, rb, nilobject, ra, .TM_LEN) {
					luaG_typeerror_c(L, rb, "get length of")
				}
			}
			base = L.base

		case .OP_CONCAT:
			b := getarg_b(i)
			c := getarg_c(i)
			L.savedpc = pc
			luaV_concat(L, c - b + 1, c)
			luaC_checkGC(L)
			base = L.base

			// After GC/concat, Restore RA
			ra = cast(StkId)(cast(uintptr)base + uintptr(getarg_a(i)) * size_of(TValue))
			rb := cast(StkId)(cast(uintptr)base + uintptr(b) * size_of(TValue))
			setobjs2s(L, ra, rb)

		case .OP_JMP:
			sbx := getarg_sbx(i)
			pc = mem.ptr_offset(pc, int(sbx))

		case .OP_EQ:
			b := getarg_b(i)
			c := getarg_c(i)
			rb: ^TValue
			rc: ^TValue
			if isk(
				b,
			) {rb = &k[indexk(b)]} else {rb = cast(StkId)(cast(uintptr)base + uintptr(b) * size_of(TValue))}
			if isk(
				c,
			) {rc = &k[indexk(c)]} else {rc = cast(StkId)(cast(uintptr)base + uintptr(c) * size_of(TValue))}

			L.savedpc = pc
			equal := equalobj(L, rb, rc)
			base = L.base

			if (equal ? 1 : 0) == getarg_a(i) {
				// Jump
				next_i := pc[0]
				sbx := getarg_sbx(next_i)
				pc = mem.ptr_offset(pc, int(sbx) + 1)
			} else {
				pc = cast([^]Instruction)(cast(uintptr)pc + size_of(Instruction))
			}

		case .OP_LT:
			a := getarg_a(i)
			b := getarg_b(i)
			c := getarg_c(i)
			rb: ^TValue
			rc: ^TValue
			if isk(
				b,
			) {rb = &k[indexk(b)]} else {rb = cast(StkId)(cast(uintptr)base + uintptr(b) * size_of(TValue))}
			if isk(
				c,
			) {rc = &k[indexk(c)]} else {rc = cast(StkId)(cast(uintptr)base + uintptr(c) * size_of(TValue))}

			L.savedpc = pc
			less := luaV_lessthan(L, rb, rc)
			base = L.base

			if int(less) != int(a) {
				next_i := pc[0]
				sbx := getarg_sbx(next_i)
				pc = mem.ptr_offset(pc, int(sbx) + 1)
			} else {
				pc = cast([^]Instruction)(cast(uintptr)pc + size_of(Instruction))
			}

		case .OP_LE:
			b := getarg_b(i)
			c := getarg_c(i)
			rb: ^TValue
			rc: ^TValue
			if isk(
				b,
			) {rb = &k[indexk(b)]} else {rb = cast(StkId)(cast(uintptr)base + uintptr(b) * size_of(TValue))}
			if isk(
				c,
			) {rc = &k[indexk(c)]} else {rc = cast(StkId)(cast(uintptr)base + uintptr(c) * size_of(TValue))}

			L.savedpc = pc
			le := lessequal(L, rb, rc)
			base = L.base

			if int(le) != getarg_a(i) {
				next_i := pc[0]
				sbx := getarg_sbx(next_i)
				pc = mem.ptr_offset(pc, int(sbx) + 1)
			} else {
				pc = cast([^]Instruction)(cast(uintptr)pc + size_of(Instruction))
			}

		case .OP_TEST:
			c := getarg_c(i)
			cond := c

			if (l_isfalse(ra) ? 0 : 1) != cond {
				next_i := pc[0]
				sbx := getarg_sbx(next_i)
				pc = mem.ptr_offset(pc, int(sbx) + 1)
			} else {
				pc = cast([^]Instruction)(cast(uintptr)pc + size_of(Instruction))
			}

		case .OP_TESTSET:
			b := getarg_b(i)
			rb := cast(StkId)(cast(uintptr)base + uintptr(b) * size_of(TValue))
			c := getarg_c(i)
			cond := c

			if (l_isfalse(rb) ? 0 : 1) != cond {
				setobjs2s(L, ra, rb)
				next_i := pc[0]
				sbx := getarg_sbx(next_i)
				pc = mem.ptr_offset(pc, int(sbx) + 1)
			} else {
				pc = cast([^]Instruction)(cast(uintptr)pc + size_of(Instruction))
			}

		case .OP_CALL:
			b := getarg_b(i)
			nresults := getarg_c(i) - 1
			if b != 0 {
				L.top = cast(StkId)(cast(uintptr)ra + uintptr(b) * size_of(TValue))
			}
			L.savedpc = pc

			res := luaD_precall_pure(L, ra, libc.int(nresults))
			switch res {
			case PCRLUA:
				ncalls += 1
				// Update everything for new function
				ci = L.ci
				cl = &clvalue(ci.func).l
				p = cl.p
				k = p.k
				base = L.base
				pc = L.savedpc
				continue loop // Restart loop with new state

			case PCRC:
				if nresults >= 0 {
					L.top = L.ci.top
				}
				base = L.base

			case:
				// Yield
				return
			}

		case .OP_TAILCALL:
			b := getarg_b(i)
			if b != 0 {
				L.top = cast(StkId)(cast(uintptr)ra + uintptr(b) * size_of(TValue))
			}
			L.savedpc = pc

			res := luaD_precall_pure(L, ra, libc.int(LUA_MULTRET))
			switch res {
			case PCRLUA:
				// Tail call: replace frame
				// This is complex manual stack manipulation
				// For now, rely on Precall doing its job, but we need to update our local vars

				// In lvm.c:
				// CallInfo *ci = L->ci - 1;  /* previous frame */
				// int aux;
				// StkId func = ci->func;
				// StkId pfunc = (ci+1)->func;  /* previous function index */
				// ...
				// This logic is mostly handled in C right now for luaD_precall_c?
				// No, luaD_precall just sets up the frame. Tail call logic is largely in the VM loop in C.
				// For simplified migration, we might treat it like a regular call for now if we can't implement full tail call logic safely without more access.
				// BUT lvm.c source shows explicit tail call handling.
				// Since we are using luaD_precall_c from C, we assume it handles the C part, but the stack frame reuse is here.

				// CRITICAL: Implementing the tail call shuffle in Odin is risky without full access to all C macros and alignment.
				// Strategy: Treat as regular call for now (updates nexeccalls, loops back). It's less efficient but correct behaviorally (except stack depth).
				ncalls += 1
				ci = L.ci
				base = L.base
				cl = &clvalue(ci.func).l
				p = cl.p
				k = p.k
				pc = L.savedpc
				continue loop

			case PCRC:
				base = L.base

			case:
				// Yield
				return
			}

		case .OP_RETURN:
			b := getarg_b(i)
			if b != 0 {
				L.top = cast(StkId)(cast(uintptr)ra + uintptr(b - 1) * size_of(TValue))
			}
			if L.openupval != nil {
				luaF_close(L, base)
			}
			L.savedpc = pc
			b_res := luaD_poscall_pure(L, ra)

			ncalls -= 1
			if ncalls == 0 {
				return
			}

			if b_res != 0 {
				L.top = L.ci.top
			}

			// Restore state for previous function
			ci = L.ci
			cl = &clvalue(ci.func).l
			p = cl.p
			k = p.k
			base = L.base
			pc = L.savedpc
			continue loop

		case .OP_FORLOOP:
			// ra = internal index
			step := nvalue(cast(StkId)(cast(uintptr)ra + 2 * size_of(TValue)))
			limit := nvalue(cast(StkId)(cast(uintptr)ra + size_of(TValue)))
			val_stk := cast(StkId)ra

			idx := luai_numadd(nvalue(val_stk), step)
			setnvalue(val_stk, idx)

			go_back := false
			if step > 0 {
				if luai_numle(idx, limit) {go_back = true}
			} else {
				if luai_numle(limit, idx) {go_back = true}
			}

			if go_back {
				sbx := getarg_sbx(i)
				pc = mem.ptr_offset(pc, int(sbx))
				// copy index to external variable
				setnvalue(cast(StkId)(cast(uintptr)ra + 3 * size_of(TValue)), idx)
			}

		case .OP_FORPREP:
			init := ra
			plimit := cast(StkId)(cast(uintptr)ra + size_of(TValue))
			pstep := cast(StkId)(cast(uintptr)ra + 2 * size_of(TValue))

			L.savedpc = pc
			if !tonumber(init, ra) {
				luaG_runerror_c(L, "'for' initial value must be a number")
			}
			if !tonumber(plimit, plimit) {
				luaG_runerror_c(L, "'for' limit must be a number")
			}
			if !tonumber(pstep, pstep) {
				luaG_runerror_c(L, "'for' step must be a number")
			}

			// Subtract step from init
			setnvalue(ra, luai_numsub(nvalue(ra), nvalue(pstep)))

			sbx := getarg_sbx(i)
			pc = mem.ptr_offset(pc, int(sbx))

		case .OP_TFORLOOP:
			cb := cast(StkId)(cast(uintptr)ra + 3 * size_of(TValue))
			setobjs2s(
				L,
				cast(StkId)(cast(uintptr)cb + 2 * size_of(TValue)),
				cast(StkId)(cast(uintptr)ra + 2 * size_of(TValue)),
			)
			setobjs2s(
				L,
				cast(StkId)(cast(uintptr)cb + size_of(TValue)),
				cast(StkId)(cast(uintptr)ra + size_of(TValue)),
			)
			setobjs2s(L, cb, ra)

			L.top = cast(StkId)(cast(uintptr)cb + 3 * size_of(TValue))

			L.savedpc = pc
			fmt.printf(
				"DEBUG: OP_TFORLOOP calling function at %p (type %d), nresults=%d\n",
				ra,
				ra.tt,
				getarg_c(i),
			)
			luaD_call_pure(L, cb, libc.int(getarg_c(i)))
			base = L.base
			L.top = L.ci.top

			// previous call may change stack, so recalculate RA/CB
			// We need to fetch RA again properly if base changed (handled by base update)
			ra = cast(StkId)(cast(uintptr)base + uintptr(getarg_a(i)) * size_of(TValue))
			cb = cast(StkId)(cast(uintptr)ra + 3 * size_of(TValue))

			fmt.printf("DEBUG: OP_TFORLOOP returned, first result type %d\n", cb.tt)
			if !ttisnil(cb) {
				setobjs2s(L, cast(StkId)(cast(uintptr)cb - size_of(TValue)), cb)
				sbx := getarg_sbx(pc[0])
				pc = mem.ptr_offset(pc, int(sbx))
			} else {
				pc = cast([^]Instruction)(cast(uintptr)pc + size_of(Instruction))
			}

		case .OP_SETLIST:
			a := getarg_a(i)
			b := getarg_b(i)
			c := getarg_c(i)
			if b == 0 {
				b = int((cast(uintptr)L.top - cast(uintptr)ra) / size_of(TValue)) - 1
				L.top = L.ci.top
			}
			n := b
			if c == 0 {
				c = int(pc[0])
				pc = cast([^]Instruction)(cast(uintptr)pc + size_of(Instruction))
			}

			h := hvalue(ra)
			last := ((c - 1) * LFIELDS_PER_FLUSH) + n

			if last > int(h.sizearray) {
				luaH_resizearray(L, h, int(last))
				base = L.base
				ra = cast(StkId)(cast(uintptr)base + uintptr(getarg_a(i)) * size_of(TValue))
			}

			for ; n > 0; n -= 1 {
				val_ptr := cast(StkId)(cast(uintptr)ra + uintptr(n) * size_of(TValue))
				temp_val: TValue
				setobj(&temp_val, val_ptr)
				slot := luaH_setnum(L, h, libc.int(last))
				last -= 1
				setobj2t(L, slot, &temp_val)
				luaC_barriert(L, h, &temp_val)
			}
			base = L.base

		case .OP_CLOSE:
			luaF_close(L, ra)

		case .OP_CLOSURE:
			bx := getarg_bx(i)
			new_p := p.p[bx]
			nup := new_p.nups
			ncl := luaF_newLclosure(L, libc.int(nup), cl.env)
			ncl.l.p = new_p

			for j := 0; j < int(nup); j += 1 {
				inst := pc[0]
				pc = cast([^]Instruction)(cast(uintptr)pc + size_of(Instruction))

				op_inst := get_opcode(inst)
				upvals_ptr := cast([^]^UpVal)&ncl.l.upvals[0]
				if op_inst == .OP_GETUPVAL {
					b := getarg_b(inst)
					upvals_ptr[j] = cl.upvals[b]
				} else {
					// OP_MOVE
					b := getarg_b(inst)
					upvals_ptr[j] = luaF_findupval(
						L,
						cast(StkId)(cast(uintptr)base + uintptr(b) * size_of(TValue)),
					)
					// REFRESH after potential GC in findupval
					base = L.base
					ci = L.ci
					cl = &clvalue(ci.func).l
				}
			}

			base = L.base
			ci = L.ci
			if ci.func == nil {
				fmt.eprintln("FATAL: ci.func is nil at OP_CLOSURE!")
				_ = (cast(^int)nil)^
			}
			if !ttisfunction(ci.func) {
				fmt.eprintln("FATAL: ci.func is not a function at OP_CLOSURE! tt =", ci.func.tt)
				_ = (cast(^int)nil)^
			}
			if ci.func.value.gc == nil {
				fmt.eprintln("FATAL: ci.func.value.gc is nil at OP_CLOSURE!")
				_ = (cast(^int)nil)^
			}
			ra = cast(StkId)(cast(uintptr)base + uintptr(getarg_a(i)) * size_of(TValue))
			cl = &clvalue(ci.func).l
			setclvalue(L, ra, ncl)
			L.savedpc = pc
			luaC_checkGC(L)
			base = L.base
			base = L.base

		case .OP_VARARG:
			b := getarg_b(i) - 1
			ci_func := L.ci.func
			// n = cast_int(base - ci->func) - cl->p->numparams - 1
			n :=
				int((cast(uintptr)base - cast(uintptr)ci_func) / size_of(TValue)) -
				int(p.numparams) -
				1

			if b == LUA_MULTRET {
				luaD_checkstack(L, n)
				base = L.base // REFRESH BASE
				// Re-fetch RA after checkstack
				ra = cast(StkId)(cast(uintptr)base + uintptr(getarg_a(i)) * size_of(TValue))
				b = n
				L.top = cast(StkId)(cast(uintptr)ra + uintptr(n) * size_of(TValue))
			}

			for j := 0; j < b; j += 1 {
				if j < n {
					// setobjs2s(L, ra+j, base - n + j)
					src := cast(StkId)(cast(uintptr)base - uintptr(n - j) * size_of(TValue))
					dest := cast(StkId)(cast(uintptr)ra + uintptr(j) * size_of(TValue))
					setobjs2s(L, dest, src)
				} else {
					dest := cast(StkId)(cast(uintptr)ra + uintptr(j) * size_of(TValue))
					setnilvalue(dest)
				}
			}
		}
	}
}

// Trace execution helper
traceexec :: proc(L: ^lua_State, pc: [^]Instruction) {
	mask := L.hookmask
	oldpc := L.savedpc
	L.savedpc = pc

	if (mask & LUA_MASKCOUNT) != 0 && L.hookcount == 0 {
		resethookcount(L)
		luaD_callhook(L, LUA_HOOKCOUNT, -1)
	}

	if (mask & LUA_MASKLINE) != 0 {
		p := ci_func(L.ci).l.p
		npc := pcRel(pc, p)
		newline := get_line_info(p, npc)

		old_npc := pcRel(oldpc, p)
		old_newline := get_line_info(p, old_npc)

		if npc == 0 || cast(uintptr)pc <= cast(uintptr)oldpc || newline != old_newline {
			luaD_callhook(L, LUA_HOOKLINE, int(newline))
		}
	}
}
