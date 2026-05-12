CMOD=ssl.so
LMOD=ssl.lua

OBJS= \
 options.o \
 x509.o    \
 context.o \
 ssl.o     \
 config.o  \
 ec.o

LIBS=-lssl -lcrypto -lluasocket

WARN=-Wall -pedantic
INCDIR=-I../../../src -I.

CFLAGS += -O2 -fPIC $(WARN) $(INCDIR) $(DEFS)

INSTALL  = install
CC      ?= cc
CCLD      ?= $(MYENV) $(CC)
LDFLAGS += -O -fPIC -shared $(LIBDIR)

.PHONY: all clean install none linux bsd macosx luasocket

all: $(CMOD)

install: $(CMOD) $(LMOD)
	$(INSTALL) -d $(DESTDIR)$(LUAPATH)/ssl $(DESTDIR)$(LUACPATH)
	$(INSTALL) $(CMOD) $(DESTDIR)$(LUACPATH)
	$(INSTALL) -m644 $(LMOD) $(DESTDIR)$(LUAPATH)
	$(INSTALL) -m644 https.lua $(DESTDIR)$(LUAPATH)/ssl

linux:
	@$(MAKE) luasocket
	@$(MAKE) $(CMOD)

bsd:
	@$(MAKE) luasocket
	@$(MAKE) $(CMOD)

macosx:
	@$(MAKE) luasocket
	@$(MAKE) $(CMOD) MYLDFLAGS="-bundle -undefined dynamic_lookup $(LIBDIR)"

luasocket:
	@cd luasocket && $(MAKE)

$(CMOD): $(EXTRA) $(OBJS)
	$(CCLD) $(LDFLAGS) -o $@ $(OBJS) $(LIBS)

clean:
	cd luasocket && $(MAKE) clean
	rm -f $(OBJS) $(CMOD)

options.o: options.h options.c
ec.o: ec.c ec.h
x509.o: x509.c x509.h compat.h
context.o: context.c context.h ec.h compat.h options.h
ssl.o: ssl.c ssl.h context.h x509.h compat.h
config.o: config.c ec.h options.h compat.h
