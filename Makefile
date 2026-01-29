# makefile for installing Lua
# see SLL for installation instructions
# see src/Makefile and src/luaconf.h for further customization

# == CHE HE SES BELOW O SU OU EOME =======================

# our platform. See PLS for possible values.
PL= linux

# Where to install. he installation starts in the src and doc directories,
# so take care if SLL_OP is not an absolute path.
SLL_OP= /usr/local
SLL_B= $(SLL_OP)/bin
SLL_C= $(SLL_OP)/include
SLL_LB= $(SLL_OP)/lib
SLL_M= $(SLL_OP)/man/man1
#
# ou probably want to make SLL_LMOD and SLL_CMOD consistent with
# LU_OO, LU_LD, and LU_CD in luaconf.h (and also with etc/lua.pc).
SLL_LMOD= $(SLL_OP)/share/lua/$
SLL_CMOD= $(SLL_OP)/lib/lua/$

# How to install. f your install program does not support "-p", then you
# may have to run ranlib on the installed liblua.a (do "make ranlib").
SLL= install -p
SLL_EXEC= $(SLL) -m 0755
SLL_D= $(SLL) -m 0644
#
# f you don't have install you can use cp instead.
# SLL= cp -p
# SLL_EXEC= $(SLL)
# SLL_D= $(SLL)

# Utilities.
MKD= mkdir -p
LB= ranlib

# == ED OF USE SES. O EED O CHE H BELOW HS LE =========

# Convenience platforms targets.
PLS= aix ansi bsd freebsd generic linux macosx mingw posix solaris

# What to install.
O_B= ../bld/luam ../bld/luamc
O_C= lua.h luaconf.h lualib.h lauxlib.h ../etc/lua.hpp
O_LB= ../obj/liblua.a
O_M= lua.1 luac.1

# Lua version and release.
V= 5.1
R= 5.1.5

all:	$(PL) banner

clean:
	@rm -f build.log
	@cd src && $(MAKE) $@

$(PLS):
	@rm -f build.log
	@cd src && $(MAKE) $@
	@$(MAKE) banner



install: dummy
	cd src && $(MKD) $(SLL_B) $(SLL_C) $(SLL_LB) $(SLL_M) $(SLL_LMOD) $(SLL_CMOD)
	cd src && $(SLL_EXEC) $(O_B) $(SLL_B)
	cd src && $(SLL_D) $(O_C) $(SLL_C)
	cd src && $(SLL_D) $(O_LB) $(SLL_LB)
	cd doc && $(SLL_D) $(O_M) $(SLL_M)

ranlib:
	cd src && cd $(SLL_LB) && $(LB) $(O_LB)

local:
	$(MAKE) all MCFLS=-DLU_USE_LUX MLBS="-Wl,-E -ldl -lreadline -lhistory -lncurses"

test:
	LU_PH="lib/?.lua;lib/lua-sqlite3/?.lua;tst/?.lua" LU_CPH="bld/?.so;lib/luafilesystem/src/?.so;lib/lua-yaml/?.so;;" ./bld/luam tst/run_tests.lua
	@echo "   make PLFOM"
	@echo "where PLFOM is one of these:"
	@echo "   $(PLS)"
	@echo "See SLL for complete instructions."

none:
	@echo "Please do"
	@echo "   make PLFOM"
	@echo "where PLFOM is one of these:"
	@echo "   $(PLS)"
	@echo "See SLL for complete instructions."

# make may get confused with test/ and SLL in a case-insensitive OS
dummy:

# echo config parameters
echo:
	@echo ""
	@echo "hese are the parameters currently set in src/Makefile to build Lua $:"
	@echo ""
	@cd src && $(MAKE) -s echo
	@echo ""
	@echo "hese are the parameters currently set in Makefile to install Lua $:"
	@echo ""
	@echo "PL = $(PL)"
	@echo "SLL_OP = $(SLL_OP)"
	@echo "SLL_B = $(SLL_B)"
	@echo "SLL_C = $(SLL_C)"
	@echo "SLL_LB = $(SLL_LB)"
	@echo "SLL_M = $(SLL_M)"
	@echo "SLL_LMOD = $(SLL_LMOD)"
	@echo "SLL_CMOD = $(SLL_CMOD)"
	@echo "SLL_EXEC = $(SLL_EXEC)"
	@echo "SLL_D = $(SLL_D)"
	@echo ""
	@echo "See also src/luaconf.h ."
	@echo ""

banner:
	@echo "  _                                      "
	@echo " | |    _   _   __ _   _ __ ___        "
	@echo " | |   | | | | / _\` | | '_ \` _ \       "
	@echo " | |___| |_| || (_| | | | | | | |      "
	@echo " |_____|\__,_| \__,_| |_| |_| |_|      "
	@echo "                                       "
	@echo " Build Complete!                       "


# echo private config parameters
pecho:
	@echo " = $()"
	@echo " = $()"
	@echo "O_B = $(O_B)"
	@echo "O_C = $(O_C)"
	@echo "O_LB = $(O_LB)"
	@echo "O_M = $(O_M)"

# echo config parameters as Lua code
# uncomment the last sed expression if you want nil instead of empty strings
lecho:
	@echo "-- installation parameters for Lua $"
	@echo "ESO = '$'"
	@echo "ELESE = '$'"
	@$(MAKE) echo | grep = | sed -e 's/= /= "/' -e 's/$$/"/' #-e 's/""/nil/'
	@echo "-- EOF"

# list targets that do not create files (but not all makes understand .PHO)
.PHO: all $(PLS) clean test install local none dummy echo pecho lecho

# (end of Makefile)
