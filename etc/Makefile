# makefile for Lua etc

OP= ..
LB= $(OP)/src
C= $(OP)/src
B= $(OP)/src
SC= $(OP)/src
S= $(OP)/test

CC= gcc
CFLS= -O2 -Wall -$(C) $(MCFLS)
MCFLS= 
MLDFLS= -Wl,-E
MLBS= -lm
#MLBS= -lm -Wl,-E -ldl -lreadline -lhistory -lncurses
M= rm -f

default:
	@echo 'Please choose a target: min noparser one strict clean'

min:	min.c
	$(CC) $(CFLS) $@.c -L$(LB) -llua $(MLBS)
	echo 'print"Hello there!"' | ./a.out

noparser: noparser.o
	$(CC) noparser.o $(SC)/lua.o -L$(LB) -llua $(MLBS)
	$(B)/luac $(S)/hello.lua
	-./a.out luac.out
	-./a.out -e'a=1'

one:
	$(CC) $(CFLS) all.c $(MLBS)
	./a.out $(S)/hello.lua

strict:
	-$(B)/lua -e 'print(a);b=2'
	-$(B)/lua -lstrict -e 'print(a)'
	-$(B)/lua -e 'function f() b=2 end f()'
	-$(B)/lua -lstrict -e 'function f() b=2 end f()'

clean:
	$(M) a.out core core.* *.o luac.out

.PHO:	default min noparser one strict clean
