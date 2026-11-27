/*
** net: procedural TCP and AF_UNIX domain sockets with non-blocking support.
**
** Functions:
**   net.listen_tcp(host, port [, opts])      -> listener | nil, err
**   net.listen_unix(path [, opts])           -> listener | nil, err
**   net.local_port(sock)                     -> integer_port | nil, err
**   net.accept(listener)                     -> conn, peer_str | nil, err
**   net.connect_tcp(host, port [, timeout])  -> conn | nil, err
**   net.connect_unix(path [, timeout])       -> conn | nil, err
**   net.fd(sock)                             -> integer_fd
**   net.set_nonblocking(sock, bool)          -> true | nil, err
**   net.read(conn [, max_bytes])             -> bytes, eof_bool | nil, err
**   net.write(conn, bytes [, start_idx])     -> n_written | nil, err
**   net.close(sock)                          -> true
*/

#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>

#define LUAM_NET_MT "luam.net.sock"

struct luam_sock {
  int fd;
  int nonblocking;
  int closed;
};

static int64_t monotonic_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int64_t)ts.tv_sec * 1000 + (int64_t)(ts.tv_nsec / 1000000L);
}

static int set_cloexec(int fd) {
  int fl = fcntl(fd, F_GETFD, 0);
  if (fl < 0) {
    return -1;
  }
  return fcntl(fd, F_SETFD, fl | FD_CLOEXEC);
}

static int apply_nonblocking(int fd, int enable) {
  int fl = fcntl(fd, F_GETFL, 0);
  if (fl < 0) {
    return -1;
  }
  int next = enable ? (fl | O_NONBLOCK) : (fl & ~O_NONBLOCK);
  return fcntl(fd, F_SETFL, next);
}

static void enable_nodelay(int fd) {
  int one = 1;
  (void)setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
}

static struct luam_sock *new_sock_udata(lua_State *L) {
  struct luam_sock *s =
      (struct luam_sock *)lua_newuserdata(L, sizeof(struct luam_sock));
  s->fd = -1;
  s->nonblocking = 0;
  s->closed = 1;
  luaL_getmetatable(L, LUAM_NET_MT);
  lua_setmetatable(L, -2);
  return s;
}

static struct luam_sock *check_sock(lua_State *L, int idx, int allow_closed) {
  struct luam_sock *s =
      (struct luam_sock *)luaL_checkudata(L, idx, LUAM_NET_MT);
  if (!allow_closed && s->closed) {
    luaL_error(L, "attempt to use a closed socket");
  }
  return s;
}

static void sock_cleanup(struct luam_sock *s) {
  if (!s->closed) {
    if (s->fd >= 0) {
      close(s->fd);
      s->fd = -1;
    }
    s->closed = 1;
  }
}

static void parse_listen_opts(lua_State *L, int idx, int *backlog,
                              int *nonblocking, int *mode_out) {
  *backlog = 128;
  *nonblocking = 0;
  *mode_out = -1;
  if (lua_isnoneornil(L, idx)) {
    return;
  }
  luaL_checktype(L, idx, LUA_TTABLE);

  lua_getfield(L, idx, "backlog");
  if (!lua_isnil(L, -1)) {
    int b = luaL_checkint(L, -1);
    if (b > 0) {
      *backlog = b;
    }
  }
  lua_pop(L, 1);

  lua_getfield(L, idx, "nonblocking");
  *nonblocking = lua_toboolean(L, -1);
  lua_pop(L, 1);

  lua_getfield(L, idx, "mode");
  if (!lua_isnil(L, -1)) {
    *mode_out = luaL_checkint(L, -1);
  }
  lua_pop(L, 1);
}

static int l_listen_tcp(lua_State *L) {
  const char *host = luaL_checkstring(L, 1);
  int port = luaL_checkint(L, 2);
  int backlog = 128, nonblocking = 0, unused_mode = -1;
  luaL_argcheck(L, port >= 0 && port <= 65535, 2, "port must be 0..65535");
  parse_listen_opts(L, 3, &backlog, &nonblocking, &unused_mode);

  struct luam_sock *s = new_sock_udata(L);

  char port_str[16];
  snprintf(port_str, sizeof(port_str), "%d", port);

  struct addrinfo hints, *res = NULL, *rp;
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = AI_PASSIVE;

  int gai = getaddrinfo(host[0] == '\0' ? NULL : host, port_str, &hints, &res);
  if (gai != 0) {
    lua_pushnil(L);
    lua_pushfstring(L, "getaddrinfo '%s:%d': %s", host, port,
                    gai_strerror(gai));
    return 2;
  }

  int fd = -1;
  int last_err = EADDRNOTAVAIL;
  for (rp = res; rp != NULL; rp = rp->ai_next) {
    fd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
    if (fd < 0) {
      last_err = errno;
      continue;
    }
    (void)set_cloexec(fd);
    int one = 1;
    (void)setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    if (bind(fd, rp->ai_addr, rp->ai_addrlen) == 0 &&
        listen(fd, backlog) == 0) {
      break;
    }
    last_err = errno;
    close(fd);
    fd = -1;
  }
  freeaddrinfo(res);

  if (fd < 0) {
    lua_pushnil(L);
    lua_pushfstring(L, "listen '%s:%d': %s", host, port, strerror(last_err));
    return 2;
  }

  if (nonblocking && apply_nonblocking(fd, 1) < 0) {
    int en = errno;
    close(fd);
    lua_pushnil(L);
    lua_pushstring(L, strerror(en));
    return 2;
  }

  s->fd = fd;
  s->nonblocking = nonblocking;
  s->closed = 0;
  return 1;
}

static int l_listen_unix(lua_State *L) {
  size_t path_len = 0;
  const char *path = luaL_checklstring(L, 1, &path_len);
  int backlog = 128, nonblocking = 0, mode = -1;
  parse_listen_opts(L, 2, &backlog, &nonblocking, &mode);

  struct sockaddr_un sun_addr;
  if (path_len == 0 || path_len >= sizeof(sun_addr.sun_path) ||
      memchr(path, '\0', path_len) != NULL) {
    lua_pushnil(L);
    lua_pushliteral(L, "unix socket path invalid or too long");
    return 2;
  }

  struct stat st;
  if (lstat(path, &st) == 0) {
    /* Only unlink pre-existing socket inodes; refuse to overwrite files/dirs. */
    if (!S_ISSOCK(st.st_mode)) {
      lua_pushnil(L);
      lua_pushfstring(L, "%s: path exists and is not a socket", path);
      return 2;
    }
    if (unlink(path) != 0 && errno != ENOENT) {
      int en = errno;
      lua_pushnil(L);
      lua_pushfstring(L, "unlink '%s': %s", path, strerror(en));
      return 2;
    }
  }

  struct luam_sock *s = new_sock_udata(L);

  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    int en = errno;
    lua_pushnil(L);
    lua_pushfstring(L, "socket: %s", strerror(en));
    return 2;
  }
  (void)set_cloexec(fd);

  memset(&sun_addr, 0, sizeof(sun_addr));
  sun_addr.sun_family = AF_UNIX;
  memcpy(sun_addr.sun_path, path, path_len + 1);

  if (bind(fd, (struct sockaddr *)&sun_addr, sizeof(sun_addr)) != 0) {
    int en = errno;
    close(fd);
    lua_pushnil(L);
    lua_pushfstring(L, "bind '%s': %s", path, strerror(en));
    return 2;
  }

  if (mode >= 0 && chmod(path, (mode_t)mode) != 0) {
    int en = errno;
    close(fd);
    (void)unlink(path);
    lua_pushnil(L);
    lua_pushfstring(L, "chmod '%s': %s", path, strerror(en));
    return 2;
  }

  if (listen(fd, backlog) != 0) {
    int en = errno;
    close(fd);
    (void)unlink(path);
    lua_pushnil(L);
    lua_pushfstring(L, "listen '%s': %s", path, strerror(en));
    return 2;
  }

  if (nonblocking && apply_nonblocking(fd, 1) < 0) {
    int en = errno;
    close(fd);
    lua_pushnil(L);
    lua_pushstring(L, strerror(en));
    return 2;
  }

  s->fd = fd;
  s->nonblocking = nonblocking;
  s->closed = 0;
  return 1;
}

static int l_local_port(lua_State *L) {
  struct luam_sock *s = check_sock(L, 1, 0);
  struct sockaddr_storage ss;
  socklen_t slen = sizeof(ss);
  if (getsockname(s->fd, (struct sockaddr *)&ss, &slen) != 0) {
    int en = errno;
    lua_pushnil(L);
    lua_pushstring(L, strerror(en));
    return 2;
  }
  if (ss.ss_family == AF_INET) {
    struct sockaddr_in *sin = (struct sockaddr_in *)&ss;
    lua_pushinteger(L, ntohs(sin->sin_port));
    return 1;
  }
  if (ss.ss_family == AF_INET6) {
    struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)&ss;
    lua_pushinteger(L, ntohs(sin6->sin6_port));
    return 1;
  }
  lua_pushnil(L);
  lua_pushliteral(L, "socket has no TCP port");
  return 2;
}

static void format_peer(const struct sockaddr_storage *ss, char *buf,
                        size_t buflen) {
  if (ss->ss_family == AF_INET) {
    const struct sockaddr_in *sin = (const struct sockaddr_in *)ss;
    char ip[INET_ADDRSTRLEN];
    if (inet_ntop(AF_INET, &sin->sin_addr, ip, sizeof(ip)) != NULL) {
      snprintf(buf, buflen, "%s:%d", ip, (int)ntohs(sin->sin_port));
      return;
    }
  } else if (ss->ss_family == AF_INET6) {
    const struct sockaddr_in6 *sin6 = (const struct sockaddr_in6 *)ss;
    char ip[INET6_ADDRSTRLEN];
    if (inet_ntop(AF_INET6, &sin6->sin6_addr, ip, sizeof(ip)) != NULL) {
      snprintf(buf, buflen, "[%s]:%d", ip, (int)ntohs(sin6->sin6_port));
      return;
    }
  } else if (ss->ss_family == AF_UNIX) {
    snprintf(buf, buflen, "unix");
    return;
  }
  snprintf(buf, buflen, "unknown");
}

static int l_accept(lua_State *L) {
  struct luam_sock *srv = check_sock(L, 1, 0);
  struct sockaddr_storage ss;
  socklen_t slen = sizeof(ss);
  int cfd = -1;

  for (;;) {
    memset(&ss, 0, sizeof(ss));
    slen = sizeof(ss);
    cfd = accept(srv->fd, (struct sockaddr *)&ss, &slen);
    if (cfd >= 0) {
      break;
    }
    if (errno == EINTR) {
      continue;
    }
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      lua_pushnil(L);
      lua_pushliteral(L, "again");
      return 2;
    }
    int en = errno;
    lua_pushnil(L);
    lua_pushstring(L, strerror(en));
    return 2;
  }

  (void)set_cloexec(cfd);
  if (ss.ss_family == AF_INET || ss.ss_family == AF_INET6) {
    enable_nodelay(cfd);
  }
  if (srv->nonblocking) {
    (void)apply_nonblocking(cfd, 1);
  }

  struct luam_sock *conn = new_sock_udata(L);
  conn->fd = cfd;
  conn->nonblocking = srv->nonblocking;
  conn->closed = 0;

  char peer[128];
  format_peer(&ss, peer, sizeof(peer));
  lua_pushstring(L, peer);
  return 2;
}

static int connect_with_timeout(int fd, const struct sockaddr *addr,
                                socklen_t addrlen, int64_t deadline_ms) {
  if (deadline_ms < 0) {
    for (;;) {
      if (connect(fd, addr, addrlen) == 0) {
        return 0;
      }
      if (errno == EINTR) {
        continue;
      }
      return errno;
    }
  }

  if (apply_nonblocking(fd, 1) < 0) {
    return errno;
  }
  int rc = connect(fd, addr, addrlen);
  if (rc == 0) {
    (void)apply_nonblocking(fd, 0);
    return 0;
  }
  if (errno != EINPROGRESS && errno != EINTR) {
    int en = errno;
    (void)apply_nonblocking(fd, 0);
    return en;
  }

  for (;;) {
    int64_t rem = deadline_ms - monotonic_ms();
    if (rem <= 0) {
      return ETIMEDOUT;
    }
    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = POLLOUT;
    pfd.revents = 0;
    int wait_ms = rem > 60000 ? 60000 : (int)rem;
    int pr = poll(&pfd, 1, wait_ms);
    if (pr < 0) {
      if (errno == EINTR) {
        continue;
      }
      return errno;
    }
    if (pr == 0) {
      continue;
    }
    int so_err = 0;
    socklen_t elen = sizeof(so_err);
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &so_err, &elen) < 0) {
      return errno;
    }
    if (so_err != 0) {
      return so_err;
    }
    if (apply_nonblocking(fd, 0) < 0) {
      return errno;
    }
    return 0;
  }
}

static int l_connect_tcp(lua_State *L) {
  const char *host = luaL_checkstring(L, 1);
  int port = luaL_checkint(L, 2);
  int64_t deadline_ms = -1;
  luaL_argcheck(L, port >= 1 && port <= 65535, 2, "port must be 1..65535");
  if (!lua_isnoneornil(L, 3)) {
    lua_Number t = luaL_checknumber(L, 3);
    if (t > 0) {
      int64_t ms = (int64_t)t;
      deadline_ms = monotonic_ms() + (ms < 1 ? 1 : ms);
    }
  }

  struct luam_sock *conn = new_sock_udata(L);

  char port_str[16];
  snprintf(port_str, sizeof(port_str), "%d", port);

  struct addrinfo hints, *res = NULL, *rp;
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;

  int gai = getaddrinfo(host, port_str, &hints, &res);
  if (gai != 0) {
    lua_pushnil(L);
    lua_pushfstring(L, "getaddrinfo '%s:%d': %s", host, port,
                    gai_strerror(gai));
    return 2;
  }

  int fd = -1;
  int last_err = ECONNREFUSED;
  for (rp = res; rp != NULL; rp = rp->ai_next) {
    fd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
    if (fd < 0) {
      last_err = errno;
      continue;
    }
    (void)set_cloexec(fd);
    enable_nodelay(fd);
    last_err =
        connect_with_timeout(fd, rp->ai_addr, rp->ai_addrlen, deadline_ms);
    if (last_err == 0) {
      break;
    }
    close(fd);
    fd = -1;
    if (last_err == ETIMEDOUT) {
      break;
    }
  }
  freeaddrinfo(res);

  if (fd < 0) {
    lua_pushnil(L);
    lua_pushfstring(L, "connect '%s:%d': %s", host, port, strerror(last_err));
    return 2;
  }

  conn->fd = fd;
  conn->nonblocking = 0;
  conn->closed = 0;
  return 1;
}

static int l_connect_unix(lua_State *L) {
  size_t path_len = 0;
  const char *path = luaL_checklstring(L, 1, &path_len);
  int64_t deadline_ms = -1;
  if (!lua_isnoneornil(L, 2)) {
    lua_Number t = luaL_checknumber(L, 2);
    if (t > 0) {
      int64_t ms = (int64_t)t;
      deadline_ms = monotonic_ms() + (ms < 1 ? 1 : ms);
    }
  }

  struct sockaddr_un sun_addr;
  if (path_len == 0 || path_len >= sizeof(sun_addr.sun_path) ||
      memchr(path, '\0', path_len) != NULL) {
    lua_pushnil(L);
    lua_pushliteral(L, "unix socket path invalid or too long");
    return 2;
  }

  struct luam_sock *conn = new_sock_udata(L);

  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    int en = errno;
    lua_pushnil(L);
    lua_pushfstring(L, "socket: %s", strerror(en));
    return 2;
  }
  (void)set_cloexec(fd);

  memset(&sun_addr, 0, sizeof(sun_addr));
  sun_addr.sun_family = AF_UNIX;
  memcpy(sun_addr.sun_path, path, path_len + 1);

  int err = connect_with_timeout(fd, (struct sockaddr *)&sun_addr,
                                 sizeof(sun_addr), deadline_ms);
  if (err != 0) {
    close(fd);
    lua_pushnil(L);
    lua_pushfstring(L, "connect '%s': %s", path, strerror(err));
    return 2;
  }

  conn->fd = fd;
  conn->nonblocking = 0;
  conn->closed = 0;
  return 1;
}

static int l_fd(lua_State *L) {
  struct luam_sock *s = check_sock(L, 1, 0);
  lua_pushinteger(L, s->fd);
  return 1;
}

static int l_set_nonblocking(lua_State *L) {
  struct luam_sock *s = check_sock(L, 1, 0);
  luaL_checktype(L, 2, LUA_TBOOLEAN);
  int enable = lua_toboolean(L, 2);
  if (apply_nonblocking(s->fd, enable) < 0) {
    int en = errno;
    lua_pushnil(L);
    lua_pushstring(L, strerror(en));
    return 2;
  }
  s->nonblocking = enable;
  lua_pushboolean(L, 1);
  return 1;
}

static int l_read(lua_State *L) {
  struct luam_sock *s = check_sock(L, 1, 0);
  int max_bytes = luaL_optint(L, 2, 8192);
  luaL_argcheck(L, max_bytes >= 1 && max_bytes <= 1048576, 2,
                "max_bytes must be 1..1048576");

  char stack_buf[8192];
  char *buf = stack_buf;
  if ((size_t)max_bytes > sizeof(stack_buf)) {
    buf = (char *)malloc((size_t)max_bytes);
    if (buf == NULL) {
      lua_pushnil(L);
      lua_pushliteral(L, "out of memory");
      return 2;
    }
  }

  ssize_t r;
  for (;;) {
    r = read(s->fd, buf, (size_t)max_bytes);
    if (r < 0 && errno == EINTR) {
      continue;
    }
    break;
  }

  if (r > 0) {
    lua_pushlstring(L, buf, (size_t)r);
    if (buf != stack_buf) {
      free(buf);
    }
    lua_pushboolean(L, 0);
    return 2;
  }
  if (buf != stack_buf) {
    free(buf);
  }
  if (r == 0) {
    lua_pushliteral(L, "");
    lua_pushboolean(L, 1);
    return 2;
  }
  if (errno == EAGAIN || errno == EWOULDBLOCK) {
    lua_pushliteral(L, "");
    lua_pushboolean(L, 0);
    return 2;
  }
  int en = errno;
  lua_pushnil(L);
  lua_pushstring(L, strerror(en));
  return 2;
}

static int l_write(lua_State *L) {
  struct luam_sock *s = check_sock(L, 1, 0);
  size_t len = 0;
  const char *data = luaL_checklstring(L, 2, &len);
  int start_idx = luaL_optint(L, 3, 1);
  luaL_argcheck(L, start_idx >= 1, 3, "start_idx must be >= 1");

  size_t offset = (size_t)(start_idx - 1);
  if (offset >= len) {
    lua_pushinteger(L, 0);
    return 1;
  }
  size_t rem = len - offset;

  int send_flags = 0;
#ifdef MSG_NOSIGNAL
  send_flags |= MSG_NOSIGNAL;
#endif

  for (;;) {
    ssize_t w = send(s->fd, data + offset, rem, send_flags);
    if (w >= 0) {
      lua_pushinteger(L, (lua_Integer)w);
      return 1;
    }
    if (errno == EINTR) {
      continue;
    }
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      lua_pushinteger(L, 0);
      return 1;
    }
    int en = errno;
    lua_pushnil(L);
    lua_pushstring(L, strerror(en));
    return 2;
  }
}

static int l_close(lua_State *L) {
  struct luam_sock *s = check_sock(L, 1, 1);
  sock_cleanup(s);
  lua_pushboolean(L, 1);
  return 1;
}

static int l_gc(lua_State *L) {
  struct luam_sock *s = check_sock(L, 1, 1);
  sock_cleanup(s);
  return 0;
}

static int l_tostring(lua_State *L) {
  struct luam_sock *s = check_sock(L, 1, 1);
  if (s->closed) {
    lua_pushliteral(L, "net.sock (closed)");
  } else {
    lua_pushfstring(L, "net.sock (fd=%d)", s->fd);
  }
  return 1;
}

static const struct luaL_Reg netlib[] = {
    {"listen_tcp", l_listen_tcp},
    {"listen_unix", l_listen_unix},
    {"local_port", l_local_port},
    {"accept", l_accept},
    {"connect_tcp", l_connect_tcp},
    {"connect_unix", l_connect_unix},
    {"fd", l_fd},
    {"set_nonblocking", l_set_nonblocking},
    {"read", l_read},
    {"write", l_write},
    {"close", l_close},
    {NULL, NULL},
};

LUALIB_API int luaopen_net(lua_State *L) {
  signal(SIGPIPE, SIG_IGN);
  if (luaL_newmetatable(L, LUAM_NET_MT)) {
    lua_pushcfunction(L, l_gc);
    lua_setfield(L, -2, "__gc");
    lua_pushcfunction(L, l_tostring);
    lua_setfield(L, -2, "__tostring");
  }
  lua_pop(L, 1);

  lua_newtable(L);
  luaL_register(L, NULL, netlib);
  return 1;
}
