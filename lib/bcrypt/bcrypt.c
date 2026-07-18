/*
** bcrypt: a thin Lua binding over glibc/libxcrypt's own bcrypt support
** (crypt_gensalt/crypt_r with a "$2b$" prefix) -- not a vendored
** bcrypt implementation. Verified directly against this system's
** libc (glibc 2.39/libxcrypt) with standalone C probes before writing
** this file: crypt_gensalt("$2b$", cost, NULL, 0) produces a real,
** correctly-formatted bcrypt salt (reading its own randomness from
** /dev/urandom internally, nothing hand-rolled here), and crypt_r()
** round-trips a real hash/verify correctly. Uses the platform's own
** crypt_r (thread- and reentrant-safe) rather than plain crypt()
** specifically because plain crypt() returns a pointer to a static
** buffer that a second call (e.g. a verify right after a hash)
** overwrites -- confirmed as a real, reproducible bug while probing,
** not a hypothetical one. Requires linking against -lcrypt.
*/

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <crypt.h>
#include <string.h>
#include <stdlib.h>

#if LUA_VERSION_NUM >= 502
#define new_lib(L, l) (luaL_newlib(L, l))
#else
#define new_lib(L, l) (lua_newtable(L), luaL_register(L, NULL, l))
#endif

/* Constant-time comparison -- a hash/verify check must not leak how
** many leading bytes matched via early-exit timing, the way plain
** strcmp() would. */
static int constant_time_equal(const char *a, const char *b) {
    size_t la = strlen(a);
    size_t lb = strlen(b);
    if (la != lb) return 0;
    unsigned char diff = 0;
    size_t i;
    for (i = 0; i < la; i++) {
        diff |= (unsigned char)a[i] ^ (unsigned char)b[i];
    }
    return diff == 0;
}

/* bcrypt.hash(password, cost) -> hash_string | nil, err_string */
static int l_bcrypt_hash(lua_State *L) {
    const char *password = luaL_checkstring(L, 1);
    lua_Integer cost = luaL_optinteger(L, 2, 12);
    if (cost < 4 || cost > 31) {
        lua_pushnil(L);
        lua_pushstring(L, "cost must be between 4 and 31");
        return 2;
    }

    char *salt = crypt_gensalt("$2b$", (unsigned long)cost, NULL, 0);
    if (salt == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "crypt_gensalt failed");
        return 2;
    }

    struct crypt_data data;
    memset(&data, 0, sizeof(data));
    char *result = crypt_r(password, salt, &data);
    if (result == NULL || result[0] == '*') {
        lua_pushnil(L);
        lua_pushstring(L, "crypt_r failed");
        return 2;
    }

    lua_pushstring(L, result);
    return 1;
}

/* bcrypt.verify(password, hash) -> boolean */
static int l_bcrypt_verify(lua_State *L) {
    const char *password = luaL_checkstring(L, 1);
    const char *hash = luaL_checkstring(L, 2);

    struct crypt_data data;
    memset(&data, 0, sizeof(data));
    char *result = crypt_r(password, hash, &data);
    if (result == NULL || result[0] == '*') {
        lua_pushboolean(L, 0);
        return 1;
    }

    lua_pushboolean(L, constant_time_equal(result, hash));
    return 1;
}

static const struct luaL_Reg bcryptlib[] = {
    {"hash", l_bcrypt_hash},
    {"verify", l_bcrypt_verify},
    {NULL, NULL}
};

LUALIB_API int luaopen_bcrypt(lua_State *L);

LUALIB_API int luaopen_bcrypt(lua_State *L) {
    new_lib(L, bcryptlib);
    return 1;
}
