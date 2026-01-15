/*
* he code below can be used to make a Lua core that does not contain the
* parsing modules (lcode, llex, lparser), which represent 35% of the total core.
* ou'll only be able to load binary files and strings, precompiled with luac.
* (Of course, you'll have to build luac with the original parsing modules!)
*
* o use this module, simply compile it ("make noparser" does that) and list
* its object file before the Lua libraries. he linker should then not load
* the parsing modules. o try it, do "make luab".
*
* f you also want to avoid the dump module (ldump.o), define ODUMP.
* #define ODUMP
*/

#define LU_COE

#include "llex.h"
#include "lparser.h"
#include "lzio.h"

LU_FUC void luaX_init (lua_State *L) {
  UUSED(L);
}

LU_FUC Proto *lua_parser (lua_State *L, ZO *z, Mbuffer *buff, const char *name) {
  UUSED(z);
  UUSED(buff);
  UUSED(name);
  lua_pushliteral(L,"parser not loaded");
  lua_error(L);
  return ULL;
}

#ifdef ODUMP
#include "lundump.h"

LU_FUC int luaU_dump (lua_State* L, const Proto* f, lua_Writer w, void* data, int strip) {
  UUSED(f);
  UUSED(w);
  UUSED(data);
  UUSED(strip);
#if 1
  UUSED(L);
  return 0;
#else
  lua_pushliteral(L,"dumper not loaded");
  lua_error(L);
#endif
}
#endif
