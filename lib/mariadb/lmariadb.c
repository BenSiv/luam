/*
** mariadb: a thin Lua binding over MariaDB Connector/C (libmariadb),
** not a vendored client implementation -- same "thin wrapper over a
** battle-tested library" choice as lib/bcrypt/bcrypt.c and
** lib/hmac/hmac.c, just with a persistent connection object instead of
** a pure function, since a network database connection is real state
** a caller needs to hold onto and reuse (unlike bcrypt/hmac, which are
** stateless per call). See doc/mariadb-migration.md (platform-wip repo)
** for why this exists: platform-wip's own lib/database.lua opens a
** fresh SQLite connection per call, which is free for a local file but
** would be a severe latency regression per network round-trip for a
** real client/server database -- so unlike lsqlite3.c's db-per-call
** convenience, this binding is deliberately built around a connection
** object a caller keeps open and reuses across many queries.
**
** Deliberately does NOT expose a prepared-statement/cursor object the
** way lsqlite3.c does -- lib/database.lua's own local_query/local_update
** only ever need "run this query, get back all rows" or "run this
** statement, get back affected-rows/insert-id" in one call, so query()
** buffers the full result set into a Lua table directly in C
** (mysql_store_result + a fetch loop) rather than exposing row-by-row
** iteration to Lua. Simpler surface, matches the one calling shape
** that's actually needed.
**
** Requires linking against -lmariadb (MariaDB Connector/C, Debian/
** Ubuntu package libmariadb-dev; headers under /usr/include/mariadb).
*/

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <mysql.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#if LUA_VERSION_NUM >= 502
#define new_lib(L, l) (luaL_newlib(L, l))
#define set_methods(L, l) (luaL_setfuncs(L, l, 0))
#else
#define new_lib(L, l) (lua_newtable(L), luaL_register(L, NULL, l))
#define set_methods(L, l) (luaL_register(L, NULL, l))
#endif

#define MARIADB_CONN_META "mariadb.connection"

typedef struct {
    MYSQL *conn; /* NULL once closed/never connected */
} lmdb_conn;

static lmdb_conn *check_conn(lua_State *L, int idx) {
    return (lmdb_conn *)luaL_checkudata(L, idx, MARIADB_CONN_META);
}

/* Every method below starts by requiring an still-open connection --
** factored out since it's the same three lines in query/exec/escape/ping. */
static lmdb_conn *check_open_conn(lua_State *L, int idx) {
    lmdb_conn *c = check_conn(L, idx);
    luaL_argcheck(L, c->conn != NULL, idx, "connection is closed");
    return c;
}

/* mariadb.connect(host, port, user, password, database) -> conn | nil, err_string
** port may be nil/0 for MariaDB's own default (3306). password may be
** "" for a passwordless account (matches this project's other bindings'
** convention of never silently guessing/defaulting a credential). */
static int l_mariadb_connect(lua_State *L) {
    const char *host = luaL_checkstring(L, 1);
    lua_Integer port = luaL_optinteger(L, 2, 0);
    const char *user = luaL_checkstring(L, 3);
    const char *password = luaL_optstring(L, 4, "");
    const char *database = luaL_checkstring(L, 5);

    MYSQL *raw = mysql_init(NULL);
    if (raw == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "mysql_init failed (out of memory)");
        return 2;
    }

    if (mysql_real_connect(raw, host, user, password, database,
                            (unsigned int)port, NULL, 0) == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, mysql_error(raw));
        mysql_close(raw);
        return 2;
    }

    lmdb_conn *c = (lmdb_conn *)lua_newuserdata(L, sizeof(lmdb_conn));
    c->conn = raw;
    luaL_getmetatable(L, MARIADB_CONN_META);
    lua_setmetatable(L, -2);
    return 1;
}

/* Buffers a result set into a {{colname=value, ...}, ...} Lua array
** (1-indexed rows, matching lib/database.lua's own row-table shape
** from local_query's sqlite path) and frees it. NULL columns
** become Lua nil, not the string "NULL" or an empty string -- matches
** local_query's own handling of a SQLite NULL. */
static void push_result_rows(lua_State *L, MYSQL_RES *res) {
    unsigned int num_fields = mysql_num_fields(res);
    MYSQL_FIELD *fields = mysql_fetch_fields(res);

    lua_newtable(L);
    lua_Integer row_idx = 0;
    MYSQL_ROW row;
    while ((row = mysql_fetch_row(res)) != NULL) {
        unsigned long *lengths = mysql_fetch_lengths(res);
        row_idx++;
        lua_newtable(L);
        unsigned int i;
        for (i = 0; i < num_fields; i++) {
            lua_pushstring(L, fields[i].name);
            if (row[i] == NULL) {
                lua_pushnil(L);
            } else {
                lua_pushlstring(L, row[i], lengths[i]);
            }
            lua_settable(L, -3);
        }
        lua_rawseti(L, -2, row_idx);
    }
    mysql_free_result(res);
}

/* conn:query(sql) -> rows_table | nil, err_string
** For a statement with no result set (e.g. called with an INSERT by
** mistake), returns an empty table rather than erroring -- callers
** wanting affected-rows/insert-id should use exec() instead, mirroring
** local_query/local_update's own query-vs-statement split. */
static int l_mariadb_query(lua_State *L) {
    lmdb_conn *c = check_open_conn(L, 1);
    size_t len;
    const char *sql = luaL_checklstring(L, 2, &len);

    if (mysql_real_query(c->conn, sql, (unsigned long)len) != 0) {
        lua_pushnil(L);
        lua_pushstring(L, mysql_error(c->conn));
        return 2;
    }

    MYSQL_RES *res = mysql_store_result(c->conn);
    if (res == NULL) {
        if (mysql_field_count(c->conn) == 0) {
            lua_newtable(L);
            return 1;
        }
        lua_pushnil(L);
        lua_pushstring(L, mysql_error(c->conn));
        return 2;
    }

    push_result_rows(L, res);
    return 1;
}

/* conn:exec(sql) -> affected_rows, insert_id | nil, err_string
** insert_id is 0 for a statement that didn't insert an AUTO_INCREMENT
** row (matches mysql_insert_id's own convention) -- callers only read
** it after an INSERT they know has one. */
static int l_mariadb_exec(lua_State *L) {
    lmdb_conn *c = check_open_conn(L, 1);
    size_t len;
    const char *sql = luaL_checklstring(L, 2, &len);

    if (mysql_real_query(c->conn, sql, (unsigned long)len) != 0) {
        lua_pushnil(L);
        lua_pushstring(L, mysql_error(c->conn));
        return 2;
    }

    /* A caller could still pass exec() a SELECT by mistake -- drain and
    ** discard any result set rather than leaving it unread, which would
    ** desync whatever the next call on this same connection tries to do. */
    MYSQL_RES *res = mysql_store_result(c->conn);
    if (res != NULL) {
        mysql_free_result(res);
    }

    lua_pushinteger(L, (lua_Integer)mysql_affected_rows(c->conn));
    lua_pushinteger(L, (lua_Integer)mysql_insert_id(c->conn));
    return 2;
}

/* conn:escape(str) -> escaped_str
** Real mysql_real_escape_string, connection/charset-aware -- not a
** naive quote-doubling gsub the way database.lua's escape_sqlite is.
** Still string-interpolation-oriented (matches this project's existing
** calling convention -- see doc/mariadb-migration.md's "Design
** decisions" section on bound parameters as a later, additive option). */
static int l_mariadb_escape(lua_State *L) {
    lmdb_conn *c = check_open_conn(L, 1);
    size_t len;
    const char *str = luaL_checklstring(L, 2, &len);

    char *buf = (char *)malloc(len * 2 + 1);
    if (buf == NULL) {
        return luaL_error(L, "out of memory");
    }
    unsigned long escaped_len = mysql_real_escape_string(c->conn, buf, str, (unsigned long)len);
    lua_pushlstring(L, buf, escaped_len);
    free(buf);
    return 1;
}

/* conn:ping() -> boolean
** true if the connection is alive (transparently reconnecting first if
** the server's wait_timeout already dropped it and the client library
** is configured to allow that), false otherwise. Needed by a
** persistent-connection wrapper (reused across many requests, unlike
** SQLite's open-per-call model) to detect and replace a dead connection
** before reusing it, rather than failing the next query with a stale
** "server has gone away" error. */
static int l_mariadb_ping(lua_State *L) {
    lmdb_conn *c = check_conn(L, 1);
    if (c->conn == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_pushboolean(L, mysql_ping(c->conn) == 0);
    return 1;
}

static int l_mariadb_isopen(lua_State *L) {
    lmdb_conn *c = check_conn(L, 1);
    lua_pushboolean(L, c->conn != NULL);
    return 1;
}

static int l_mariadb_close(lua_State *L) {
    lmdb_conn *c = check_conn(L, 1);
    if (c->conn != NULL) {
        mysql_close(c->conn);
        c->conn = NULL;
    }
    return 0;
}

/* Garbage-collector safety net -- a caller that forgets to call close()
** explicitly (e.g. an error path that returns early) must not leak the
** underlying socket/handle forever. Safe to run even after an explicit
** close() already happened (conn is NULL by then, this is a no-op). */
static int l_mariadb_gc(lua_State *L) {
    lmdb_conn *c = check_conn(L, 1);
    if (c->conn != NULL) {
        mysql_close(c->conn);
        c->conn = NULL;
    }
    return 0;
}

/* NOT exposed as conn:method()/conn.method(conn,...) dispatch through the
** connection's own metatable -- verified directly against this Luam
** build that userdata field-indexing doesn't work here even with a
** correctly-set __index metatable (the same limitation already affects
** lib/sqlite/lsqlite3.c's own db/stmt objects, which is why
** lib/database.lua never actually calls db.exec(db, ...) either --
** it always calls sqlite.exec(db, ...), a flat module-level function
** taking the userdata as an explicit argument). So every real operation
** here is a flat function on the `mariadb` module table instead,
** matching that same, actually-working convention: mariadb.query(conn,
** sql), mariadb.exec(conn, sql), etc. The metatable below exists only
** for luaL_checkudata's type safety and the __gc finalizer, which the
** Lua GC invokes directly (a C-level metatable event, unrelated to
** Luam's own indexing sugar/parser). */
static const struct luaL_Reg conn_meta_methods[] = {
    {"__gc", l_mariadb_gc},
    {NULL, NULL}
};

static const struct luaL_Reg mariadblib[] = {
    {"connect", l_mariadb_connect},
    {"query", l_mariadb_query},
    {"exec", l_mariadb_exec},
    {"escape", l_mariadb_escape},
    {"ping", l_mariadb_ping},
    {"isopen", l_mariadb_isopen},
    {"close", l_mariadb_close},
    {NULL, NULL}
};

LUALIB_API int luaopen_mariadb(lua_State *L);

LUALIB_API int luaopen_mariadb(lua_State *L) {
    luaL_newmetatable(L, MARIADB_CONN_META);
    set_methods(L, conn_meta_methods);
    lua_pop(L, 1);

    new_lib(L, mariadblib);
    return 1;
}
