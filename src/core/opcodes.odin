// Opcodes for Lua virtual machine
// Migrated from lopcodes.c/h
package core

import "core:c"

/*===========================================================================
  We assume that instructions are unsigned numbers.
  All instructions have an opcode in the first 6 bits.
  Instructions can have the following fields:
        `A' : 8 bits
        `B' : 9 bits
        `C' : 9 bits
        `Bx' : 18 bits (`B' and `C' together)
        `sBx' : signed Bx

  A signed argument is represented in excess K; that is, the number
  value is the unsigned value minus K. K is exactly the maximum value
  for that argument (so that -max is represented by 0, and +max is
  represented by 2*max), which is half the maximum for the corresponding
  unsigned argument.
===========================================================================*/

// Instruction type - 32-bit unsigned
Instruction :: u32

// Basic instruction formats
OpMode :: enum u8 {
	iABC, // Format: A:8, B:9, C:9
	iABx, // Format: A:8, Bx:18
	iAsBx, // Format: A:8, sBx:18 (signed)
}

// Size and position of opcode arguments
SIZE_C :: 9
SIZE_B :: 9
SIZE_Bx :: SIZE_C + SIZE_B // 18
SIZE_A :: 8
SIZE_OP :: 6

POS_OP :: 0
POS_A :: POS_OP + SIZE_OP // 6
POS_C :: POS_A + SIZE_A // 14
POS_B :: POS_C + SIZE_C // 23
POS_Bx :: POS_C // 14

// Limits for opcode arguments
MAXARG_Bx :: (1 << SIZE_Bx) - 1 // 262143
MAXARG_sBx :: MAXARG_Bx >> 1 // 131071
MAXARG_A :: (1 << SIZE_A) - 1 // 255
MAXARG_B :: (1 << SIZE_B) - 1 // 511
MAXARG_C :: (1 << SIZE_C) - 1 // 511

// Creates a mask with `n' 1 bits at position `p'
mask1 :: #force_inline proc(n: u32, p: u32) -> Instruction {
	return (~((~Instruction(0)) << n)) << p
}

// Creates a mask with `n' 0 bits at position `p'
mask0 :: #force_inline proc(n: u32, p: u32) -> Instruction {
	return ~mask1(n, p)
}

// Instruction manipulation
get_opcode :: #force_inline proc(i: Instruction) -> OpCode {
	return OpCode((i >> POS_OP) & mask1(SIZE_OP, 0))
}

set_opcode :: #force_inline proc(i: ^Instruction, o: OpCode) {
	i^ = (i^ & mask0(SIZE_OP, POS_OP)) | ((Instruction(o) << POS_OP) & mask1(SIZE_OP, POS_OP))
}

getarg_a :: #force_inline proc(i: Instruction) -> int {
	return int((i >> POS_A) & mask1(SIZE_A, 0))
}

setarg_a :: #force_inline proc(i: ^Instruction, a: int) {
	i^ = (i^ & mask0(SIZE_A, POS_A)) | ((Instruction(a) << POS_A) & mask1(SIZE_A, POS_A))
}

getarg_b :: #force_inline proc(i: Instruction) -> int {
	return int((i >> POS_B) & mask1(SIZE_B, 0))
}

setarg_b :: #force_inline proc(i: ^Instruction, b: int) {
	i^ = (i^ & mask0(SIZE_B, POS_B)) | ((Instruction(b) << POS_B) & mask1(SIZE_B, POS_B))
}

getarg_c :: #force_inline proc(i: Instruction) -> int {
	return int((i >> POS_C) & mask1(SIZE_C, 0))
}

setarg_c :: #force_inline proc(i: ^Instruction, c: int) {
	i^ = (i^ & mask0(SIZE_C, POS_C)) | ((Instruction(c) << POS_C) & mask1(SIZE_C, POS_C))
}

getarg_bx :: #force_inline proc(i: Instruction) -> int {
	return int((i >> POS_Bx) & mask1(SIZE_Bx, 0))
}

setarg_bx :: #force_inline proc(i: ^Instruction, bx: int) {
	i^ = (i^ & mask0(SIZE_Bx, POS_Bx)) | ((Instruction(bx) << POS_Bx) & mask1(SIZE_Bx, POS_Bx))
}

getarg_sbx :: #force_inline proc(i: Instruction) -> int {
	return getarg_bx(i) - MAXARG_sBx
}

setarg_sbx :: #force_inline proc(i: ^Instruction, sbx: int) {
	setarg_bx(i, sbx + MAXARG_sBx)
}

// Instruction creation
create_abc :: #force_inline proc(op: OpCode, a: int, b: int, c: int) -> Instruction {
	return(
		(Instruction(op) << POS_OP) |
		(Instruction(a) << POS_A) |
		(Instruction(b) << POS_B) |
		(Instruction(c) << POS_C) \
	)
}

create_abx :: #force_inline proc(op: OpCode, a: int, bx: int) -> Instruction {
	return (Instruction(op) << POS_OP) | (Instruction(a) << POS_A) | (Instruction(bx) << POS_Bx)
}

// RK (register/constant) index operations
BITRK :: 1 << (SIZE_B - 1) // 256

// Test whether value is a constant
isk :: #force_inline proc(x: int) -> bool {
	return (x & BITRK) != 0
}

// Gets the index of the constant
indexk :: #force_inline proc(r: int) -> int {
	return r & ~int(BITRK)
}

MAXINDEXRK :: BITRK - 1 // 255

// Code a constant index as a RK value
rkask :: #force_inline proc(x: int) -> int {
	return x | BITRK
}

// Invalid register that fits in 8 bits
NO_REG :: MAXARG_A

// Opcodes - ORDER OP (must match luaP_opnames order)
OpCode :: enum u8 {
	OP_MOVE, // A B     R(A) := R(B)
	OP_LOADK, // A Bx    R(A) := Kst(Bx)
	OP_LOADBOOL, // A B C   R(A) := (Bool)B; if (C) pc++
	OP_LOADNIL, // A B     R(A) := ... := R(B) := nil
	OP_GETUPVAL, // A B     R(A) := UpValue[B]
	OP_GETGLOBAL, // A Bx    R(A) := Gbl[Kst(Bx)]
	OP_GETTABLE, // A B C   R(A) := R(B)[RK(C)]
	OP_SETGLOBAL, // A Bx    Gbl[Kst(Bx)] := R(A)
	OP_SETUPVAL, // A B     UpValue[B] := R(A)
	OP_SETTABLE, // A B C   R(A)[RK(B)] := RK(C)
	OP_NEWTABLE, // A B C   R(A) := {} (size = B,C)
	OP_SELF, // A B C   R(A+1) := R(B); R(A) := R(B)[RK(C)]
	OP_ADD, // A B C   R(A) := RK(B) + RK(C)
	OP_SUB, // A B C   R(A) := RK(B) - RK(C)
	OP_MUL, // A B C   R(A) := RK(B) * RK(C)
	OP_DIV, // A B C   R(A) := RK(B) / RK(C)
	OP_MOD, // A B C   R(A) := RK(B) % RK(C)
	OP_POW, // A B C   R(A) := RK(B) ^ RK(C)
	OP_UNM, // A B     R(A) := -R(B)
	OP_NOT, // A B     R(A) := not R(B)
	OP_LEN, // A B     R(A) := length of R(B)
	OP_CONCAT, // A B C   R(A) := R(B).. ... ..R(C)
	OP_JMP, // sBx     pc+=sBx
	OP_EQ, // A B C   if ((RK(B) == RK(C)) ~= A) then pc++
	OP_LT, // A B C   if ((RK(B) <  RK(C)) ~= A) then pc++
	OP_LE, // A B C   if ((RK(B) <= RK(C)) ~= A) then pc++
	OP_TEST, // A C     if not (R(A) <=> C) then pc++
	OP_TESTSET, // A B C   if (R(B) <=> C) then R(A) := R(B) else pc++
	OP_CALL, // A B C   R(A), ... ,R(A+C-2) := R(A)(R(A+1), ... ,R(A+B-1))
	OP_TAILCALL, // A B C   return R(A)(R(A+1), ... ,R(A+B-1))
	OP_RETURN, // A B     return R(A), ... ,R(A+B-2)
	OP_FORLOOP, // A sBx   R(A)+=R(A+2); if R(A) <?= R(A+1) then { pc+=sBx; R(A+3)=R(A) }
	OP_FORPREP, // A sBx   R(A)-=R(A+2); pc+=sBx
	OP_TFORLOOP, // A C     R(A+3), ... ,R(A+2+C) := R(A)(R(A+1), R(A+2)); if R(A+3) ~= nil then R(A+2)=R(A+3) else pc++
	OP_SETLIST, // A B C   R(A)[(C-1)*FPF+i] := R(A+i), 1 <= i <= B
	OP_CLOSE, // A       close all variables in the stack up to (>=) R(A)
	OP_CLOSURE, // A Bx    R(A) := closure(KPROTO[Bx], R(A), ... ,R(A+n))
	OP_VARARG, // A B     R(A), R(A+1), ..., R(A+B-1) = vararg
}

NUM_OPCODES :: int(OpCode.OP_VARARG) + 1

// Opcode names for debugging
@(export, link_name = "luaP_opnames")
opnames := [NUM_OPCODES + 1]cstring {
	"MOVE",
	"LOADK",
	"LOADBOOL",
	"LOADNIL",
	"GETUPVAL",
	"GETGLOBAL",
	"GETTABLE",
	"SETGLOBAL",
	"SETUPVAL",
	"SETTABLE",
	"NEWTABLE",
	"SELF",
	"ADD",
	"SUB",
	"MUL",
	"DIV",
	"MOD",
	"POW",
	"UNM",
	"NOT",
	"LEN",
	"CONCAT",
	"JMP",
	"EQ",
	"LT",
	"LE",
	"TEST",
	"TESTSET",
	"CALL",
	"TAILCALL",
	"RETURN",
	"FORLOOP",
	"FORPREP",
	"TFORLOOP",
	"SETLIST",
	"CLOSE",
	"CLOSURE",
	"VARARG",
	nil,
}

// Argument mode types
OpArgMask :: enum u8 {
	OpArgN, // argument is not used
	OpArgU, // argument is used
	OpArgR, // argument is a register or a jump offset
	OpArgK, // argument is a constant or register/constant
}

// Opmode encoding: bits 0-1: op mode, bits 2-3: C arg, bits 4-5: B arg, bit 6: sets A, bit 7: is test
opmode :: #force_inline proc "contextless" (
	t: u8,
	a: u8,
	b: OpArgMask,
	c: OpArgMask,
	m: OpMode,
) -> u8 {
	return (t << 7) | (a << 6) | (u8(b) << 4) | (u8(c) << 2) | u8(m)
}

// Opmode table for all opcodes
@(export, link_name = "luaP_opmodes")
opmodes := [NUM_OPCODES]u8 {
	opmode(0, 1, .OpArgR, .OpArgN, .iABC), // OP_MOVE
	opmode(0, 1, .OpArgK, .OpArgN, .iABx), // OP_LOADK
	opmode(0, 1, .OpArgU, .OpArgU, .iABC), // OP_LOADBOOL
	opmode(0, 1, .OpArgR, .OpArgN, .iABC), // OP_LOADNIL
	opmode(0, 1, .OpArgU, .OpArgN, .iABC), // OP_GETUPVAL
	opmode(0, 1, .OpArgK, .OpArgN, .iABx), // OP_GETGLOBAL
	opmode(0, 1, .OpArgR, .OpArgK, .iABC), // OP_GETTABLE
	opmode(0, 0, .OpArgK, .OpArgN, .iABx), // OP_SETGLOBAL
	opmode(0, 0, .OpArgU, .OpArgN, .iABC), // OP_SETUPVAL
	opmode(0, 0, .OpArgK, .OpArgK, .iABC), // OP_SETTABLE
	opmode(0, 1, .OpArgU, .OpArgU, .iABC), // OP_NEWTABLE
	opmode(0, 1, .OpArgR, .OpArgK, .iABC), // OP_SELF
	opmode(0, 1, .OpArgK, .OpArgK, .iABC), // OP_ADD
	opmode(0, 1, .OpArgK, .OpArgK, .iABC), // OP_SUB
	opmode(0, 1, .OpArgK, .OpArgK, .iABC), // OP_MUL
	opmode(0, 1, .OpArgK, .OpArgK, .iABC), // OP_DIV
	opmode(0, 1, .OpArgK, .OpArgK, .iABC), // OP_MOD
	opmode(0, 1, .OpArgK, .OpArgK, .iABC), // OP_POW
	opmode(0, 1, .OpArgR, .OpArgN, .iABC), // OP_UNM
	opmode(0, 1, .OpArgR, .OpArgN, .iABC), // OP_NOT
	opmode(0, 1, .OpArgR, .OpArgN, .iABC), // OP_LEN
	opmode(0, 1, .OpArgR, .OpArgR, .iABC), // OP_CONCAT
	opmode(0, 0, .OpArgR, .OpArgN, .iAsBx), // OP_JMP
	opmode(1, 0, .OpArgK, .OpArgK, .iABC), // OP_EQ
	opmode(1, 0, .OpArgK, .OpArgK, .iABC), // OP_LT
	opmode(1, 0, .OpArgK, .OpArgK, .iABC), // OP_LE
	opmode(1, 1, .OpArgR, .OpArgU, .iABC), // OP_TEST
	opmode(1, 1, .OpArgR, .OpArgU, .iABC), // OP_TESTSET
	opmode(0, 1, .OpArgU, .OpArgU, .iABC), // OP_CALL
	opmode(0, 1, .OpArgU, .OpArgU, .iABC), // OP_TAILCALL
	opmode(0, 0, .OpArgU, .OpArgN, .iABC), // OP_RETURN
	opmode(0, 1, .OpArgR, .OpArgN, .iAsBx), // OP_FORLOOP
	opmode(0, 1, .OpArgR, .OpArgN, .iAsBx), // OP_FORPREP
	opmode(1, 0, .OpArgN, .OpArgU, .iABC), // OP_TFORLOOP
	opmode(0, 0, .OpArgU, .OpArgU, .iABC), // OP_SETLIST
	opmode(0, 0, .OpArgN, .OpArgN, .iABC), // OP_CLOSE
	opmode(0, 1, .OpArgU, .OpArgN, .iABx), // OP_CLOSURE
	opmode(0, 1, .OpArgU, .OpArgN, .iABC), // OP_VARARG
}

// Opmode query functions
get_opmode :: #force_inline proc(op: OpCode) -> OpMode {
	return OpMode(opmodes[op] & 3)
}

get_bmode :: #force_inline proc(op: OpCode) -> OpArgMask {
	return OpArgMask((opmodes[op] >> 4) & 3)
}

get_cmode :: #force_inline proc(op: OpCode) -> OpArgMask {
	return OpArgMask((opmodes[op] >> 2) & 3)
}

test_amode :: #force_inline proc(op: OpCode) -> bool {
	return (opmodes[op] & (1 << 6)) != 0
}

test_tmode :: #force_inline proc(op: OpCode) -> bool {
	return (opmodes[op] & (1 << 7)) != 0
}

// Number of list items to accumulate before a SETLIST instruction
LFIELDS_PER_FLUSH :: 50
