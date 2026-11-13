/*
** $Id: lstrlib.c,v 1.132.1.5 2010/05/14 15:34:19 roberto Exp $
** Standard library for string operations and pattern-matching
** See Copyright Notice in lua.h
*/


#include <ctype.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define lstrlib_c
#define LUA_LIB

#include "lua.h"

#include "lauxlib.h"
#include "lualib.h"


/* macro to `unsign' a character */
#define uchar(c) ((unsigned char)(c))


static int str_len(lua_State *L) {
  size_t l;
  luaL_checklstring(L, 1, &l);
  lua_pushinteger(L, l);
  return 1;
}


static ptrdiff_t posrelat(ptrdiff_t pos, size_t len) {
  /* relative string position: negative means back from end */
  if (pos < 0)
    pos += (ptrdiff_t)len + 1;
  return (pos >= 0) ? pos : 0;
}


static int str_sub(lua_State *L) {
  size_t l;
  const char *s = luaL_checklstring(L, 1, &l);
  ptrdiff_t start = posrelat(luaL_checkinteger(L, 2), l);
  ptrdiff_t end = posrelat(luaL_optinteger(L, 3, -1), l);
  if (start < 1)
    start = 1;
  if (end > (ptrdiff_t)l)
    end = (ptrdiff_t)l;
  if (start <= end)
    lua_pushlstring(L, s + start - 1, end - start + 1);
  else
    lua_pushliteral(L, "");
  return 1;
}


static int str_reverse(lua_State *L) {
  size_t l;
  luaL_Buffer b;
  const char *s = luaL_checklstring(L, 1, &l);
  luaL_buffinit(L, &b);
  while (l--)
    luaL_addchar(&b, s[l]);
  luaL_pushresult(&b);
  return 1;
}


static int str_lower(lua_State *L) {
  size_t l;
  size_t i;
  luaL_Buffer b;
  const char *s = luaL_checklstring(L, 1, &l);
  luaL_buffinit(L, &b);
  for (i = 0; i < l; i++)
    luaL_addchar(&b, tolower(uchar(s[i])));
  luaL_pushresult(&b);
  return 1;
}


static int str_upper(lua_State *L) {
  size_t l;
  size_t i;
  luaL_Buffer b;
  const char *s = luaL_checklstring(L, 1, &l);
  luaL_buffinit(L, &b);
  for (i = 0; i < l; i++)
    luaL_addchar(&b, toupper(uchar(s[i])));
  luaL_pushresult(&b);
  return 1;
}

static int str_rep(lua_State *L) {
  size_t l;
  luaL_Buffer b;
  const char *s = luaL_checklstring(L, 1, &l);
  int n = luaL_checkint(L, 2);
  luaL_buffinit(L, &b);
  while (n-- > 0)
    luaL_addlstring(&b, s, l);
  luaL_pushresult(&b);
  return 1;
}


static int str_byte(lua_State *L) {
  size_t l;
  const char *s = luaL_checklstring(L, 1, &l);
  ptrdiff_t posi = posrelat(luaL_optinteger(L, 2, 1), l);
  ptrdiff_t pose = posrelat(luaL_optinteger(L, 3, posi), l);
  int n, i;
  if (posi <= 0)
    posi = 1;
  if ((size_t)pose > l)
    pose = l;
  if (posi > pose)
    return 0; /* empty interval; return no values */
  n = (int)(pose - posi + 1);
  if (posi + n <= pose) /* overflow? */
    luaL_error(L, "string slice too long");
  luaL_checkstack(L, n, "string slice too long");
  for (i = 0; i < n; i++)
    lua_pushinteger(L, uchar(s[posi + i - 1]));
  return n;
}


static int str_char(lua_State *L) {
  int n = lua_gettop(L); /* number of arguments */
  int i;
  luaL_Buffer b;
  luaL_buffinit(L, &b);
  for (i = 1; i <= n; i++) {
    int c = luaL_checkint(L, i);
    luaL_argcheck(L, uchar(c) == c, i, "invalid value");
    luaL_addchar(&b, uchar(c));
  }
  luaL_pushresult(&b);
  return 1;
}


static int writer(lua_State *L, const void *b, size_t size, void *B) {
  (void)L;
  luaL_addlstring((luaL_Buffer *)B, (const char *)b, size);
  return 0;
}


static int str_dump(lua_State *L) {
  luaL_Buffer b;
  luaL_checktype(L, 1, LUA_TFUNCTION);
  lua_settop(L, 1);
  luaL_buffinit(L, &b);
  if (lua_dump(L, writer, &b) != 0)
    luaL_error(L, "unable to dump given function");
  luaL_pushresult(&b);
  return 1;
}


/*
** {======================================================
** PATTERN MATCHING
** =======================================================
*/


#define CAP_UNFINISHED (-1)
#define CAP_POSITION (-2)

typedef struct MatchState {
  const char *src_init; /* init of source string */
  const char *src_end;  /* end (`\0') of source string */
  lua_State *L;
  int level; /* total number of captures (finished or unfinished) */
  struct {
    const char *init;
    ptrdiff_t len;
  } capture[LUA_MAXCAPTURES];
} MatchState;


#define L_ESC '%'
#define SPECIALS "^$*+?.([%-"


static int check_capture(MatchState *ms, int l) {
  l -= '1';
  if (l < 0 || l >= ms->level || ms->capture[l].len == CAP_UNFINISHED)
    return luaL_error(ms->L, "invalid capture index");
  return l;
}


static int capture_to_close(MatchState *ms) {
  int level = ms->level;
  for (level--; level >= 0; level--)
    if (ms->capture[level].len == CAP_UNFINISHED)
      return level;
  return luaL_error(ms->L, "invalid pattern capture");
}


static const char *classend(MatchState *ms, const char *p) {
  switch (*p++) {
  case L_ESC: {
    if (*p == '\0')
      luaL_error(ms->L, "malformed pattern (ends with " LUA_QL("%%") ")");
    return p + 1;
  }
  case '[': {
    if (*p == '^')
      p++;
    do { /* look for a `]' */
      if (*p == '\0')
        luaL_error(ms->L, "malformed pattern (missing " LUA_QL("]") ")");
      if (*(p++) == L_ESC && *p != '\0')
        p++; /* skip escapes (e.g. `%]') */
    } while (*p != ']');
    return p + 1;
  }
  default: {
    return p;
  }
  }
}


static int match_class(int c, int cl) {
  int res;
  switch (tolower(cl)) {
  case 'a':
    res = isalpha(c);
    break;
  case 'c':
    res = iscntrl(c);
    break;
  case 'd':
    res = isdigit(c);
    break;
  case 'l':
    res = islower(c);
    break;
  case 'p':
    res = ispunct(c);
    break;
  case 's':
    res = isspace(c);
    break;
  case 'u':
    res = isupper(c);
    break;
  case 'w':
    res = isalnum(c);
    break;
  case 'x':
    res = isxdigit(c);
    break;
  case 'z':
    res = (c == 0);
    break;
  default:
    return (cl == c);
  }
  return (islower(cl) ? res : !res);
}


static int matchbracketclass(int c, const char *p, const char *ec) {
  int sig = 1;
  if (*(p + 1) == '^') {
    sig = 0;
    p++; /* skip the `^' */
  }
  while (++p < ec) {
    if (*p == L_ESC) {
      p++;
      if (match_class(c, uchar(*p)))
        return sig;
    } else if ((*(p + 1) == '-') && (p + 2 < ec)) {
      p += 2;
      if (uchar(*(p - 2)) <= c && c <= uchar(*p))
        return sig;
    } else if (uchar(*p) == c)
      return sig;
  }
  return !sig;
}


static int singlematch(int c, const char *p, const char *ep) {
  switch (*p) {
  case '.':
    return 1; /* matches any char */
  case L_ESC:
    return match_class(c, uchar(*(p + 1)));
  case '[':
    return matchbracketclass(c, p, ep - 1);
  default:
    return (uchar(*p) == c);
  }
}


static const char *match(MatchState *ms, const char *s, const char *p);


static const char *matchbalance(MatchState *ms, const char *s, const char *p) {
  if (*p == 0 || *(p + 1) == 0)
    luaL_error(ms->L, "unbalanced pattern");
  if (*s != *p)
    return NULL;
  else {
    int b = *p;
    int e = *(p + 1);
    int cont = 1;
    while (++s < ms->src_end) {
      if (*s == e) {
        if (--cont == 0)
          return s + 1;
      } else if (*s == b)
        cont++;
    }
  }
  return NULL; /* string ends out of balance */
}


static const char *max_expand(MatchState *ms, const char *s, const char *p,
                              const char *ep) {
  ptrdiff_t i = 0; /* counts maximum expand for item */
  while ((s + i) < ms->src_end && singlematch(uchar(*(s + i)), p, ep))
    i++;
  /* keeps trying to match with the maximum repetitions */
  while (i >= 0) {
    const char *res = match(ms, (s + i), ep + 1);
    if (res)
      return res;
    i--; /* else didn't match; reduce 1 repetition to try again */
  }
  return NULL;
}


static const char *min_expand(MatchState *ms, const char *s, const char *p,
                              const char *ep) {
  for (;;) {
    const char *res = match(ms, s, ep + 1);
    if (res != NULL)
      return res;
    else if (s < ms->src_end && singlematch(uchar(*s), p, ep))
      s++; /* try with one more repetition */
    else
      return NULL;
  }
}


static const char *start_capture(MatchState *ms, const char *s, const char *p,
                                 int what) {
  const char *res;
  int level = ms->level;
  if (level >= LUA_MAXCAPTURES)
    luaL_error(ms->L, "too many captures");
  ms->capture[level].init = s;
  ms->capture[level].len = what;
  ms->level = level + 1;
  if ((res = match(ms, s, p)) == NULL) /* match failed? */
    ms->level--;                       /* undo capture */
  return res;
}


static const char *end_capture(MatchState *ms, const char *s, const char *p) {
  int l = capture_to_close(ms);
  const char *res;
  ms->capture[l].len = s - ms->capture[l].init; /* close capture */
  if ((res = match(ms, s, p)) == NULL)          /* match failed? */
    ms->capture[l].len = CAP_UNFINISHED;        /* undo capture */
  return res;
}


static const char *match_capture(MatchState *ms, const char *s, int l) {
  size_t len;
  l = check_capture(ms, l);
  len = ms->capture[l].len;
  if ((size_t)(ms->src_end - s) >= len &&
      memcmp(ms->capture[l].init, s, len) == 0)
    return s + len;
  else
    return NULL;
}


static const char *match(MatchState *ms, const char *s, const char *p) {
init: /* using goto's to optimize tail recursion */
  switch (*p) {
  case '(': {            /* start capture */
    if (*(p + 1) == ')') /* position capture? */
      return start_capture(ms, s, p + 2, CAP_POSITION);
    else
      return start_capture(ms, s, p + 1, CAP_UNFINISHED);
  }
  case ')': { /* end capture */
    return end_capture(ms, s, p + 1);
  }
  case L_ESC: {
    switch (*(p + 1)) {
    case 'b': { /* balanced string? */
      s = matchbalance(ms, s, p + 2);
      if (s == NULL)
        return NULL;
      p += 4;
      goto init; /* else return match(ms, s, p+4); */
    }
    case 'f': { /* frontier? */
      const char *ep;
      char previous;
      p += 2;
      if (*p != '[')
        luaL_error(ms->L, "missing " LUA_QL("[") " after " LUA_QL(
                              "%%f") " in pattern");
      ep = classend(ms, p); /* points to what is next */
      previous = (s == ms->src_init) ? '\0' : *(s - 1);
      if (matchbracketclass(uchar(previous), p, ep - 1) ||
          !matchbracketclass(uchar(*s), p, ep - 1))
        return NULL;
      p = ep;
      goto init; /* else return match(ms, s, ep); */
    }
    default: {
      if (isdigit(uchar(*(p + 1)))) { /* capture results (%0-%9)? */
        s = match_capture(ms, s, uchar(*(p + 1)));
        if (s == NULL)
          return NULL;
        p += 2;
        goto init; /* else return match(ms, s, p+2) */
      }
      goto dflt; /* case default */
    }
    }
  }
  case '\0': { /* end of pattern */
    return s;  /* match succeeded */
  }
  case '$': {
    if (*(p + 1) == '\0') /* is the `$' the last char in pattern? */
      return (s == ms->src_end) ? s : NULL; /* check end of string */
    else
      goto dflt;
  }
  default:
  dflt: {                             /* it is a pattern item */
    const char *ep = classend(ms, p); /* points to what is next */
    int m = s < ms->src_end && singlematch(uchar(*s), p, ep);
    switch (*ep) {
    case '?': { /* optional */
      const char *res;
      if (m && ((res = match(ms, s + 1, ep + 1)) != NULL))
        return res;
      p = ep + 1;
      goto init; /* else return match(ms, s, ep+1); */
    }
    case '*': { /* 0 or more repetitions */
      return max_expand(ms, s, p, ep);
    }
    case '+': { /* 1 or more repetitions */
      return (m ? max_expand(ms, s + 1, p, ep) : NULL);
    }
    case '-': { /* 0 or more repetitions (minimum) */
      return min_expand(ms, s, p, ep);
    }
    default: {
      if (!m)
        return NULL;
      s++;
      p = ep;
      goto init; /* else return match(ms, s+1, ep); */
    }
    }
  }
  }
}


static const char *lmemfind(const char *s1, size_t l1, const char *s2,
                            size_t l2) {
  if (l2 == 0)
    return s1; /* empty strings are everywhere */
  else if (l2 > l1)
    return NULL; /* avoids a negative `l1' */
  else {
    const char *init; /* to search for a `*s2' inside `s1' */
    l2--;             /* 1st char will be checked by `memchr' */
    l1 = l1 - l2;     /* `s2' cannot be found after that */
    while (l1 > 0 && (init = (const char *)memchr(s1, *s2, l1)) != NULL) {
      init++; /* 1st char is already checked */
      if (memcmp(init, s2 + 1, l2) == 0)
        return init - 1;
      else { /* correct `l1' and `s1' to try again */
        l1 -= init - s1;
        s1 = init;
      }
    }
    return NULL; /* not found */
  }
}


static void push_onecapture(MatchState *ms, int i, const char *s,
                            const char *e) {
  if (i >= ms->level) {
    if (i == 0)                         /* ms->level == 0, too */
      lua_pushlstring(ms->L, s, e - s); /* add whole match */
    else
      luaL_error(ms->L, "invalid capture index");
  } else {
    ptrdiff_t l = ms->capture[i].len;
    if (l == CAP_UNFINISHED)
      luaL_error(ms->L, "unfinished capture");
    if (l == CAP_POSITION)
      lua_pushinteger(ms->L, ms->capture[i].init - ms->src_init + 1);
    else
      lua_pushlstring(ms->L, ms->capture[i].init, l);
  }
}


static int push_captures(MatchState *ms, const char *s, const char *e) {
  int i;
  int nlevels = (ms->level == 0 && s) ? 1 : ms->level;
  luaL_checkstack(ms->L, nlevels, "too many captures");
  for (i = 0; i < nlevels; i++)
    push_onecapture(ms, i, s, e);
  return nlevels; /* number of strings pushed */
}


static int str_find_aux(lua_State *L, int find) {
  size_t l1, l2;
  const char *s = luaL_checklstring(L, 1, &l1);
  const char *p = luaL_checklstring(L, 2, &l2);
  ptrdiff_t init = posrelat(luaL_optinteger(L, 3, 1), l1) - 1;
  if (init < 0)
    init = 0;
  else if ((size_t)(init) > l1)
    init = (ptrdiff_t)l1;
  if (find && (lua_toboolean(L, 4) ||           /* explicit request? */
               strpbrk(p, SPECIALS) == NULL)) { /* or no special characters? */
    /* do a plain search */
    const char *s2 = lmemfind(s + init, l1 - init, p, l2);
    if (s2) {
      lua_pushinteger(L, s2 - s + 1);
      lua_pushinteger(L, s2 - s + l2);
      return 2;
    }
  } else {
    MatchState ms;
    int anchor = (*p == '^') ? (p++, 1) : 0;
    const char *s1 = s + init;
    ms.L = L;
    ms.src_init = s;
    ms.src_end = s + l1;
    do {
      const char *res;
      ms.level = 0;
      if ((res = match(&ms, s1, p)) != NULL) {
        if (find) {
          lua_pushinteger(L, s1 - s + 1); /* start */
          lua_pushinteger(L, res - s);    /* end */
          return push_captures(&ms, NULL, 0) + 2;
        } else
          return push_captures(&ms, s1, res);
      }
    } while (s1++ < ms.src_end && !anchor);
  }
  lua_pushnil(L); /* not found */
  return 1;
}


static int str_find(lua_State *L) {
  return str_find_aux(L, 1);
}


static int str_match(lua_State *L) {
  return str_find_aux(L, 0);
}


static int gmatch_aux(lua_State *L) {
  MatchState ms;
  size_t ls;
  const char *s = lua_tolstring(L, lua_upvalueindex(1), &ls);
  const char *p = lua_tostring(L, lua_upvalueindex(2));
  const char *src;
  ms.L = L;
  ms.src_init = s;
  ms.src_end = s + ls;
  for (src = s + (size_t)lua_tointeger(L, lua_upvalueindex(3));
       src <= ms.src_end; src++) {
    const char *e;
    ms.level = 0;
    if ((e = match(&ms, src, p)) != NULL) {
      lua_Integer newstart = e - s;
      if (e == src)
        newstart++; /* empty match? go at least one position */
      lua_pushinteger(L, newstart);
      lua_replace(L, lua_upvalueindex(3));
      return push_captures(&ms, src, e);
    }
  }
  return 0; /* not found */
}


static int gmatch(lua_State *L) {
  luaL_checkstring(L, 1);
  luaL_checkstring(L, 2);
  lua_settop(L, 2);
  lua_pushinteger(L, 0);
  lua_pushcclosure(L, gmatch_aux, 3);
  return 1;
}


static int gfind_nodef(lua_State *L) {
  return luaL_error(
      L, LUA_QL("string.gfind") " was renamed to " LUA_QL("string.gmatch"));
}


static void add_s(MatchState *ms, luaL_Buffer *b, const char *s,
                  const char *e) {
  size_t l, i;
  const char *news = lua_tolstring(ms->L, 3, &l);
  for (i = 0; i < l; i++) {
    if (news[i] != L_ESC)
      luaL_addchar(b, news[i]);
    else {
      i++; /* skip ESC */
      if (!isdigit(uchar(news[i])))
        luaL_addchar(b, news[i]);
      else if (news[i] == '0')
        luaL_addlstring(b, s, e - s);
      else {
        push_onecapture(ms, news[i] - '1', s, e);
        luaL_addvalue(b); /* add capture to accumulated result */
      }
    }
  }
}


static void add_value(MatchState *ms, luaL_Buffer *b, const char *s,
                      const char *e) {
  lua_State *L = ms->L;
  switch (lua_type(L, 3)) {
  case LUA_TNUMBER:
  case LUA_TSTRING: {
    add_s(ms, b, s, e);
    return;
  }
  case LUA_TFUNCTION: {
    int n;
    lua_pushvalue(L, 3);
    n = push_captures(ms, s, e);
    lua_call(L, n, 1);
    break;
  }
  case LUA_TTABLE: {
    push_onecapture(ms, 0, s, e);
    lua_gettable(L, 3);
    break;
  }
  }
  if (!lua_toboolean(L, -1)) { /* nil or false? */
    lua_pop(L, 1);
    lua_pushlstring(L, s, e - s); /* keep original text */
  } else if (!lua_isstring(L, -1))
    luaL_error(L, "invalid replacement value (a %s)", luaL_typename(L, -1));
  luaL_addvalue(b); /* add result to accumulator */
}


static int str_gsub(lua_State *L) {
  size_t srcl;
  const char *src = luaL_checklstring(L, 1, &srcl);
  const char *p = luaL_checkstring(L, 2);
  int tr = lua_type(L, 3);
  int max_s = luaL_optint(L, 4, srcl + 1);
  int anchor = (*p == '^') ? (p++, 1) : 0;
  int n = 0;
  MatchState ms;
  luaL_Buffer b;
  luaL_argcheck(L,
                tr == LUA_TNUMBER || tr == LUA_TSTRING || tr == LUA_TFUNCTION ||
                    tr == LUA_TTABLE,
                3, "string/function/table expected");
  luaL_buffinit(L, &b);
  ms.L = L;
  ms.src_init = src;
  ms.src_end = src + srcl;
  while (n < max_s) {
    const char *e;
    ms.level = 0;
    e = match(&ms, src, p);
    if (e) {
      n++;
      add_value(&ms, &b, src, e);
    }
    if (e && e > src) /* non empty match? */
      src = e;        /* skip it */
    else if (src < ms.src_end)
      luaL_addchar(&b, *src++);
    else
      break;
    if (anchor)
      break;
  }
  luaL_addlstring(&b, src, ms.src_end - src);
  luaL_pushresult(&b);
  lua_pushinteger(L, n); /* number of substitutions */
  return 2;
}

/* }====================================================== */


/* maximum size of each formatted item (> len(format('%99.99f', -1e308))) */
#define MAX_ITEM 512
/* valid flags in a format specification */
#define FLAGS "-+ #0"
/*
** maximum size of each format specification (such as '%-099.99d')
** (+10 accounts for %99.99x plus margin of error)
*/
#define MAX_FORMAT (sizeof(FLAGS) + sizeof(LUA_INTFRMLEN) + 10)


static void addquoted(lua_State *L, luaL_Buffer *b, int arg) {
  size_t l;
  const char *s = luaL_checklstring(L, arg, &l);
  luaL_addchar(b, '"');
  while (l--) {
    switch (*s) {
    case '"':
    case '\\':
    case '\n': {
      luaL_addchar(b, '\\');
      luaL_addchar(b, *s);
      break;
    }
    case '\r': {
      luaL_addlstring(b, "\\r", 2);
      break;
    }
    case '\0': {
      luaL_addlstring(b, "\\x00", 4);
      break;
    }
    default: {
      luaL_addchar(b, *s);
      break;
    }
    }
    s++;
  }
  luaL_addchar(b, '"');
}

static const char *scanformat(lua_State *L, const char *strfrmt, char *form) {
  const char *p = strfrmt;
  while (*p != '\0' && strchr(FLAGS, *p) != NULL)
    p++; /* skip flags */
  if ((size_t)(p - strfrmt) >= sizeof(FLAGS))
    luaL_error(L, "invalid format (repeated flags)");
  if (isdigit(uchar(*p)))
    p++; /* skip width */
  if (isdigit(uchar(*p)))
    p++; /* (2 digits at most) */
  if (*p == '.') {
    p++;
    if (isdigit(uchar(*p)))
      p++; /* skip precision */
    if (isdigit(uchar(*p)))
      p++; /* (2 digits at most) */
  }
  if (isdigit(uchar(*p)))
    luaL_error(L, "invalid format (width or precision too long)");
  *(form++) = '%';
  strncpy(form, strfrmt, p - strfrmt + 1);
  form += p - strfrmt + 1;
  *form = '\0';
  return p;
}


static void addintlen(char *form) {
  size_t l = strlen(form);
  char spec = form[l - 1];
  strcpy(form + l - 1, LUA_INTFRMLEN);
  form[l + sizeof(LUA_INTFRMLEN) - 2] = spec;
  form[l + sizeof(LUA_INTFRMLEN) - 1] = '\0';
}


static int str_format(lua_State *L) {
  int top = lua_gettop(L);
  int arg = 1;
  size_t sfl;
  const char *strfrmt = luaL_checklstring(L, arg, &sfl);
  const char *strfrmt_end = strfrmt + sfl;
  luaL_Buffer b;
  luaL_buffinit(L, &b);
  while (strfrmt < strfrmt_end) {
    if (*strfrmt != L_ESC)
      luaL_addchar(&b, *strfrmt++);
    else if (*++strfrmt == L_ESC)
      luaL_addchar(&b, *strfrmt++); /* %% */
    else {                          /* format item */
      char form[MAX_FORMAT];        /* to store the format (`%...') */
      char buff[MAX_ITEM];          /* to store the formatted item */
      if (++arg > top)
        luaL_argerror(L, arg, "no value");
      strfrmt = scanformat(L, strfrmt, form);
      switch (*strfrmt++) {
      case 'c': {
        sprintf(buff, form, (int)luaL_checknumber(L, arg));
        break;
      }
      case 'd':
      case 'i': {
        addintlen(form);
        sprintf(buff, form, (LUA_INTFRM_T)luaL_checknumber(L, arg));
        break;
      }
      case 'o':
      case 'u':
      case 'x':
      case 'X': {
        addintlen(form);
        sprintf(buff, form, (unsigned LUA_INTFRM_T)luaL_checknumber(L, arg));
        break;
      }
      case 'e':
      case 'E':
      case 'f':
      case 'g':
      case 'G': {
        sprintf(buff, form, (double)luaL_checknumber(L, arg));
        break;
      }
      case 'q': {
        addquoted(L, &b, arg);
        continue; /* skip the 'addsize' at the end */
      }
      case 's': {
        size_t l;
        const char *s = luaL_checklstring(L, arg, &l);
        if (!strchr(form, '.') && l >= 100) {
          /* no precision and string is too long to be formatted;
             keep original string */
          lua_pushvalue(L, arg);
          luaL_addvalue(&b);
          continue; /* skip the `addsize' at the end */
        } else {
          sprintf(buff, form, s);
          break;
        }
      }
      default: { /* also treat cases `pnLlh' */
        return luaL_error(
            L, "invalid option " LUA_QL("%%%c") " to " LUA_QL("format"),
            *(strfrmt - 1));
      }
      }
      luaL_addlstring(&b, buff, strlen(buff));
    }
  }
  luaL_pushresult(&b);
  return 1;
}


/*
** {======================================================
** Plain-text string helpers (literal bytes, no pattern magic)
** =======================================================
*/

static int str_contains(lua_State *L) {
  size_t ls, lsub;
  const char *s = luaL_checklstring(L, 1, &ls);
  const char *sub = luaL_checklstring(L, 2, &lsub);
  lua_pushboolean(L, lmemfind(s, ls, sub, lsub) != NULL);
  return 1;
}

static int str_starts_with(lua_State *L) {
  size_t ls, lp;
  const char *s = luaL_checklstring(L, 1, &ls);
  const char *p = luaL_checklstring(L, 2, &lp);
  lua_pushboolean(L, lp <= ls && memcmp(s, p, lp) == 0);
  return 1;
}

static int str_ends_with(lua_State *L) {
  size_t ls, lsuf;
  const char *s = luaL_checklstring(L, 1, &ls);
  const char *suf = luaL_checklstring(L, 2, &lsuf);
  lua_pushboolean(L, lsuf <= ls && memcmp(s + ls - lsuf, suf, lsuf) == 0);
  return 1;
}

static int str_index_of(lua_State *L) {
  size_t ls, lsub;
  const char *s = luaL_checklstring(L, 1, &ls);
  const char *sub = luaL_checklstring(L, 2, &lsub);
  ptrdiff_t init = posrelat(luaL_optinteger(L, 3, 1), ls) - 1;
  const char *p;
  if (init < 0) {
    init = 0;
  } else if ((size_t)init > ls) {
    lua_pushnil(L);
    return 1;
  }
  p = lmemfind(s + init, ls - (size_t)init, sub, lsub);
  if (p != NULL)
    lua_pushinteger(L, p - s + 1);
  else
    lua_pushnil(L);
  return 1;
}

static int str_count(lua_State *L) {
  size_t ls, lsub;
  const char *s = luaL_checklstring(L, 1, &ls);
  const char *sub = luaL_checklstring(L, 2, &lsub);
  lua_Integer n = 0;
  const char *p;
  luaL_argcheck(L, lsub > 0, 2, "substring cannot be empty");
  while ((p = lmemfind(s, ls, sub, lsub)) != NULL) {
    n++;
    ls -= (size_t)(p - s) + lsub;
    s = p + lsub;
  }
  lua_pushinteger(L, n);
  return 1;
}

static int str_replace(lua_State *L) {
  size_t ls, lold, lnew;
  const char *s = luaL_checklstring(L, 1, &ls);
  const char *old = luaL_checklstring(L, 2, &lold);
  const char *rep = luaL_checklstring(L, 3, &lnew);
  int has_max = !lua_isnoneornil(L, 4);
  lua_Integer max_n = has_max ? luaL_checkinteger(L, 4) : 0;
  lua_Integer count = 0;
  luaL_Buffer b;
  luaL_argcheck(L, lold > 0, 2, "old substring cannot be empty");
  luaL_buffinit(L, &b);
  while (!has_max || count < max_n) {
    const char *p = lmemfind(s, ls, old, lold);
    if (p == NULL)
      break;
    luaL_addlstring(&b, s, (size_t)(p - s));
    luaL_addlstring(&b, rep, lnew);
    ls -= (size_t)(p - s) + lold;
    s = p + lold;
    count++;
  }
  luaL_addlstring(&b, s, ls);
  luaL_pushresult(&b);
  lua_pushinteger(L, count);
  return 2;
}

static int trim_aux(lua_State *L, int left, int right) {
  size_t ls;
  const char *s = luaL_checklstring(L, 1, &ls);
  unsigned char set[256];
  size_t start = 0;
  size_t end = ls;
  memset(set, 0, sizeof(set));
  if (lua_isnoneornil(L, 2)) {
    set[' '] = 1;
    set['\t'] = 1;
    set['\n'] = 1;
    set['\r'] = 1;
    set['\v'] = 1;
    set['\f'] = 1;
  } else {
    size_t lchars, i;
    const char *chars = luaL_checklstring(L, 2, &lchars);
    for (i = 0; i < lchars; i++)
      set[uchar(chars[i])] = 1;
  }
  if (left) {
    while (start < end && set[uchar(s[start])])
      start++;
  }
  if (right) {
    while (end > start && set[uchar(s[end - 1])])
      end--;
  }
  lua_pushlstring(L, s + start, end - start);
  return 1;
}

static int str_trim(lua_State *L) {
  return trim_aux(L, 1, 1);
}

static int str_ltrim(lua_State *L) {
  return trim_aux(L, 1, 0);
}

static int str_rtrim(lua_State *L) {
  return trim_aux(L, 0, 1);
}

static int str_strip_prefix(lua_State *L) {
  size_t ls, lp;
  const char *s = luaL_checklstring(L, 1, &ls);
  const char *p = luaL_checklstring(L, 2, &lp);
  if (lp <= ls && memcmp(s, p, lp) == 0) {
    lua_pushlstring(L, s + lp, ls - lp);
    lua_pushboolean(L, 1);
  } else {
    lua_pushlstring(L, s, ls);
    lua_pushboolean(L, 0);
  }
  return 2;
}

static int str_strip_suffix(lua_State *L) {
  size_t ls, lsuf;
  const char *s = luaL_checklstring(L, 1, &ls);
  const char *suf = luaL_checklstring(L, 2, &lsuf);
  if (lsuf <= ls && memcmp(s + ls - lsuf, suf, lsuf) == 0) {
    lua_pushlstring(L, s, ls - lsuf);
    lua_pushboolean(L, 1);
  } else {
    lua_pushlstring(L, s, ls);
    lua_pushboolean(L, 0);
  }
  return 2;
}

static int str_dedent(lua_State *L) {
  size_t ls;
  const char *s = luaL_checklstring(L, 1, &ls);
  size_t i = 0;
  const char *margin = NULL;
  size_t margin_len = 0;
  const char *p, *end;
  luaL_Buffer b;
  /* strip leading wrapper blank line if empty/whitespace up to first '\n' */
  while (i < ls && (s[i] == ' ' || s[i] == '\t'))
    i++;
  if (i < ls && s[i] == '\r' && i + 1 < ls && s[i + 1] == '\n') {
    s += i + 2;
    ls -= i + 2;
  } else if (i < ls && s[i] == '\n') {
    s += i + 1;
    ls -= i + 1;
  }
  /* strip trailing whitespace-only wrapper line after last '\n' */
  i = ls;
  while (i > 0 && (s[i - 1] == ' ' || s[i - 1] == '\t'))
    i--;
  if (i > 0 && s[i - 1] == '\n') {
    i--;
    if (i > 0 && s[i - 1] == '\r')
      i--;
    ls = i;
  }
  /* pass 1: find common leading space/tab prefix across non-empty lines */
  p = s;
  end = s + ls;
  while (p < end) {
    const char *nl = (const char *)memchr(p, '\n', (size_t)(end - p));
    const char *lend = nl ? nl : end;
    size_t llen, ws = 0;
    if (lend > p && lend[-1] == '\r')
      lend--;
    llen = (size_t)(lend - p);
    while (ws < llen && (p[ws] == ' ' || p[ws] == '\t'))
      ws++;
    if (ws < llen) {
      if (margin == NULL) {
        margin = p;
        margin_len = ws;
      } else {
        size_t k = 0;
        size_t lim = ws < margin_len ? ws : margin_len;
        while (k < lim && margin[k] == p[k])
          k++;
        margin_len = k;
      }
    }
    if (nl == NULL)
      break;
    p = nl + 1;
  }
  /* pass 2: emit dedented lines */
  luaL_buffinit(L, &b);
  p = s;
  while (p < end) {
    const char *nl = (const char *)memchr(p, '\n', (size_t)(end - p));
    const char *lend = nl ? nl : end;
    int has_cr = (nl != NULL && lend > p && lend[-1] == '\r');
    size_t llen, ws = 0;
    if (has_cr)
      lend--;
    llen = (size_t)(lend - p);
    while (ws < llen && (p[ws] == ' ' || p[ws] == '\t'))
      ws++;
    if (ws < llen)
      luaL_addlstring(&b, p + margin_len, llen - margin_len);
    if (nl != NULL) {
      if (has_cr)
        luaL_addchar(&b, '\r');
      luaL_addchar(&b, '\n');
      p = nl + 1;
    } else {
      break;
    }
  }
  luaL_pushresult(&b);
  return 1;
}

static int str_split(lua_State *L) {
  size_t ls, lsep;
  const char *s = luaL_checklstring(L, 1, &ls);
  const char *sep = luaL_checklstring(L, 2, &lsep);
  int has_max = !lua_isnoneornil(L, 3);
  lua_Integer max_splits = has_max ? luaL_checkinteger(L, 3) : 0;
  lua_Integer splits = 0;
  int idx = 1;
  luaL_argcheck(L, lsep > 0, 2, "separator cannot be empty");
  lua_newtable(L);
  while (!has_max || splits < max_splits) {
    const char *p = lmemfind(s, ls, sep, lsep);
    if (p == NULL)
      break;
    lua_pushlstring(L, s, (size_t)(p - s));
    lua_rawseti(L, -2, idx++);
    ls -= (size_t)(p - s) + lsep;
    s = p + lsep;
    splits++;
  }
  lua_pushlstring(L, s, ls);
  lua_rawseti(L, -2, idx);
  return 1;
}

static int str_lines(lua_State *L) {
  size_t ls;
  const char *s = luaL_checklstring(L, 1, &ls);
  const char *end = s + ls;
  int idx = 1;
  lua_newtable(L);
  while (s < end) {
    const char *nl = (const char *)memchr(s, '\n', (size_t)(end - s));
    if (nl == NULL) {
      lua_pushlstring(L, s, (size_t)(end - s));
      lua_rawseti(L, -2, idx++);
      break;
    } else {
      size_t len = (size_t)(nl - s);
      if (len > 0 && s[len - 1] == '\r')
        len--;
      lua_pushlstring(L, s, len);
      lua_rawseti(L, -2, idx++);
      s = nl + 1;
    }
  }
  return 1;
}

static int str_words(lua_State *L) {
  size_t ls, i = 0;
  const char *s = luaL_checklstring(L, 1, &ls);
  int idx = 1;
  lua_newtable(L);
  while (i < ls) {
    size_t start;
    while (i < ls && (s[i] == ' ' || (s[i] >= '\t' && s[i] <= '\r')))
      i++;
    if (i >= ls)
      break;
    start = i;
    while (i < ls && !(s[i] == ' ' || (s[i] >= '\t' && s[i] <= '\r')))
      i++;
    lua_pushlstring(L, s + start, i - start);
    lua_rawseti(L, -2, idx++);
  }
  return 1;
}

static void push_tostring(lua_State *L, int idx) {
  if (idx < 0)
    idx = lua_gettop(L) + idx + 1;
  if (luaL_callmeta(L, idx, "__tostring")) {
    if (!lua_isstring(L, -1))
      luaL_error(L, LUA_QL("__tostring") " must return a string");
    return;
  }
  switch (lua_type(L, idx)) {
  case LUA_TNUMBER:
    lua_pushvalue(L, idx);
    lua_tostring(L, -1);
    break;
  case LUA_TSTRING:
    lua_pushvalue(L, idx);
    break;
  case LUA_TBOOLEAN:
    lua_pushstring(L, lua_toboolean(L, idx) ? "true" : "false");
    break;
  case LUA_TNIL:
    lua_pushliteral(L, "nil");
    break;
  default:
    lua_pushfstring(L, "%s: %p", luaL_typename(L, idx), lua_topointer(L, idx));
    break;
  }
}

static int is_ident_key(const char *s, size_t len) {
  size_t i;
  if (len == 0)
    return 0;
  for (i = 0; i < len; i++) {
    unsigned char c = uchar(s[i]);
    if (!(isalnum(c) || c == '_'))
      return 0;
  }
  return 1;
}

static int str_template(lua_State *L) {
  int top = lua_gettop(L);
  size_t ls;
  const char *s = luaL_checklstring(L, 1, &ls);
  const char *p = s;
  const char *end = s + ls;
  int named_mode = (top == 2 && lua_istable(L, 2));
  int pos_arg = 2;
  luaL_Buffer b;
  luaL_buffinit(L, &b);
  while (p < end) {
    const char *open = lmemfind(p, (size_t)(end - p), "{{", 2);
    const char *close;
    if (open == NULL) {
      luaL_addlstring(&b, p, (size_t)(end - p));
      break;
    }
    luaL_addlstring(&b, p, (size_t)(open - p));
    while (open + 2 < end && open[2] == '{') {
      luaL_addchar(&b, '{');
      open++;
    }
    close = lmemfind(open + 2, (size_t)(end - (open + 2)), "}}", 2);
    if (close == NULL) {
      luaL_addlstring(&b, open, (size_t)(end - open));
      break;
    }
    if (close == open + 2) {
      /* positional {{}} */
      if (pos_arg <= top) {
        push_tostring(L, pos_arg);
        luaL_addvalue(&b);
      } else {
        luaL_addlstring(&b, "nil", 3);
      }
      pos_arg++;
      p = close + 2;
    } else if (named_mode) {
      const char *ks = open + 2;
      const char *ke = close;
      while (ks < ke && (*ks == ' ' || *ks == '\t'))
        ks++;
      while (ke > ks && (ke[-1] == ' ' || ke[-1] == '\t'))
        ke--;
      if (is_ident_key(ks, (size_t)(ke - ks))) {
        lua_pushlstring(L, ks, (size_t)(ke - ks));
        lua_gettable(L, 2);
        if (lua_isnil(L, -1)) {
          lua_pop(L, 1);
          luaL_addlstring(&b, open, (size_t)((close + 2) - open));
        } else {
          int val_idx = lua_gettop(L);
          push_tostring(L, val_idx);
          lua_remove(L, val_idx);
          luaL_addvalue(&b);
        }
      } else {
        luaL_addlstring(&b, open, (size_t)((close + 2) - open));
      }
      p = close + 2;
    } else {
      luaL_addlstring(&b, open, (size_t)((close + 2) - open));
      p = close + 2;
    }
  }
  luaL_pushresult(&b);
  return 1;
}

/* }====================================================== */


static const luaL_Reg strlib[] = {
    {"byte", str_byte},
    {"char", str_char},
    {"contains", str_contains},
    {"count", str_count},
    {"dedent", str_dedent},
    {"dump", str_dump},
    {"ends_with", str_ends_with},
    {"find", str_find},
    {"format", str_format},
    {"gfind", gfind_nodef},
    {"gmatch", gmatch},
    {"gsub", str_gsub},
    {"index_of", str_index_of},
    {"len", str_len},
    {"lines", str_lines},
    {"lower", str_lower},
    {"ltrim", str_ltrim},
    {"match", str_match},
    {"rep", str_rep},
    {"replace", str_replace},
    {"reverse", str_reverse},
    {"rtrim", str_rtrim},
    {"split", str_split},
    {"starts_with", str_starts_with},
    {"strip_prefix", str_strip_prefix},
    {"strip_suffix", str_strip_suffix},
    {"sub", str_sub},
    {"template", str_template},
    {"trim", str_trim},
    {"upper", str_upper},
    {"words", str_words},
    {NULL, NULL}};


static void createmetatable(lua_State *L) {
  lua_createtable(L, 0, 1); /* create metatable for strings */
  lua_pushliteral(L, "");   /* dummy string */
  lua_pushvalue(L, -2);
  lua_setmetatable(L, -2);        /* set string metatable */
  lua_pop(L, 1);                  /* pop dummy string */
  lua_pushvalue(L, -2);           /* string library... */
  lua_setfield(L, -2, "__index"); /* ...is the __index metamethod */
  lua_pop(L, 1);                  /* pop metatable */
}


/*
** Open string library
*/
LUALIB_API int luaopen_string(lua_State *L) {
  luaL_register(L, LUA_STRLIBNAME, strlib);
#if defined(LUA_COMPAT_GFIND)
  lua_getfield(L, -1, "gmatch");
  lua_setfield(L, -2, "gfind");
#endif
  createmetatable(L);
  return 1;
}
