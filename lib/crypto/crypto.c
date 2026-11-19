/*
** crypto: thin Luam binding over OpenSSL libcrypto (SHA-256, HMAC-SHA256,
** and CSPRNG random bytes/hex). Requires linking against -lcrypto.
**
** Functions:
**   crypto.sha256(str)           -> 64-char hex digest
**   crypto.sha256_file(path)     -> 64-char hex digest | nil, err
**   crypto.hmac_sha256(key, msg) -> 64-char hex digest
**   crypto.random_bytes(n)       -> n raw random bytes
**   crypto.random_hex(n_bytes)   -> 2*n_bytes lowercase hex string
*/

#include <errno.h>
#include <stdio.h>
#include <string.h>

#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/rand.h>

static const char hex_chars[] = "0123456789abcdef";

static void bytes_to_hex(const unsigned char *in, size_t len, char *out) {
  size_t i;
  for (i = 0; i < len; i++) {
    out[i * 2] = hex_chars[(in[i] >> 4) & 0xf];
    out[i * 2 + 1] = hex_chars[in[i] & 0xf];
  }
}

static int l_sha256(lua_State *L) {
  size_t msg_len = 0;
  const char *msg = luaL_checklstring(L, 1, &msg_len);
  unsigned char digest[EVP_MAX_MD_SIZE];
  unsigned int digest_len = 0;
  char hex[EVP_MAX_MD_SIZE * 2];

  if (!EVP_Digest(msg, msg_len, digest, &digest_len, EVP_sha256(), NULL)) {
    return luaL_error(L, "EVP_Digest(SHA256) failed");
  }
  bytes_to_hex(digest, digest_len, hex);
  lua_pushlstring(L, hex, digest_len * 2);
  return 1;
}

static int l_sha256_file(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
  FILE *fp = fopen(path, "rb");
  if (fp == NULL) {
    int en = errno;
    lua_pushnil(L);
    lua_pushfstring(L, "%s: %s", path, strerror(en));
    return 2;
  }

  EVP_MD_CTX *ctx = EVP_MD_CTX_new();
  if (ctx == NULL) {
    fclose(fp);
    return luaL_error(L, "EVP_MD_CTX_new failed");
  }
  if (!EVP_DigestInit_ex(ctx, EVP_sha256(), NULL)) {
    EVP_MD_CTX_free(ctx);
    fclose(fp);
    return luaL_error(L, "EVP_DigestInit_ex failed");
  }

  unsigned char buf[8192];
  size_t nread;
  while ((nread = fread(buf, 1, sizeof(buf), fp)) > 0) {
    if (!EVP_DigestUpdate(ctx, buf, nread)) {
      EVP_MD_CTX_free(ctx);
      fclose(fp);
      return luaL_error(L, "EVP_DigestUpdate failed");
    }
  }
  if (ferror(fp)) {
    int en = errno;
    EVP_MD_CTX_free(ctx);
    fclose(fp);
    lua_pushnil(L);
    lua_pushfstring(L, "%s: %s", path, strerror(en));
    return 2;
  }
  fclose(fp);

  unsigned char digest[EVP_MAX_MD_SIZE];
  unsigned int digest_len = 0;
  if (!EVP_DigestFinal_ex(ctx, digest, &digest_len)) {
    EVP_MD_CTX_free(ctx);
    return luaL_error(L, "EVP_DigestFinal_ex failed");
  }
  EVP_MD_CTX_free(ctx);

  char hex[EVP_MAX_MD_SIZE * 2];
  bytes_to_hex(digest, digest_len, hex);
  lua_pushlstring(L, hex, digest_len * 2);
  return 1;
}

static int l_hmac_sha256(lua_State *L) {
  size_t key_len = 0, msg_len = 0;
  const char *key = luaL_checklstring(L, 1, &key_len);
  const char *msg = luaL_checklstring(L, 2, &msg_len);
  unsigned char digest[EVP_MAX_MD_SIZE];
  unsigned int digest_len = 0;
  char hex[EVP_MAX_MD_SIZE * 2];

  if (HMAC(EVP_sha256(), key, (int)key_len, (const unsigned char *)msg, msg_len,
           digest, &digest_len) == NULL) {
    return luaL_error(L, "HMAC-SHA256 failed");
  }
  bytes_to_hex(digest, digest_len, hex);
  lua_pushlstring(L, hex, digest_len * 2);
  return 1;
}

static int l_random_bytes(lua_State *L) {
  int n = luaL_checkint(L, 1);
  luaL_argcheck(L, n >= 0 && n <= 1048576, 1, "byte count out of range");
  if (n == 0) {
    lua_pushliteral(L, "");
    return 1;
  }
  unsigned char stack_buf[256];
  unsigned char *buf = stack_buf;
  if (n > (int)sizeof(stack_buf)) {
    buf = (unsigned char *)lua_newuserdata(L, (size_t)n);
  }
  if (RAND_bytes(buf, n) != 1) {
    return luaL_error(L, "RAND_bytes failed");
  }
  lua_pushlstring(L, (const char *)buf, (size_t)n);
  return 1;
}

static int l_random_hex(lua_State *L) {
  int n = luaL_checkint(L, 1);
  luaL_argcheck(L, n >= 0 && n <= 524288, 1, "byte count out of range");
  if (n == 0) {
    lua_pushliteral(L, "");
    return 1;
  }
  unsigned char stack_raw[128];
  char stack_hex[256];
  unsigned char *raw = stack_raw;
  char *hex = stack_hex;
  if (n > (int)sizeof(stack_raw)) {
    raw = (unsigned char *)lua_newuserdata(L, (size_t)n * 3);
    hex = (char *)(raw + n);
  }
  if (RAND_bytes(raw, n) != 1) {
    return luaL_error(L, "RAND_bytes failed");
  }
  bytes_to_hex(raw, (size_t)n, hex);
  lua_pushlstring(L, hex, (size_t)n * 2);
  return 1;
}

static const struct luaL_Reg cryptolib[] = {
    {"sha256", l_sha256},
    {"sha256_file", l_sha256_file},
    {"hmac_sha256", l_hmac_sha256},
    {"random_bytes", l_random_bytes},
    {"random_hex", l_random_hex},
    {NULL, NULL},
};

LUALIB_API int luaopen_crypto(lua_State *L) {
  lua_newtable(L);
  luaL_register(L, NULL, cryptolib);
  return 1;
}
