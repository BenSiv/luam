# makefile for building Lua
# see ../INSTALL for installation instructions
# see ../Makefile and luaconf.h for further customization

# == CHANGE THE SETTINGS BELOW TO SUIT YOUR ENVIRONMENT =======================

# Your platform. See PLATS for possible values.
PLAT= none

CC= gcc
CFLAGS= -O2 -Wall $(MYCFLAGS)
AR= ar rcu
RANLIB= ranlib
RM= rm -f
LIBS= -lm $(MYLIBS)

MYCFLAGS=
MYLDFLAGS=
MYLIBS=

# == END OF USER SETTINGS. NO NEED TO CHANGE ANYTHING BELOW THIS LINE =========

PLATS= aix ansi bsd freebsd generic linux macosx mingw posix solaris

OBJ_DIR= ../obj
MKDIR= mkdir -p

LUA_A=	$(OBJ_DIR)/liblua.a
CORE_O=	$(OBJ_DIR)/lapi.o $(OBJ_DIR)/lcode.o $(OBJ_DIR)/ldebug.o $(OBJ_DIR)/ldo.o $(OBJ_DIR)/ldump.o $(OBJ_DIR)/lfunc.o $(OBJ_DIR)/lgc.o $(OBJ_DIR)/llex.o $(OBJ_DIR)/lmem.o \
	$(OBJ_DIR)/lobject.o $(OBJ_DIR)/lopcodes.o $(OBJ_DIR)/lparser.o $(OBJ_DIR)/lstate.o $(OBJ_DIR)/lstring.o $(OBJ_DIR)/ltable.o $(OBJ_DIR)/ltm.o  \
	$(OBJ_DIR)/lundump.o $(OBJ_DIR)/lvm.o $(OBJ_DIR)/lzio.o
LIB_O=	$(OBJ_DIR)/lauxlib.o $(OBJ_DIR)/lbaselib.o $(OBJ_DIR)/ldblib.o $(OBJ_DIR)/liolib.o $(OBJ_DIR)/lmathlib.o $(OBJ_DIR)/loslib.o $(OBJ_DIR)/ltablib.o \
	$(OBJ_DIR)/lstrlib.o $(OBJ_DIR)/loadlib.o $(OBJ_DIR)/linit.o $(OBJ_DIR)/bit.o $(OBJ_DIR)/struct.o

BIN_DIR= ../bin
LUA_T=	$(BIN_DIR)/luam
LUA_O=	$(OBJ_DIR)/lua.o

LUAC_T=	$(BIN_DIR)/luamc
LUAC_O=	$(OBJ_DIR)/luac.o $(OBJ_DIR)/print.o

ALL_O= $(CORE_O) $(LIB_O) $(LUA_O) $(LUAC_O)
ALL_T= $(LUA_A) $(LUA_T) $(LUAC_T)
ALL_A= $(LUA_A)

default: $(PLAT)

all:	$(ALL_T)

o:	$(ALL_O)

a:	$(ALL_A)

$(LUA_A): $(CORE_O) $(LIB_O)
	@echo "  AR    $@"
	@$(AR) $@ $(CORE_O) $(LIB_O) >> ../log/build.log 2>&1
	@$(RANLIB) $@ >> ../log/build.log 2>&1

$(LUA_T): $(LUA_O) $(LUA_A)
	@echo "  LINK  $@"
	@$(MKDIR) $(BIN_DIR)
	@$(CC) -o $@ $(MYLDFLAGS) $(LUA_O) $(LUA_A) $(LIBS) >> ../log/build.log 2>&1

$(LUAC_T): $(LUAC_O) $(LUA_A)
	@echo "  LINK  $@"
	@$(MKDIR) $(BIN_DIR)
	@$(CC) -o $@ $(MYLDFLAGS) $(LUAC_O) $(LUA_A) $(LIBS) >> ../log/build.log 2>&1

$(OBJ_DIR)/sqlite3.o: ../lib/sqlite/sqlite3.c ../lib/sqlite/sqlite3.h
	@echo "  CC    $@"
	@$(MKDIR) $(OBJ_DIR)
	@$(CC) $(CFLAGS) -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_RTREE -fPIC -c -o $@ $< >> ../log/build.log 2>&1

$(OBJ_DIR)/libluasqlite3.o: ../lib/sqlite/lsqlite3.c
	@echo "  CC    $@"
	@$(MKDIR) $(OBJ_DIR)
	@$(CC) $(CFLAGS) -I../lib/sqlite -I. -fPIC -c -o $@ $< >> ../log/build.log 2>&1

$(BIN_DIR)/sqlite3.so: $(OBJ_DIR)/libluasqlite3.o $(OBJ_DIR)/sqlite3.o
	@echo "  LINK  $@"
	@$(MKDIR) $(BIN_DIR)
	@$(CC) -shared -o $@ $^ -lpthread -ldl >> ../log/build.log 2>&1

$(OBJ_DIR)/bit.o: ../lib/bit/bit.c
	@echo "  CC    $@"
	@$(MKDIR) $(OBJ_DIR)
	@$(CC) $(CFLAGS) -I. -fPIC -c -o $@ $< >> ../log/build.log 2>&1

$(OBJ_DIR)/struct.o: ../lib/struct/struct.c
	@echo "  CC    $@"
	@$(MKDIR) $(OBJ_DIR)
	@$(CC) $(CFLAGS) -I. -fPIC -c -o $@ $< >> ../log/build.log 2>&1

$(OBJ_DIR)/%.o: %.c
	@echo "  CC    $@"
	@$(MKDIR) $(OBJ_DIR)
	@$(CC) $(CFLAGS) -I. -fPIC -c -o $@ $< >> ../log/build.log 2>&1

clean:
	$(RM) $(ALL_T) $(ALL_O)

depend:
	@$(CC) $(CFLAGS) -MM l*.c print.c

echo:
	@echo "PLAT = $(PLAT)"
	@echo "CC = $(CC)"
	@echo "CFLAGS = $(CFLAGS)"
	@echo "AR = $(AR)"
	@echo "RANLIB = $(RANLIB)"
	@echo "RM = $(RM)"
	@echo "MYCFLAGS = $(MYCFLAGS)"
	@echo "MYLDFLAGS = $(MYLDFLAGS)"
	@echo "MYLIBS = $(MYLIBS)"

# convenience targets for popular platforms

none:
	@echo "Please choose a platform:"
	@echo "   $(PLATS)"

aix:
	$(MAKE) all CC="xlc" CFLAGS="-O2 -DLUA_USE_POSIX -DLUA_USE_DLOPEN" MYLIBS="-ldl" MYLDFLAGS="-brtl -bexpall"

ansi:
	$(MAKE) all MYCFLAGS=-DLUA_ANSI

bsd:
	$(MAKE) all MYCFLAGS="-DLUA_USE_POSIX -DLUA_USE_DLOPEN" MYLIBS="-Wl,-E"

freebsd:
	$(MAKE) all MYCFLAGS="-DLUA_USE_LINUX" MYLIBS="-Wl,-E -lreadline"

generic:
	$(MAKE) all MYCFLAGS=

linux:
	$(MAKE) all MYCFLAGS=-DLUA_USE_LINUX MYLIBS="-Wl,-E -ldl -lreadline -lhistory -lncurses"
	$(MAKE) $(BIN_DIR)/sqlite3.so

macosx:
	$(MAKE) all MYCFLAGS=-DLUA_USE_LINUX MYLIBS="-lreadline"
# use this on Mac OS X 10.3-
#	$(MAKE) all MYCFLAGS=-DLUA_USE_MACOSX

mingw:
	$(MAKE) "LUA_A=lua51.dll" "LUA_T=luam.exe" \
	"AR=$(CC) -shared -o" "RANLIB=strip --strip-unneeded" \
	"MYCFLAGS=-DLUA_BUILD_AS_DLL" "MYLIBS=" "MYLDFLAGS=-s" luam.exe
	$(MAKE) "LUAC_T=luamc.exe" luamc.exe

posix:
	$(MAKE) all MYCFLAGS=-DLUA_USE_POSIX

solaris:
	$(MAKE) all MYCFLAGS="-DLUA_USE_POSIX -DLUA_USE_DLOPEN" MYLIBS="-ldl"

# list targets that do not create files (but not all makes understand .PHONY)
.PHONY: all $(PLATS) default o a clean depend echo none

# DO NOT DELETE

$(OBJ_DIR)/lapi.o: lapi.c lua.h luaconf.h lapi.h lobject.h llimits.h ldebug.h \
  lstate.h ltm.h lzio.h lmem.h ldo.h lfunc.h lgc.h lstring.h ltable.h \
  lundump.h lvm.h
$(OBJ_DIR)/lauxlib.o: lauxlib.c lua.h luaconf.h lauxlib.h
$(OBJ_DIR)/lbaselib.o: lbaselib.c lua.h luaconf.h lauxlib.h lualib.h
$(OBJ_DIR)/lcode.o: lcode.c lua.h luaconf.h lcode.h llex.h lobject.h llimits.h \
  lzio.h lmem.h lopcodes.h lparser.h ldebug.h lstate.h ltm.h ldo.h lgc.h \
  ltable.h
$(OBJ_DIR)/ldblib.o: ldblib.c lua.h luaconf.h lauxlib.h lualib.h
$(OBJ_DIR)/ldebug.o: ldebug.c lua.h luaconf.h lapi.h lobject.h llimits.h lcode.h \
  llex.h lzio.h lmem.h lopcodes.h lparser.h ldebug.h lstate.h ltm.h ldo.h \
  lfunc.h lstring.h lgc.h ltable.h lvm.h
$(OBJ_DIR)/ldo.o: ldo.c lua.h luaconf.h ldebug.h lstate.h lobject.h llimits.h ltm.h \
  lzio.h lmem.h ldo.h lfunc.h lgc.h lopcodes.h lparser.h lstring.h \
  ltable.h lundump.h lvm.h
$(OBJ_DIR)/ldump.o: ldump.c lua.h luaconf.h lobject.h llimits.h lstate.h ltm.h \
  lzio.h lmem.h lundump.h
$(OBJ_DIR)/lfunc.o: lfunc.c lua.h luaconf.h lfunc.h lobject.h llimits.h lgc.h lmem.h \
  lstate.h ltm.h lzio.h
$(OBJ_DIR)/lgc.o: lgc.c lua.h luaconf.h ldebug.h lstate.h lobject.h llimits.h ltm.h \
  lzio.h lmem.h ldo.h lfunc.h lgc.h lstring.h ltable.h
$(OBJ_DIR)/linit.o: linit.c lua.h luaconf.h lualib.h lauxlib.h
$(OBJ_DIR)/liolib.o: liolib.c lua.h luaconf.h lauxlib.h lualib.h
$(OBJ_DIR)/llex.o: llex.c lua.h luaconf.h ldo.h lobject.h llimits.h lstate.h ltm.h \
  lzio.h lmem.h llex.h lparser.h lstring.h lgc.h ltable.h
$(OBJ_DIR)/lmathlib.o: lmathlib.c lua.h luaconf.h lauxlib.h lualib.h
$(OBJ_DIR)/lmem.o: lmem.c lua.h luaconf.h ldebug.h lstate.h lobject.h llimits.h \
  ltm.h lzio.h lmem.h ldo.h
$(OBJ_DIR)/loadlib.o: loadlib.c lua.h luaconf.h lauxlib.h lualib.h
$(OBJ_DIR)/lobject.o: lobject.c lua.h luaconf.h ldo.h lobject.h llimits.h lstate.h \
  ltm.h lzio.h lmem.h lstring.h lgc.h lvm.h
$(OBJ_DIR)/lopcodes.o: lopcodes.c lopcodes.h llimits.h lua.h luaconf.h
$(OBJ_DIR)/loslib.o: loslib.c lua.h luaconf.h lauxlib.h lualib.h
$(OBJ_DIR)/lparser.o: lparser.c lua.h luaconf.h lcode.h llex.h lobject.h llimits.h \
  lzio.h lmem.h lopcodes.h lparser.h ldebug.h lstate.h ltm.h ldo.h \
  lfunc.h lstring.h lgc.h ltable.h
$(OBJ_DIR)/lstate.o: lstate.c lua.h luaconf.h ldebug.h lstate.h lobject.h llimits.h \
  ltm.h lzio.h lmem.h ldo.h lfunc.h lgc.h llex.h lstring.h ltable.h
$(OBJ_DIR)/lstring.o: lstring.c lua.h luaconf.h lmem.h llimits.h lobject.h lstate.h \
  ltm.h lzio.h lstring.h lgc.h
$(OBJ_DIR)/lstrlib.o: lstrlib.c lua.h luaconf.h lauxlib.h lualib.h
$(OBJ_DIR)/ltable.o: ltable.c lua.h luaconf.h ldebug.h lstate.h lobject.h llimits.h \
  ltm.h lzio.h lmem.h ldo.h lgc.h ltable.h
$(OBJ_DIR)/ltablib.o: ltablib.c lua.h luaconf.h lauxlib.h lualib.h
$(OBJ_DIR)/ltm.o: ltm.c lua.h luaconf.h lobject.h llimits.h lstate.h ltm.h lzio.h \
  lmem.h lstring.h lgc.h ltable.h
$(OBJ_DIR)/lua.o: lua.c lua.h luaconf.h lauxlib.h lualib.h
$(OBJ_DIR)/luac.o: luac.c lua.h luaconf.h lauxlib.h ldo.h lobject.h llimits.h \
  lstate.h ltm.h lzio.h lmem.h lfunc.h lopcodes.h lstring.h lgc.h \
  lundump.h
$(OBJ_DIR)/lundump.o: lundump.c lua.h luaconf.h ldebug.h lstate.h lobject.h \
  llimits.h ltm.h lzio.h lmem.h ldo.h lfunc.h lstring.h lgc.h lundump.h
$(OBJ_DIR)/lvm.o: lvm.c lua.h luaconf.h ldebug.h lstate.h lobject.h llimits.h ltm.h \
  lzio.h lmem.h ldo.h lfunc.h lgc.h lopcodes.h lstring.h ltable.h lvm.h
$(OBJ_DIR)/lzio.o: lzio.c lua.h luaconf.h llimits.h lmem.h lstate.h lobject.h ltm.h \
  lzio.h
$(OBJ_DIR)/print.o: print.c ldebug.h lstate.h lua.h luaconf.h lobject.h llimits.h \
  ltm.h lzio.h lmem.h lopcodes.h lundump.h

# (end of Makefile)
