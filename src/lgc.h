/*
** Interface to Garbage Collector (Restored for Odin migration)
*/

#ifndef lgc_h
#define lgc_h

#include "llimits.h"
#include "lobject.h"

/*
** Bit manipulation macros (from llimits.h)
*/
#define bitmask(b) (1 << (b))
#define bit2mask(b1, b2) (bitmask(b1) | bitmask(b2))
#define l_setbit(x, b) ((x) |= bitmask(b))
#define resetbit(x, b) ((x) &= cast(lu_byte, ~bitmask(b)))
#define testbit(x, b) ((x) & bitmask(b))
#define test2bits(x, b1, b2) ((x) & (bitmask(b1) | bitmask(b2)))

/*
** Possible states of the Garbage Collector
*/
#define GCSpropagate 0
#define GCSsweepstring 1
#define GCSsweep 2
#define GCSfinalize 3

/*
** some predefined values
*/
#define GCSTEPSIZE 1024
#define GCSWEEPMAX 40
#define GCSWEEPCOST 10
#define GCFINALIZECOST 100

/*
** GC Bits
*/
#define WHITE0BIT 0
#define WHITE1BIT 1
#define BLACKBIT 2
#define FINALIZEDBIT 3
#define KEYWEAKBIT 3
#define VALUEWEAKBIT 4
#define FIXEDBIT 5
#define SFIXEDBIT 6
#define WHITEBITS bit2mask(WHITE0BIT, WHITE1BIT)

#define iswhite(x) test2bits((x)->gch.marked, WHITE0BIT, WHITE1BIT)
#define isblack(x) testbit((x)->gch.marked, BLACKBIT)
#define isgray(x) (!isblack(x) && !iswhite(x))

#define otherwhite(g) (g->currentwhite ^ WHITEBITS)
#define isdead(g, v) ((v)->gch.marked & otherwhite(g) & WHITEBITS)

#define changewhite(x) ((x)->gch.marked ^= WHITEBITS)
#define gray2black(x) l_setbit((x)->gch.marked, BLACKBIT)

#define valiswhite(x) (iscollectable(x) && iswhite(gcvalue(x)))

#define luaC_white(g) cast(lu_byte, (g)->currentwhite &WHITEBITS)

/*
** macro 'luaC_checkGC'
*/

/*
** macro 'luaC_checkGC'
*/
#define luaC_checkGC(L)                                                        \
  {                                                                            \
    condhardstacktests(luaD_reallocstack(L, L->stacksize - EXTRA_STACK - 1));  \
    if (G(L)->totalbytes >= G(L)->GCthreshold)                                 \
      luaC_step(L);                                                            \
  }

/*
** macro 'luaC_barrier'
*/
#define luaC_barrier(L, p, v)                                                  \
  {                                                                            \
    if (valiswhite(v) && isblack(obj2gco(p)))                                  \
      luaC_barrierf(L, obj2gco(p), gcvalue(v));                                \
  }

#define luaC_barriert(L, t, v)                                                 \
  {                                                                            \
    if (valiswhite(v) && isblack(obj2gco(t)))                                  \
      luaC_barrierback(L, t);                                                  \
  }

#define luaC_objbarrier(L, p, o)                                               \
  {                                                                            \
    if (iswhite(obj2gco(o)) && isblack(obj2gco(p)))                            \
      luaC_barrierf(L, obj2gco(p), obj2gco(o));                                \
  }

#define luaC_objbarriert(L, h, o)                                              \
  {                                                                            \
    if (iswhite(obj2gco(o)) && isblack(obj2gco(h)))                            \
      luaC_barrierback(L, h);                                                  \
  }

#define luaC_barrierback(L, t) luaC_barrierback(L, t) // calls exported func

/*
** Exported functions (from Odin)
*/
LUAI_FUNC size_t luaC_separateudata(lua_State *L, int all);
LUAI_FUNC void luaC_callGCTM(lua_State *L);
LUAI_FUNC void luaC_freeall(lua_State *L);
LUAI_FUNC void luaC_step(lua_State *L);
LUAI_FUNC void luaC_fullgc(lua_State *L);
LUAI_FUNC void luaC_link(lua_State *L, GCObject *o, lu_byte tt);
LUAI_FUNC void luaC_linkupval(lua_State *L, UpVal *uv);
LUAI_FUNC void luaC_barrierf(lua_State *L, GCObject *o, GCObject *v);
LUAI_FUNC void luaC_barrierback(lua_State *L, Table *t);

#endif
