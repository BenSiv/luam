#define LUA_CORE
#include "lobject.h"
#include "lstate.h"
#include "lua.h"
#include <stdarg.h>

LUA_API const char *lua_pushvfstring(lua_State *L, const char *fmt,
                                     va_list argp) {
  const char *ret;
  ret = luaO_pushvfstring(L, fmt, argp);
  return ret;
}

LUA_API const char *lua_pushfstring(lua_State *L, const char *fmt, ...) {
  const char *ret;
  va_list argp;
  va_start(argp, fmt);
  ret = lua_pushvfstring(L, fmt, argp);
  va_end(argp);
  return ret;
}
