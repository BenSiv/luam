/*
** $Id: llex.c,v 2.20.1.2 2009/11/23 14:58:22 roberto Exp $
** Lexical Analyzer
** See Copyright Notice in lua.h
*/

#include <ctype.h>
#include <locale.h>
#include <string.h>

#define llex_c
#define LUA_CORE

#include "lua.h"

#include "ldo.h"
#include "llex.h"
#include "lobject.h"
#include "lparser.h"
#include "lstate.h"
#include "lstring.h"
#include "ltable.h"
#include "lzio.h"

#define next(ls) (ls->current = zgetc(ls->z))

#define currIsNewline(ls) (ls->current == '\n' || ls->current == '\r')

/* ORDER RESERVED */
const char *const luaX_tokens[] = {
    "and",   "break",    "do",       "else",     "elseif", "end",
    "false", "for",      "function", "if",       "in",     "const",
    "nil",   "not",      "or",       "return",   "then",   "true",
    "while", "..",       "...",      "==",       ">=",     "<=",
    "!=",    "<number>", "<name>",   "<string>", "<eof>",  NULL};

#define save_and_next(ls) (save(ls, ls->current), next(ls))

static void save(LexState *ls, int c) {
  Mbuffer *b = ls->buff;
  if (b->n + 1 > b->buffsize) {
    size_t newsize;
    if (b->buffsize >= MAX_SIZET / 2)
      luaX_lexerror(ls, "lexical element too long", 0);
    newsize = b->buffsize * 2;
    luaZ_resizebuffer(ls->L, b, newsize);
  }
  b->buffer[b->n++] = cast(char, c);
}

void luaX_init(lua_State *L) {
  int i;
  for (i = 0; i < NUM_RESERVED; i++) {
    TString *ts = luaS_new(L, luaX_tokens[i]);
    luaS_fix(ts); /* reserved words are never collected */
    lua_assert(strlen(luaX_tokens[i]) + 1 <= TOKEN_LEN);
    ts->tsv.reserved = cast_byte(i + 1); /* reserved word */
  }
}

#define MAXSRC 80

const char *luaX_token2str(LexState *ls, int token) {
  if (token < FIRST_RESERVED) {
    lua_assert(token == cast(unsigned char, token));
    return (iscntrl(token)) ? luaO_pushfstring(ls->L, "char(%d)", token)
                            : luaO_pushfstring(ls->L, "%c", token);
  } else
    return luaX_tokens[token - FIRST_RESERVED];
}

static const char *txtToken(LexState *ls, int token) {
  switch (token) {
  case TK_NAME:
  case TK_STRING:
  case TK_NUMBER:
    save(ls, '\0');
    return luaZ_buffer(ls->buff);
  default:
    return luaX_token2str(ls, token);
  }
}

void luaX_lexerror(LexState *ls, const char *msg, int token) {
  char buff[MAXSRC];
  luaO_chunkid(buff, getstr(ls->source), MAXSRC);
  msg = luaO_pushfstring(ls->L, "%s:%d: %s", buff, ls->linenumber, msg);
  if (token)
    luaO_pushfstring(ls->L, "%s near " LUA_QS, msg, txtToken(ls, token));
  luaD_throw(ls->L, LUA_ERRSYNTAX);
}

void luaX_syntaxerror(LexState *ls, const char *msg) {
  luaX_lexerror(ls, msg, ls->t.token);
}

TString *luaX_newstring(LexState *ls, const char *str, size_t l) {
  lua_State *L = ls->L;
  TString *ts = luaS_newlstr(L, str, l);
  TValue *o = luaH_setstr(L, ls->fs->h, ts); /* entry for `str' */
  if (ttisnil(o)) {
    setbvalue(o, 1); /* make sure `str' will not be collected */
    luaC_checkGC(L);
  }
  return ts;
}

static void inclinenumber(LexState *ls) {
  int old = ls->current;
  lua_assert(currIsNewline(ls));
  next(ls); /* skip `\n' or `\r' */
  if (currIsNewline(ls) && ls->current != old)
    next(ls); /* skip `\n\r' or `\r\n' */
  if (++ls->linenumber >= MAX_INT)
    luaX_syntaxerror(ls, "chunk has too many lines");
}

void luaX_setinput(lua_State *L, LexState *ls, ZIO *z, TString *source) {
  ls->decpoint = '.';
  ls->L = L;
  ls->lookahead.token = TK_EOS; /* no look-ahead token */
  ls->z = z;
  ls->fs = NULL;
  ls->linenumber = 1;
  ls->lastline = 1;
  ls->source = source;
  luaZ_resizebuffer(ls->L, ls->buff, LUA_MINBUFFER); /* initialize buffer */
  next(ls);                                          /* read first char */
}

/*
** =======================================================
** LEXICAL ANALYZER
** =======================================================
*/

static int check_next(LexState *ls, const char *set) {
  if (!strchr(set, ls->current))
    return 0;
  save_and_next(ls);
  return 1;
}

static void buffreplace(LexState *ls, char from, char to) {
  size_t n = luaZ_bufflen(ls->buff);
  char *p = luaZ_buffer(ls->buff);
  while (n--)
    if (p[n] == from)
      p[n] = to;
}

static void trydecpoint(LexState *ls, SemInfo *seminfo) {
  /* format error: try to update decimal point separator */
  struct lconv *cv = localeconv();
  char old = ls->decpoint;
  ls->decpoint = (cv ? cv->decimal_point[0] : '.');
  buffreplace(ls, old, ls->decpoint); /* try updated decimal separator */
  if (!luaO_str2d(luaZ_buffer(ls->buff), &seminfo->r)) {
    /* format error with correct decimal point: no more options */
    buffreplace(ls, ls->decpoint, '.'); /* undo change (for error message) */
    luaX_lexerror(ls, "malformed number", TK_NUMBER);
  }
}

/* LUA_NUMBER */
static void read_numeral(LexState *ls, SemInfo *seminfo) {
  lua_assert(isdigit(ls->current));
  do {
    save_and_next(ls);
  } while (isdigit(ls->current) || ls->current == '.');
  if (check_next(ls, "Ee")) /* `E'? */
    check_next(ls, "+-");   /* optional exponent sign */
  while (isalnum(ls->current) || ls->current == '_')
    save_and_next(ls);
  save(ls, '\0');
  buffreplace(ls, '.', ls->decpoint); /* follow locale for decimal point */
  if (!luaO_str2d(luaZ_buffer(ls->buff), &seminfo->r)) /* format error? */
    trydecpoint(ls, seminfo); /* try to update decimal point separator */
}

static int hexvalue(int c) {
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return c - 'a' + 10;
  if (c >= 'A' && c <= 'F')
    return c - 'A' + 10;
  return -1;
}

static void save_utf8(LexState *ls, unsigned long cp) {
  if (cp <= 0x7FUL) {
    save(ls, (int)cp);
  } else if (cp <= 0x7FFUL) {
    save(ls, (int)(0xC0UL | (cp >> 6)));
    save(ls, (int)(0x80UL | (cp & 0x3FUL)));
  } else if (cp <= 0xFFFFUL) {
    save(ls, (int)(0xE0UL | (cp >> 12)));
    save(ls, (int)(0x80UL | ((cp >> 6) & 0x3FUL)));
    save(ls, (int)(0x80UL | (cp & 0x3FUL)));
  } else {
    save(ls, (int)(0xF0UL | (cp >> 18)));
    save(ls, (int)(0x80UL | ((cp >> 12) & 0x3FUL)));
    save(ls, (int)(0x80UL | ((cp >> 6) & 0x3FUL)));
    save(ls, (int)(0x80UL | (cp & 0x3FUL)));
  }
}

static void read_escape(LexState *ls) {
  int c;
  next(ls); /* skip '\\' */
  switch (ls->current) {
  case 'a':
    c = '\a';
    goto read_save;
  case 'b':
    c = '\b';
    goto read_save;
  case 'f':
    c = '\f';
    goto read_save;
  case 'n':
    c = '\n';
    goto read_save;
  case 'r':
    c = '\r';
    goto read_save;
  case 't':
    c = '\t';
    goto read_save;
  case 'v':
    c = '\v';
    goto read_save;
  case '\\':
  case '"':
  case '\'':
    c = ls->current;
    goto read_save;
  case '0':
    next(ls);
    if (ls->current >= '0' && ls->current <= '9') {
      save(ls, '\\');
      save(ls, '0');
      save(ls, ls->current);
      luaX_lexerror(ls, "decimal escape sequence not supported; use \\xXX",
                    TK_STRING);
    }
    save(ls, '\0');
    return;
  case 'x': {
    int h1, h2;
    next(ls);
    h1 = hexvalue(ls->current);
    if (h1 < 0)
      luaX_lexerror(ls, "hexadecimal digit expected in \\xXX escape",
                    TK_STRING);
    next(ls);
    h2 = hexvalue(ls->current);
    if (h2 < 0)
      luaX_lexerror(ls, "hexadecimal digit expected in \\xXX escape",
                    TK_STRING);
    next(ls);
    save(ls, (h1 << 4) | h2);
    return;
  }
  case 'u': {
    unsigned long cp = 0;
    int digits = 0;
    next(ls);
    if (ls->current != '{')
      luaX_lexerror(ls, "missing '{' in \\u{xxxx} escape", TK_STRING);
    next(ls);
    while (hexvalue(ls->current) >= 0) {
      cp = (cp << 4) | (unsigned long)hexvalue(ls->current);
      digits++;
      if (digits > 6 || cp > 0x10FFFFUL)
        luaX_lexerror(ls, "UTF-8 value too large", TK_STRING);
      next(ls);
    }
    if (digits == 0 || ls->current != '}')
      luaX_lexerror(ls, "invalid \\u{xxxx} escape", TK_STRING);
    next(ls);
    save_utf8(ls, cp);
    return;
  }
  case 'z':
    next(ls);
    while (ls->current != EOZ && isspace(ls->current)) {
      if (currIsNewline(ls))
        inclinenumber(ls);
      else
        next(ls);
    }
    return;
  case '\n':
  case '\r':
    save(ls, '\n');
    inclinenumber(ls);
    return;
  case EOZ:
    return; /* caller handles EOZ with unfinished string error */
  default:
    save(ls, '\\');
    if (ls->current != EOZ)
      save(ls, ls->current);
    if (ls->current >= '1' && ls->current <= '9')
      luaX_lexerror(ls, "decimal escape sequence not supported; use \\xXX",
                    TK_STRING);
    luaX_lexerror(ls, "invalid escape sequence", TK_STRING);
    return;
  }
read_save:
  save(ls, c);
  next(ls);
}

static void read_triple_quote_string(LexState *ls, SemInfo *seminfo) {
  /* buffer already contains opening """ */
  for (;;) {
    switch (ls->current) {
    case EOZ:
      luaX_lexerror(ls, "unfinished long string", TK_EOS);
      break;
    case '"': {
      save_and_next(ls);
      if (ls->current == '"') {
        save_and_next(ls);
        if (ls->current == '"') {
          save_and_next(ls);
          goto endloop;
        }
      }
      break;
    }
    case '\\':
      read_escape(ls);
      break;
    case '\n':
    case '\r':
      save(ls, '\n');
      inclinenumber(ls);
      break;
    default:
      save_and_next(ls);
      break;
    }
  }
endloop:
  seminfo->ts =
      luaX_newstring(ls, luaZ_buffer(ls->buff) + 3, luaZ_bufflen(ls->buff) - 6);
}

static void read_string(LexState *ls, SemInfo *seminfo) {
  /* buffer already contains opening " */
  while (ls->current != '"') {
    switch (ls->current) {
    case EOZ:
      luaX_lexerror(ls, "unfinished string", TK_EOS);
      continue; /* to avoid warnings */
    case '\n':
    case '\r':
      luaX_lexerror(ls, "unfinished string", TK_STRING);
      continue; /* to avoid warnings */
    case '\\':
      read_escape(ls);
      continue;
    default:
      save_and_next(ls);
      continue;
    }
  }
  save_and_next(ls); /* skip closing " */
  seminfo->ts =
      luaX_newstring(ls, luaZ_buffer(ls->buff) + 1, luaZ_bufflen(ls->buff) - 2);
}

static int llex(LexState *ls, SemInfo *seminfo) {
  luaZ_resetbuffer(ls->buff);
  for (;;) {
    switch (ls->current) {
    case '\n':
    case '\r': {
      inclinenumber(ls);
      continue;
    }
    case '-': {
      next(ls);
      if (ls->current != '-')
        return '-';
      /* else is a comment */
      next(ls);
      /* no --[[ long comment ]] form: [[ ]] itself was repurposed for
         triple-quoted strings, so -- is always a single-line comment */
      while (!currIsNewline(ls) && ls->current != EOZ)
        next(ls);
      continue;
    }
    case '[': {
      next(ls);
      return '[';
    }
    case '=': {
      next(ls);
      if (ls->current != '=')
        return '=';
      else {
        next(ls);
        return TK_EQ;
      }
    }
    case '<': {
      next(ls);
      if (ls->current != '=')
        return '<';
      else {
        next(ls);
        return TK_LE;
      }
    }

    case '>': {
      next(ls);
      if (ls->current != '=')
        return '>';
      else {
        next(ls);
        return TK_GE;
      }
    }
    case '!': {
      next(ls);
      if (ls->current != '=')
        return '!';
      else {
        next(ls);
        return TK_NE;
      }
    }
    case '"': {
      save_and_next(ls);
      if (ls->current == '"') {
        save_and_next(ls);
        if (ls->current == '"') {
          save_and_next(ls);
          read_triple_quote_string(ls, seminfo);
          return TK_STRING;
        }
        seminfo->ts = luaX_newstring(ls, "", 0);
        return TK_STRING;
      }
      read_string(ls, seminfo);
      return TK_STRING;
    }
    case '.': {
      save_and_next(ls);
      if (check_next(ls, ".")) {
        if (check_next(ls, "."))
          return TK_DOTS; /* ... */
        else
          return TK_CONCAT; /* .. */
      } else if (!isdigit(ls->current))
        return '.';
      else {
        read_numeral(ls, seminfo);
        return TK_NUMBER;
      }
    }
    case EOZ: {
      return TK_EOS;
    }
    default: {
      if (isspace(ls->current)) {
        lua_assert(!currIsNewline(ls));
        next(ls);
        continue;
      } else if (isdigit(ls->current)) {
        read_numeral(ls, seminfo);
        return TK_NUMBER;
      } else if (isalpha(ls->current) || ls->current == '_') {
        /* identifier or reserved word */
        TString *ts;
        do {
          save_and_next(ls);
        } while (isalnum(ls->current) || ls->current == '_');
        ts = luaX_newstring(ls, luaZ_buffer(ls->buff), luaZ_bufflen(ls->buff));
        if (ts->tsv.reserved > 0) /* reserved word? */
          return ts->tsv.reserved - 1 + FIRST_RESERVED;
        else {
          seminfo->ts = ts;
          return TK_NAME;
        }
      } else {
        int c = ls->current;
        next(ls);
        return c; /* single-char tokens (+ - / ...) */
      }
    }
    }
  }
}

void luaX_next(LexState *ls) {
  ls->lastline = ls->linenumber;
  if (ls->lookahead.token != TK_EOS) { /* is there a look-ahead token? */
    ls->t = ls->lookahead;             /* use this one */
    ls->lookahead.token = TK_EOS;      /* and discharge it */
  } else
    ls->t.token = llex(ls, &ls->t.seminfo); /* read next token */
}

void luaX_lookahead(LexState *ls) {
  lua_assert(ls->lookahead.token == TK_EOS);
  ls->lookahead.token = llex(ls, &ls->lookahead.seminfo);
}
