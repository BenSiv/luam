#include <stdio.h>
#include <time.h>
#include <sys/time.h>
#include "lua.h"
#include "lauxlib.h"

/* timeout control structure */
typedef struct t_timeout_ {
    double block;          /* maximum time for blocking calls */
    double total;          /* total number of miliseconds for operation */
    double start;          /* time of start of operation */
} t_timeout;
typedef t_timeout *p_timeout;

double timeout_gettime(void) {
    struct timeval v;
    gettimeofday(&v, (struct timezone *) NULL);
    /* Unix Epoch time (time since January 1, 1970 (UTC)) */
    return v.tv_sec + v.tv_usec/1.0e6;
}

void timeout_init(p_timeout tm, double block, double total) {
    tm->block = block;
    tm->total = total;
}

p_timeout timeout_markstart(p_timeout tm) {
    tm->start = timeout_gettime();
    return tm;
}

int timeout_meth_settimeout(lua_State *L, p_timeout tm) {
    double t = luaL_optnumber(L, 2, -1);
    const char *mode = luaL_optstring(L, 3, "b");
    if (*mode == 'b') {
        tm->block = t;
    } else if (*mode == 'r' || *mode == 't') {
        tm->total = t;
    }
    lua_pushnumber(L, 1);
    return 1;
}

LUALIB_API int luaopen_timeout(lua_State *L) {
    (void)L;
    /* This function exists to force the linker to include this object
       and export its symbols (like timeout_markstart) for modules. */
    return 0;
}
