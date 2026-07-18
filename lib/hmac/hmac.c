/*
** hmac: a thin Lua binding over OpenSSL's libcrypto HMAC-SHA256
** implementation -- not a vendored/hand-rolled HMAC or SHA256. Chosen
** over vendoring a pure-Lua SHA/HMAC implementation for the same
** reason as lib/bcrypt/bcrypt.c: prefer a thin wrapper around the
** platform's own battle-tested crypto over introducing an unvetted
** third-party implementation. Verified against the standard
** HMAC-SHA256 test vector (key="key",
** msg="The quick brown fox jumps over the lazy dog" ->
** f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd)
** before use. Requires linking against -lcrypto.
*/

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <openssl/hmac.h>
#include <openssl/evp.h>
#include <string.h>

#if LUA_VERSION_NUM >= 502
#define new_lib(L, l) (luaL_newlib(L, l))
#else
#define new_lib(L, l) (lua_newtable(L), luaL_register(L, NULL, l))
#endif

static const char hex_chars[] = "0123456789abcdef";

/* hmac.sha256(key, message) -> hex_digest_string | nil, err_string */
static int l_hmac_sha256(lua_State *L) {
    size_t key_len, msg_len;
    const char *key = luaL_checklstring(L, 1, &key_len);
    const char *msg = luaL_checklstring(L, 2, &msg_len);

    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int digest_len = 0;

    if (HMAC(EVP_sha256(), key, (int)key_len,
             (const unsigned char *)msg, msg_len,
             digest, &digest_len) == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "HMAC failed");
        return 2;
    }

    char hex[EVP_MAX_MD_SIZE * 2 + 1];
    unsigned int i;
    for (i = 0; i < digest_len; i++) {
        hex[i * 2] = hex_chars[(digest[i] >> 4) & 0xf];
        hex[i * 2 + 1] = hex_chars[digest[i] & 0xf];
    }
    hex[digest_len * 2] = '\0';

    lua_pushstring(L, hex);
    return 1;
}

static const struct luaL_Reg hmaclib[] = {
    {"sha256", l_hmac_sha256},
    {NULL, NULL}
};

LUALIB_API int luaopen_hmac(lua_State *L);

LUALIB_API int luaopen_hmac(lua_State *L) {
    new_lib(L, hmaclib);
    return 1;
}
