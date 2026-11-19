/*
** vec: dense little-endian float32 vector operations for embedding search,
** cosine similarity, L2 normalization, and SQL blob packing without Lua
** table/number allocation churn.
**
** Functions:
**   vec.dot_packed(bytes_a, bytes_b)    -> number
**   vec.cosine_packed(bytes_a, bytes_b) -> number
**   vec.pack(tbl [, dims])              -> L2-normalized LE float32 bytes | nil
**   vec.pack_raw(tbl [, dims])          -> raw LE float32 bytes | nil
**   vec.unpack(bytes)                   -> array table | nil
**   vec.dot(tbl_a, tbl_b)               -> number
**   vec.cosine(tbl_a, tbl_b)            -> number
**   vec.unit(tbl [, dims])              -> L2-normalized array table | nil
**   vec.hex_literal(bytes)              -> "X'...'" SQL hex literal
*/

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>

static float read_f32_le(const unsigned char *p) {
  uint32_t u = (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
               ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
  float f;
  memcpy(&f, &u, sizeof(float));
  return f;
}

static void write_f32_le(unsigned char *p, float f) {
  uint32_t u;
  memcpy(&u, &f, sizeof(uint32_t));
  p[0] = (unsigned char)(u & 0xff);
  p[1] = (unsigned char)((u >> 8) & 0xff);
  p[2] = (unsigned char)((u >> 16) & 0xff);
  p[3] = (unsigned char)((u >> 24) & 0xff);
}

static int l_dot_packed(lua_State *L) {
  if (lua_isnoneornil(L, 1) || lua_isnoneornil(L, 2)) {
    lua_pushnumber(L, 0.0);
    return 1;
  }
  size_t len_a = 0, len_b = 0;
  const unsigned char *a =
      (const unsigned char *)luaL_checklstring(L, 1, &len_a);
  const unsigned char *b =
      (const unsigned char *)luaL_checklstring(L, 2, &len_b);
  if (len_a == 0 || len_a != len_b || (len_a & 3) != 0) {
    lua_pushnumber(L, 0.0);
    return 1;
  }
  size_t n = len_a >> 2;
  double sum = 0.0;
  size_t i;
  for (i = 0; i < n; i++) {
    double va = (double)read_f32_le(a + (i << 2));
    double vb = (double)read_f32_le(b + (i << 2));
    sum += va * vb;
  }
  lua_pushnumber(L, sum);
  return 1;
}

static int l_cosine_packed(lua_State *L) {
  if (lua_isnoneornil(L, 1) || lua_isnoneornil(L, 2)) {
    lua_pushnumber(L, 0.0);
    return 1;
  }
  size_t len_a = 0, len_b = 0;
  const unsigned char *a =
      (const unsigned char *)luaL_checklstring(L, 1, &len_a);
  const unsigned char *b =
      (const unsigned char *)luaL_checklstring(L, 2, &len_b);
  if (len_a == 0 || len_a != len_b || (len_a & 3) != 0) {
    lua_pushnumber(L, 0.0);
    return 1;
  }
  size_t n = len_a >> 2;
  double dot = 0.0, norm_a = 0.0, norm_b = 0.0;
  size_t i;
  for (i = 0; i < n; i++) {
    double va = (double)read_f32_le(a + (i << 2));
    double vb = (double)read_f32_le(b + (i << 2));
    dot += va * vb;
    norm_a += va * va;
    norm_b += vb * vb;
  }
  if (norm_a <= 0.0 || norm_b <= 0.0) {
    lua_pushnumber(L, 0.0);
    return 1;
  }
  lua_pushnumber(L, dot / (sqrt(norm_a) * sqrt(norm_b)));
  return 1;
}

static int pack_impl(lua_State *L, int normalize) {
  if (lua_isnoneornil(L, 1)) {
    lua_pushnil(L);
    return 1;
  }
  luaL_checktype(L, 1, LUA_TTABLE);
  size_t n = lua_objlen(L, 1);
  if (!lua_isnoneornil(L, 2)) {
    int dims = luaL_checkint(L, 2);
    if (dims >= 0 && (size_t)dims < n) {
      n = (size_t)dims;
    }
  }
  if (n == 0) {
    lua_pushnil(L);
    return 1;
  }

  double *vals = (double *)malloc(n * sizeof(double));
  if (vals == NULL) {
    return luaL_error(L, "vec.pack: out of memory");
  }
  double norm_sq = 0.0;
  size_t i;
  for (i = 0; i < n; i++) {
    lua_rawgeti(L, 1, (int)(i + 1));
    double v = lua_tonumber(L, -1);
    lua_pop(L, 1);
    vals[i] = v;
    norm_sq += v * v;
  }
  if (normalize && norm_sq == 0.0) {
    free(vals);
    lua_pushnil(L);
    return 1;
  }
  double scale = normalize ? (1.0 / sqrt(norm_sq)) : 1.0;

  unsigned char *out = (unsigned char *)malloc(n * 4);
  if (out == NULL) {
    free(vals);
    return luaL_error(L, "vec.pack: out of memory");
  }
  for (i = 0; i < n; i++) {
    write_f32_le(out + (i << 2), (float)(vals[i] * scale));
  }
  free(vals);
  lua_pushlstring(L, (const char *)out, n * 4);
  free(out);
  return 1;
}

static int l_pack(lua_State *L) { return pack_impl(L, 1); }
static int l_pack_raw(lua_State *L) { return pack_impl(L, 0); }

static int l_unpack(lua_State *L) {
  if (lua_isnoneornil(L, 1)) {
    lua_pushnil(L);
    return 1;
  }
  size_t len = 0;
  const unsigned char *bytes =
      (const unsigned char *)luaL_checklstring(L, 1, &len);
  if (len == 0 || (len & 3) != 0) {
    lua_pushnil(L);
    return 1;
  }
  size_t n = len >> 2;
  lua_createtable(L, (int)n, 0);
  size_t i;
  for (i = 0; i < n; i++) {
    lua_pushnumber(L, (lua_Number)read_f32_le(bytes + (i << 2)));
    lua_rawseti(L, -2, (int)(i + 1));
  }
  return 1;
}

static int l_dot(lua_State *L) {
  if (!lua_istable(L, 1) || !lua_istable(L, 2)) {
    lua_pushnumber(L, 0.0);
    return 1;
  }
  size_t na = lua_objlen(L, 1);
  size_t nb = lua_objlen(L, 2);
  if (na == 0 || na != nb) {
    lua_pushnumber(L, 0.0);
    return 1;
  }
  double sum = 0.0;
  size_t i;
  for (i = 1; i <= na; i++) {
    lua_rawgeti(L, 1, (int)i);
    double va = lua_tonumber(L, -1);
    lua_rawgeti(L, 2, (int)i);
    double vb = lua_tonumber(L, -1);
    lua_pop(L, 2);
    sum += va * vb;
  }
  lua_pushnumber(L, sum);
  return 1;
}

static int l_cosine(lua_State *L) {
  if (!lua_istable(L, 1) || !lua_istable(L, 2)) {
    lua_pushnumber(L, 0.0);
    return 1;
  }
  size_t na = lua_objlen(L, 1);
  size_t nb = lua_objlen(L, 2);
  if (na == 0 || na != nb) {
    lua_pushnumber(L, 0.0);
    return 1;
  }
  double dot = 0.0, norm_a = 0.0, norm_b = 0.0;
  size_t i;
  for (i = 1; i <= na; i++) {
    lua_rawgeti(L, 1, (int)i);
    double va = lua_tonumber(L, -1);
    lua_rawgeti(L, 2, (int)i);
    double vb = lua_tonumber(L, -1);
    lua_pop(L, 2);
    dot += va * vb;
    norm_a += va * va;
    norm_b += vb * vb;
  }
  if (norm_a <= 0.0 || norm_b <= 0.0) {
    lua_pushnumber(L, 0.0);
    return 1;
  }
  lua_pushnumber(L, dot / (sqrt(norm_a) * sqrt(norm_b)));
  return 1;
}

static int l_unit(lua_State *L) {
  if (lua_isnoneornil(L, 1)) {
    lua_pushnil(L);
    return 1;
  }
  luaL_checktype(L, 1, LUA_TTABLE);
  size_t n = lua_objlen(L, 1);
  if (!lua_isnoneornil(L, 2)) {
    int dims = luaL_checkint(L, 2);
    if (dims >= 0 && (size_t)dims < n) {
      n = (size_t)dims;
    }
  }
  if (n == 0) {
    lua_pushnil(L);
    return 1;
  }
  double *vals = (double *)malloc(n * sizeof(double));
  if (vals == NULL) {
    return luaL_error(L, "vec.unit: out of memory");
  }
  double norm_sq = 0.0;
  size_t i;
  for (i = 0; i < n; i++) {
    lua_rawgeti(L, 1, (int)(i + 1));
    double v = lua_tonumber(L, -1);
    lua_pop(L, 1);
    vals[i] = v;
    norm_sq += v * v;
  }
  if (norm_sq == 0.0) {
    free(vals);
    lua_pushnil(L);
    return 1;
  }
  double inv = 1.0 / sqrt(norm_sq);
  lua_createtable(L, (int)n, 0);
  for (i = 0; i < n; i++) {
    lua_pushnumber(L, vals[i] * inv);
    lua_rawseti(L, -2, (int)(i + 1));
  }
  free(vals);
  return 1;
}

static int l_hex_literal(lua_State *L) {
  static const char hex[] = "0123456789abcdef";
  size_t len = 0;
  const unsigned char *bytes =
      (const unsigned char *)luaL_checklstring(L, 1, &len);
  size_t out_len = 2 + len * 2 + 1;
  char *out = (char *)malloc(out_len);
  if (out == NULL) {
    return luaL_error(L, "vec.hex_literal: out of memory");
  }
  out[0] = 'X';
  out[1] = '\'';
  size_t i;
  for (i = 0; i < len; i++) {
    out[2 + i * 2] = hex[(bytes[i] >> 4) & 0xf];
    out[2 + i * 2 + 1] = hex[bytes[i] & 0xf];
  }
  out[2 + len * 2] = '\'';
  lua_pushlstring(L, out, out_len);
  free(out);
  return 1;
}

static const struct luaL_Reg veclib[] = {
    {"dot_packed", l_dot_packed},
    {"cosine_packed", l_cosine_packed},
    {"pack", l_pack},
    {"pack_raw", l_pack_raw},
    {"unpack", l_unpack},
    {"dot", l_dot},
    {"cosine", l_cosine},
    {"unit", l_unit},
    {"hex_literal", l_hex_literal},
    {NULL, NULL},
};

LUALIB_API int luaopen_vec(lua_State *L) {
  lua_newtable(L);
  luaL_register(L, NULL, veclib);
  return 1;
}
