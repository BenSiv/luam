/*
** poll: procedural I/O multiplexing over poll(2) and signal fds.
**
** Functions:
**   poll.open()                      -> poller | nil, err
**   poll.add(poller, fd, events)     -> true | nil, err   ("r" | "w" | "rw")
**   poll.mod(poller, fd, events)     -> true | nil, err
**   poll.del(poller, fd)             -> true | nil, err
**   poll.wait(poller [, timeout_ms]) -> {{fd, r, w, hup, err}, ...} | nil, err
**   poll.close(poller)               -> true
**
**   poll.signal_open(sig_names)      -> sig_handle | nil, err
**   poll.signal_fd(sig_handle)       -> integer_fd
**   poll.signal_read(sig_handle)     -> sig_name | nil, err
**   poll.signal_close(sig_handle)    -> true
*/

#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifdef __linux__
#include <sys/signalfd.h>
#endif

#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>

#define LUAM_POLL_MT "luam.poll"
#define LUAM_SIG_MT "luam.poll.signal"

struct luam_poller {
  struct pollfd *fds;
  size_t len;
  size_t cap;
  int closed;
};

struct sig_entry {
  const char *name;
  int signo;
};

static const struct sig_entry sig_table[] = {
    {"HUP", SIGHUP},   {"INT", SIGINT},   {"QUIT", SIGQUIT},
    {"ALRM", SIGALRM}, {"TERM", SIGTERM}, {"CHLD", SIGCHLD},
    {"USR1", SIGUSR1}, {"USR2", SIGUSR2},
#ifdef SIGWINCH
    {"WINCH", SIGWINCH},
#endif
    {NULL, 0},
};

static int parse_sig_name(const char *s) {
  size_t i;
  if (strncmp(s, "SIG", 3) == 0) {
    s += 3;
  }
  for (i = 0; sig_table[i].name != NULL; i++) {
    if (strcmp(s, sig_table[i].name) == 0) {
      return sig_table[i].signo;
    }
  }
  return -1;
}

static const char *sig_to_name(int signo) {
  size_t i;
  for (i = 0; sig_table[i].name != NULL; i++) {
    if (sig_table[i].signo == signo) {
      return sig_table[i].name;
    }
  }
  return "UNKNOWN";
}

static short parse_events(lua_State *L, int idx) {
  const char *s = luaL_checkstring(L, idx);
  short ev = 0;
  size_t i;
  if (s[0] == '\0') {
    luaL_argerror(L, idx, "events must be 'r', 'w', or 'rw'");
  }
  for (i = 0; s[i] != '\0'; i++) {
    if (s[i] == 'r') {
      ev |= POLLIN;
    } else if (s[i] == 'w') {
      ev |= POLLOUT;
    } else {
      luaL_argerror(L, idx, "events must contain only 'r' and/or 'w'");
    }
  }
  return ev;
}

static struct luam_poller *check_poller(lua_State *L, int idx,
                                        int allow_closed) {
  struct luam_poller *p =
      (struct luam_poller *)luaL_checkudata(L, idx, LUAM_POLL_MT);
  if (!allow_closed && p->closed) {
    luaL_error(L, "attempt to use a closed poller");
  }
  return p;
}

static ssize_t find_fd_index(const struct luam_poller *p, int fd) {
  size_t i;
  for (i = 0; i < p->len; i++) {
    if (p->fds[i].fd == fd) {
      return (ssize_t)i;
    }
  }
  return -1;
}

static int l_poll_open(lua_State *L) {
  struct luam_poller *p =
      (struct luam_poller *)lua_newuserdata(L, sizeof(struct luam_poller));
  p->fds = NULL;
  p->len = 0;
  p->cap = 0;
  p->closed = 0;
  luaL_getmetatable(L, LUAM_POLL_MT);
  lua_setmetatable(L, -2);
  return 1;
}

static int l_poll_add(lua_State *L) {
  struct luam_poller *p = check_poller(L, 1, 0);
  int fd = luaL_checkint(L, 2);
  short ev = parse_events(L, 3);
  if (fd < 0) {
    lua_pushnil(L);
    lua_pushliteral(L, "invalid file descriptor");
    return 2;
  }
  if (find_fd_index(p, fd) >= 0) {
    lua_pushnil(L);
    lua_pushliteral(L, "fd already registered");
    return 2;
  }
  if (p->len == p->cap) {
    size_t next_cap = p->cap == 0 ? 16 : p->cap * 2;
    struct pollfd *grown =
        (struct pollfd *)realloc(p->fds, next_cap * sizeof(struct pollfd));
    if (grown == NULL) {
      lua_pushnil(L);
      lua_pushliteral(L, "out of memory");
      return 2;
    }
    p->fds = grown;
    p->cap = next_cap;
  }
  p->fds[p->len].fd = fd;
  p->fds[p->len].events = ev;
  p->fds[p->len].revents = 0;
  p->len++;
  lua_pushboolean(L, 1);
  return 1;
}

static int l_poll_mod(lua_State *L) {
  struct luam_poller *p = check_poller(L, 1, 0);
  int fd = luaL_checkint(L, 2);
  short ev = parse_events(L, 3);
  ssize_t idx = find_fd_index(p, fd);
  if (idx < 0) {
    lua_pushnil(L);
    lua_pushliteral(L, "fd not registered");
    return 2;
  }
  p->fds[idx].events = ev;
  p->fds[idx].revents = 0;
  lua_pushboolean(L, 1);
  return 1;
}

static int l_poll_del(lua_State *L) {
  struct luam_poller *p = check_poller(L, 1, 0);
  int fd = luaL_checkint(L, 2);
  ssize_t idx = find_fd_index(p, fd);
  if (idx < 0) {
    lua_pushnil(L);
    lua_pushliteral(L, "fd not registered");
    return 2;
  }
  if ((size_t)idx + 1 < p->len) {
    memmove(&p->fds[idx], &p->fds[idx + 1],
            (p->len - (size_t)idx - 1) * sizeof(struct pollfd));
  }
  p->len--;
  lua_pushboolean(L, 1);
  return 1;
}

static int l_poll_wait(lua_State *L) {
  struct luam_poller *p = check_poller(L, 1, 0);
  int timeout_ms = -1;
  if (!lua_isnoneornil(L, 2)) {
    lua_Number t = luaL_checknumber(L, 2);
    timeout_ms = t < 0 ? -1 : (int)t;
  }

  size_t i;
  for (i = 0; i < p->len; i++) {
    p->fds[i].revents = 0;
  }

  int ready = poll(p->fds, (nfds_t)p->len, timeout_ms);
  if (ready < 0) {
    if (errno == EINTR) {
      lua_newtable(L);
      return 1;
    }
    int en = errno;
    lua_pushnil(L);
    lua_pushstring(L, strerror(en));
    return 2;
  }

  lua_createtable(L, ready > 0 ? ready : 0, 0);
  if (ready == 0) {
    return 1;
  }

  int out_idx = 1;
  for (i = 0; i < p->len; i++) {
    short rev = p->fds[i].revents;
    if (rev != 0) {
      lua_createtable(L, 0, 5);
      lua_pushinteger(L, p->fds[i].fd);
      lua_setfield(L, -2, "fd");
      lua_pushboolean(L, (rev & POLLIN) != 0);
      lua_setfield(L, -2, "r");
      lua_pushboolean(L, (rev & POLLOUT) != 0);
      lua_setfield(L, -2, "w");
      lua_pushboolean(L, (rev & POLLHUP) != 0);
      lua_setfield(L, -2, "hup");
      lua_pushboolean(L, (rev & (POLLERR | POLLNVAL)) != 0);
      lua_setfield(L, -2, "err");
      lua_rawseti(L, -2, out_idx++);
    }
  }
  return 1;
}

static void poller_cleanup(struct luam_poller *p) {
  if (!p->closed) {
    free(p->fds);
    p->fds = NULL;
    p->len = 0;
    p->cap = 0;
    p->closed = 1;
  }
}

static int l_poll_close(lua_State *L) {
  struct luam_poller *p = check_poller(L, 1, 1);
  poller_cleanup(p);
  lua_pushboolean(L, 1);
  return 1;
}

static int l_poll_gc(lua_State *L) {
  struct luam_poller *p = check_poller(L, 1, 1);
  poller_cleanup(p);
  return 0;
}

static int l_poll_tostring(lua_State *L) {
  struct luam_poller *p = check_poller(L, 1, 1);
  if (p->closed) {
    lua_pushliteral(L, "poll (closed)");
  } else {
    lua_pushfstring(L, "poll (%d fds)", (int)p->len);
  }
  return 1;
}

/* ---- Signal descriptor handle ---- */

#ifdef __linux__

struct luam_sig {
  int sfd;
  sigset_t old_mask;
  int has_mask;
  int closed;
};

static struct luam_sig *check_sig(lua_State *L, int idx, int allow_closed) {
  struct luam_sig *sh =
      (struct luam_sig *)luaL_checkudata(L, idx, LUAM_SIG_MT);
  if (!allow_closed && sh->closed) {
    luaL_error(L, "attempt to use a closed signal handle");
  }
  return sh;
}

static void sig_cleanup(struct luam_sig *sh) {
  if (!sh->closed) {
    if (sh->sfd >= 0) {
      close(sh->sfd);
      sh->sfd = -1;
    }
    if (sh->has_mask) {
      (void)sigprocmask(SIG_SETMASK, &sh->old_mask, NULL);
      sh->has_mask = 0;
    }
    sh->closed = 1;
  }
}

static int l_signal_open(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  size_t n = lua_objlen(L, 1);
  luaL_argcheck(L, n >= 1, 1, "sig_names must be a non-empty list");

  sigset_t mask;
  sigemptyset(&mask);
  size_t i;
  for (i = 1; i <= n; i++) {
    lua_rawgeti(L, 1, (int)i);
    if (!lua_isstring(L, -1)) {
      lua_pop(L, 1);
      return luaL_argerror(L, 1, "signal names must be strings");
    }
    int signo = parse_sig_name(lua_tostring(L, -1));
    lua_pop(L, 1);
    if (signo < 0) {
      return luaL_argerror(L, 1, "unsupported signal name");
    }
    sigaddset(&mask, signo);
  }

  struct luam_sig *sh =
      (struct luam_sig *)lua_newuserdata(L, sizeof(struct luam_sig));
  sh->sfd = -1;
  sh->has_mask = 0;
  sh->closed = 1;
  luaL_getmetatable(L, LUAM_SIG_MT);
  lua_setmetatable(L, -2);

  sigset_t prev_mask;
  if (sigprocmask(SIG_BLOCK, &mask, &prev_mask) != 0) {
    int en = errno;
    lua_pushnil(L);
    lua_pushfstring(L, "sigprocmask: %s", strerror(en));
    return 2;
  }

  int sfd = signalfd(-1, &mask, SFD_NONBLOCK | SFD_CLOEXEC);
  if (sfd < 0) {
    int en = errno;
    (void)sigprocmask(SIG_SETMASK, &prev_mask, NULL);
    lua_pushnil(L);
    lua_pushfstring(L, "signalfd: %s", strerror(en));
    return 2;
  }

  sh->sfd = sfd;
  sh->old_mask = prev_mask;
  sh->has_mask = 1;
  sh->closed = 0;
  return 1;
}

static int l_signal_fd(lua_State *L) {
  struct luam_sig *sh = check_sig(L, 1, 0);
  lua_pushinteger(L, sh->sfd);
  return 1;
}

static int l_signal_read(lua_State *L) {
  struct luam_sig *sh = check_sig(L, 1, 0);
  struct signalfd_siginfo fdsi;
  for (;;) {
    ssize_t r = read(sh->sfd, &fdsi, sizeof(fdsi));
    if (r == (ssize_t)sizeof(fdsi)) {
      lua_pushstring(L, sig_to_name((int)fdsi.ssi_signo));
      return 1;
    }
    if (r < 0 && errno == EINTR) {
      continue;
    }
    if (r < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
      lua_pushnil(L);
      return 1;
    }
    int en = r < 0 ? errno : EIO;
    lua_pushnil(L);
    lua_pushstring(L, strerror(en));
    return 2;
  }
}

#else /* POSIX self-pipe fallback */

static volatile int selfpipe_wr_fd = -1;

static void selfpipe_handler(int signo) {
  int saved = errno;
  int wr = selfpipe_wr_fd;
  if (wr >= 0) {
    unsigned char b = (unsigned char)(signo & 0xff);
    ssize_t r = write(wr, &b, 1);
    (void)r;
  }
  errno = saved;
}

struct luam_sig {
  int rd_fd;
  int wr_fd;
  int signos[16];
  struct sigaction old_sa[16];
  size_t n_sigs;
  int closed;
};

static struct luam_sig *check_sig(lua_State *L, int idx, int allow_closed) {
  struct luam_sig *sh =
      (struct luam_sig *)luaL_checkudata(L, idx, LUAM_SIG_MT);
  if (!allow_closed && sh->closed) {
    luaL_error(L, "attempt to use a closed signal handle");
  }
  return sh;
}

static void sig_cleanup(struct luam_sig *sh) {
  if (!sh->closed) {
    size_t i;
    selfpipe_wr_fd = -1;
    for (i = 0; i < sh->n_sigs; i++) {
      (void)sigaction(sh->signos[i], &sh->old_sa[i], NULL);
    }
    if (sh->rd_fd >= 0) {
      close(sh->rd_fd);
      sh->rd_fd = -1;
    }
    if (sh->wr_fd >= 0) {
      close(sh->wr_fd);
      sh->wr_fd = -1;
    }
    sh->closed = 1;
  }
}

static void set_fd_nonblock_cloexec(int fd) {
  int fl = fcntl(fd, F_GETFL, 0);
  if (fl >= 0) {
    (void)fcntl(fd, F_SETFL, fl | O_NONBLOCK);
  }
  int fdfl = fcntl(fd, F_GETFD, 0);
  if (fdfl >= 0) {
    (void)fcntl(fd, F_SETFD, fdfl | FD_CLOEXEC);
  }
}

static int l_signal_open(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  size_t n = lua_objlen(L, 1);
  luaL_argcheck(L, n >= 1 && n <= 16, 1, "sig_names must have 1..16 entries");
  if (selfpipe_wr_fd >= 0) {
    lua_pushnil(L);
    lua_pushliteral(L, "a signal handle is already active");
    return 2;
  }

  int signos[16];
  size_t i;
  for (i = 1; i <= n; i++) {
    lua_rawgeti(L, 1, (int)i);
    if (!lua_isstring(L, -1)) {
      lua_pop(L, 1);
      return luaL_argerror(L, 1, "signal names must be strings");
    }
    int signo = parse_sig_name(lua_tostring(L, -1));
    lua_pop(L, 1);
    if (signo < 0) {
      return luaL_argerror(L, 1, "unsupported signal name");
    }
    signos[i - 1] = signo;
  }

  struct luam_sig *sh =
      (struct luam_sig *)lua_newuserdata(L, sizeof(struct luam_sig));
  memset(sh, 0, sizeof(*sh));
  sh->rd_fd = -1;
  sh->wr_fd = -1;
  sh->closed = 1;
  luaL_getmetatable(L, LUAM_SIG_MT);
  lua_setmetatable(L, -2);

  int pfd[2];
  if (pipe(pfd) != 0) {
    int en = errno;
    lua_pushnil(L);
    lua_pushfstring(L, "pipe: %s", strerror(en));
    return 2;
  }
  set_fd_nonblock_cloexec(pfd[0]);
  set_fd_nonblock_cloexec(pfd[1]);

  sh->rd_fd = pfd[0];
  sh->wr_fd = pfd[1];
  selfpipe_wr_fd = pfd[1];
  sh->closed = 0;

  struct sigaction sa;
  memset(&sa, 0, sizeof(sa));
  sa.sa_handler = selfpipe_handler;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = SA_NOCLDSTOP;

  for (i = 0; i < n; i++) {
    sh->signos[i] = signos[i];
    if (sigaction(signos[i], &sa, &sh->old_sa[i]) != 0) {
      int en = errno;
      sh->n_sigs = i;
      sig_cleanup(sh);
      lua_pushnil(L);
      lua_pushfstring(L, "sigaction: %s", strerror(en));
      return 2;
    }
    sh->n_sigs = i + 1;
  }
  return 1;
}

static int l_signal_fd(lua_State *L) {
  struct luam_sig *sh = check_sig(L, 1, 0);
  lua_pushinteger(L, sh->rd_fd);
  return 1;
}

static int l_signal_read(lua_State *L) {
  struct luam_sig *sh = check_sig(L, 1, 0);
  unsigned char b = 0;
  for (;;) {
    ssize_t r = read(sh->rd_fd, &b, 1);
    if (r == 1) {
      lua_pushstring(L, sig_to_name((int)b));
      return 1;
    }
    if (r < 0 && errno == EINTR) {
      continue;
    }
    if (r < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
      lua_pushnil(L);
      return 1;
    }
    int en = r < 0 ? errno : EIO;
    lua_pushnil(L);
    lua_pushstring(L, strerror(en));
    return 2;
  }
}

#endif /* __linux__ */

static int l_signal_close(lua_State *L) {
  struct luam_sig *sh = check_sig(L, 1, 1);
  sig_cleanup(sh);
  lua_pushboolean(L, 1);
  return 1;
}

static int l_signal_gc(lua_State *L) {
  struct luam_sig *sh = check_sig(L, 1, 1);
  sig_cleanup(sh);
  return 0;
}

static int l_signal_tostring(lua_State *L) {
  struct luam_sig *sh = check_sig(L, 1, 1);
  if (sh->closed) {
    lua_pushliteral(L, "poll.signal (closed)");
  } else {
    lua_pushliteral(L, "poll.signal");
  }
  return 1;
}

static const struct luaL_Reg polllib[] = {
    {"open", l_poll_open},
    {"add", l_poll_add},
    {"mod", l_poll_mod},
    {"del", l_poll_del},
    {"wait", l_poll_wait},
    {"close", l_poll_close},
    {"signal_open", l_signal_open},
    {"signal_fd", l_signal_fd},
    {"signal_read", l_signal_read},
    {"signal_close", l_signal_close},
    {NULL, NULL},
};

LUALIB_API int luaopen_poll(lua_State *L) {
  if (luaL_newmetatable(L, LUAM_POLL_MT)) {
    lua_pushcfunction(L, l_poll_gc);
    lua_setfield(L, -2, "__gc");
    lua_pushcfunction(L, l_poll_tostring);
    lua_setfield(L, -2, "__tostring");
  }
  lua_pop(L, 1);

  if (luaL_newmetatable(L, LUAM_SIG_MT)) {
    lua_pushcfunction(L, l_signal_gc);
    lua_setfield(L, -2, "__gc");
    lua_pushcfunction(L, l_signal_tostring);
    lua_setfield(L, -2, "__tostring");
  }
  lua_pop(L, 1);

  lua_newtable(L);
  luaL_register(L, NULL, polllib);
  return 1;
}
