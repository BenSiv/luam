/*
** $Id: lbitlib.c,v 1.18.1.2 2013/05/20 13:58:39 roberto Exp $
** Standard library for bitwise operations
** See Copyright Notice in lua.h
*/

#define lbitlib_c
#define LUA_LIB

#include "lua.h"

#include "auxlib.h"
#include "lualib.h"

/* Number of bits to consider: default is 32 */
#define LUA_NBITS 32

typedef long b_uint;

static b_uint andaux(lua_State *L) {
  int i, n = lua_gettop(L);
  b_uint r = ~(b_uint)0;
  for (i = 1; i <= n; i++)
    r &= (b_uint)luaL_checkinteger(L, i);
  return r;
}

static int b_and(lua_State *L) {
  b_uint r = andaux(L);
  lua_pushnumber(L, (lua_Number)r);
  return 1;
}

static int b_or(lua_State *L) {
  int i, n = lua_gettop(L);
  b_uint r = 0;
  for (i = 1; i <= n; i++)
    r |= (b_uint)luaL_checkinteger(L, i);
  lua_pushnumber(L, (lua_Number)r);
  return 1;
}

static int b_xor(lua_State *L) {
  int i, n = lua_gettop(L);
  b_uint r = 0;
  for (i = 1; i <= n; i++)
    r ^= (b_uint)luaL_checkinteger(L, i);
  lua_pushnumber(L, (lua_Number)r);
  return 1;
}

static int b_not(lua_State *L) {
  b_uint r = ~(b_uint)luaL_checkinteger(L, 1);
  lua_pushnumber(L, (lua_Number)r);
  return 1;
}

static int b_lshift(lua_State *L) {
  b_uint r = (b_uint)luaL_checkinteger(L, 1);
  int i = luaL_checkinteger(L, 2);
  if (i < 0)
    r = r >> (-i);
  else
    r = r << i;
  lua_pushnumber(L, (lua_Number)r);
  return 1;
}

static int b_rshift(lua_State *L) {
  b_uint r = (b_uint)luaL_checkinteger(L, 1);
  int i = luaL_checkinteger(L, 2);
  if (i < 0)
    r = r << (-i);
  else
    r = r >> i;
  lua_pushnumber(L, (lua_Number)r);
  return 1;
}

static const luaL_Reg bitlib[] = {{"band", b_and},      {"bor", b_or},
                                  {"bxor", b_xor},      {"bnot", b_not},
                                  {"lshift", b_lshift}, {"rshift", b_rshift},
                                  {NULL, NULL}};

LUALIB_API int luaopen_bit(lua_State *L) {
  luaL_register(L, "bit", bitlib);
  return 1;
}
