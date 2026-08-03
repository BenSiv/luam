# makefile for installing Lua
# see doc/install.md for installation instructions
# see src/Makefile and src/luaconf.h for further customization

# == CHANGE THE SETTINGS BELOW TO SUIT YOUR ENVIRONMENT =======================

MAKEFLAGS += --no-print-directory

# Your platform. See PLS for possible values.
PL= linux

# Verbosity control
ifeq ($(V),1)
  Q=
  REDIRECT=
else
  Q=@
  REDIRECT= >> log/build.log 2>&1
endif

# Where to install. The installation starts in the src and doc directories,
# so take care if SLL_OP is not an absolute path.
SLL_OP= /usr/local
SLL_B= $(SLL_OP)/bin
SLL_C= $(SLL_OP)/include
SLL_LB= $(SLL_OP)/lib
SLL_M= $(SLL_OP)/man/man1
#
# You probably want to make SLL_LMOD and SLL_CMOD consistent with
# LUA_ROOT, LUA_LDIR, and LUA_CDIR in luaconf.h (and also with etc/lua.pc).
SLL_LMOD= $(SLL_OP)/share/lua/$V
SLL_CMOD= $(SLL_OP)/lib/lua/$V

# How to install. If your install program does not support "-p", then you
# may have to run ranlib on the installed liblua.a (do "make ranlib").
SLL= install -p
SLL_EXEC= $(SLL) -m 0755
SLL_D= $(SLL) -m 0644
#
# If you don't have install you can use cp instead.
# SLL= cp -p
# SLL_EXEC= $(SLL)
# SLL_D= $(SLL)

# Utilities.
MKD= mkdir -p
LB= ranlib

# == END OF USER SETTINGS. NO NEED TO CHANGE ANYTHING BELOW THIS LINE =========

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
	@mkdir -p log
	$(Q)rm -f log/build.log
	$(Q)cd src && $(MAKE) $@ V=$(V)

$(PLS):
	@mkdir -p log
	$(Q)rm -f log/build.log
	$(Q)cd src && $(MAKE) $@ V=$(V)
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
	$(MAKE) all MYCFLAGS=-DLUA_USE_LINUX MYLIBS="-Wl,-E -ldl -lreadline -lhistory -lncurses"

test:
	LUA_PATH="lib/?.lua;lib/lua-sqlite3/?.lua;tst/?.lua" LUA_CPATH="bld/?.so;lib/luafilesystem/src/?.so;lib/lua-yaml/?.so;;" ./bld/luam tst/run_tests.lua
	@echo "   make PLATFORM"
	@echo "where PLATFORM is one of these:"
	@echo "   $(PLS)"
	@echo "See doc/install.md for complete instructions."

none:
	@echo "Please do"
	@echo "   make PLATFORM"
	@echo "where PLATFORM is one of these:"
	@echo "   $(PLS)"
	@echo "See doc/install.md for complete instructions."

# make may get confused with test/ and SLL in a case-insensitive OS
dummy:

# echo config parameters
echo:
	@echo ""
	@echo "These are the parameters currently set in src/Makefile to build Lua $R:"
	@echo ""
	@cd src && $(MAKE) -s echo
	@echo ""
	@echo "These are the parameters currently set in Makefile to install Lua $R:"
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
	@echo "V = $V"
	@echo "R = $R"
	@echo "O_B = $(O_B)"
	@echo "O_C = $(O_C)"
	@echo "O_LB = $(O_LB)"
	@echo "O_M = $(O_M)"

# echo config parameters as Lua code
# uncomment the last sed expression if you want nil instead of empty strings
lecho:
	@echo "-- installation parameters for Lua $R"
	@echo "VERSION = '$V'"
	@echo "RELEASE = '$R'"
	@$(MAKE) echo | grep = | sed -e 's/= /= "/' -e 's/$$/"/' #-e 's/""/nil/'
	@echo "-- EOF"

# list targets that do not create files (but not all makes understand .PHONY)
.PHONY: all $(PLS) clean test install local none dummy echo pecho lecho

# (end of Makefile)
