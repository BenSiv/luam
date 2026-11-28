/*
** proc: argv-safe POSIX subprocess execution without /bin/sh.
**
** Synchronous functions:
**   proc.exec(argv [, opts]) -> {ok, why, code, stdout, stderr} | nil, err
**   proc.run(argv [, opts])  -> ok_bool, why, code | nil, err
**
** Asynchronous procedural child functions:
**   proc.spawn(argv [, opts])                -> child | nil, err
**   proc.pid(child)                          -> int
**   proc.stdin_fd(child) / stdout_fd / stderr_fd -> int | nil
**   proc.read(child, stream [, max_bytes])   -> bytes, eof_bool | nil, err
**   proc.write(child, bytes [, start_idx])   -> n_written | nil, err
**   proc.close_stdin(child)                  -> true
**   proc.wait(child [, nohang_bool])         -> {done, ok, why, code} | nil, err
**   proc.kill(child, sig_name [, group_bool])-> ok_bool, err
**   proc.close(child)                        -> true
*/

#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>

extern char **environ;

struct exec_err_msg {
  int stage; /* 1 = chdir, 2 = execvp */
  int err;
};

struct proc_buf {
  char *data;
  size_t len;
  size_t cap;
};

static void buf_init(struct proc_buf *b) {
  b->data = NULL;
  b->len = 0;
  b->cap = 0;
}

static void buf_free(struct proc_buf *b) {
  free(b->data);
  b->data = NULL;
  b->len = 0;
  b->cap = 0;
}

static int buf_append(struct proc_buf *b, const char *chunk, size_t n) {
  if (n == 0) {
    return 1;
  }
  if (b->len + n > b->cap) {
    size_t new_cap = b->cap == 0 ? 4096 : b->cap;
    while (new_cap < b->len + n) {
      if (new_cap > ((size_t)-1) / 2) {
        return 0;
      }
      new_cap *= 2;
    }
    char *next = (char *)realloc(b->data, new_cap);
    if (next == NULL) {
      return 0;
    }
    b->data = next;
    b->cap = new_cap;
  }
  memcpy(b->data + b->len, chunk, n);
  b->len += n;
  return 1;
}

static int64_t monotonic_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int64_t)ts.tv_sec * 1000 + (int64_t)(ts.tv_nsec / 1000000L);
}

static void set_nonblocking(int fd) {
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags >= 0) {
    (void)fcntl(fd, F_SETFL, flags | O_NONBLOCK);
  }
}

static void set_cloexec(int fd) {
  int flags = fcntl(fd, F_GETFD, 0);
  if (flags >= 0) {
    (void)fcntl(fd, F_SETFD, flags | FD_CLOEXEC);
  }
}

static void safe_close(int *fd) {
  if (*fd >= 0) {
    close(*fd);
    *fd = -1;
  }
}

struct env_kv {
  char *key;
  char *val;
};

static void free_argv_and_env(char **argv, size_t argc, struct env_kv *envs,
                              size_t n_env) {
  size_t i;
  if (argv != NULL) {
    for (i = 0; i < argc; i++) {
      free(argv[i]);
    }
    free(argv);
  }
  if (envs != NULL) {
    for (i = 0; i < n_env; i++) {
      free(envs[i].key);
      free(envs[i].val);
    }
    free(envs);
  }
}

static char *dup_lstring_checked(lua_State *L, const char *s, size_t len,
                                 const char *what) {
  if (memchr(s, '\0', len) != NULL) {
    luaL_error(L, "%s must not contain NUL bytes", what);
    return NULL;
  }
  char *copy = (char *)malloc(len + 1);
  if (copy == NULL) {
    luaL_error(L, "out of memory");
    return NULL;
  }
  memcpy(copy, s, len);
  copy[len] = '\0';
  return copy;
}

static void parse_argv(lua_State *L, int idx, char ***out_argv,
                       size_t *out_argc) {
  luaL_checktype(L, idx, LUA_TTABLE);
  size_t n = lua_objlen(L, idx);
  luaL_argcheck(L, n >= 1, idx, "argv must be a non-empty list of strings");

  char **argv = (char **)calloc(n + 1, sizeof(char *));
  if (argv == NULL) {
    luaL_error(L, "out of memory");
  }
  size_t i;
  for (i = 1; i <= n; i++) {
    lua_rawgeti(L, idx, (int)i);
    if (!lua_isstring(L, -1)) {
      lua_pop(L, 1);
      free_argv_and_env(argv, i - 1, NULL, 0);
      luaL_argerror(L, idx, "all argv elements must be strings");
    }
    size_t slen = 0;
    const char *s = lua_tolstring(L, -1, &slen);
    if (i == 1 && slen == 0) {
      lua_pop(L, 1);
      free_argv_and_env(argv, 0, NULL, 0);
      luaL_argerror(L, idx, "argv[1] executable name cannot be empty");
    }
    if (memchr(s, '\0', slen) != NULL) {
      lua_pop(L, 1);
      free_argv_and_env(argv, i - 1, NULL, 0);
      luaL_argerror(L, idx, "argv elements must not contain NUL bytes");
    }
    argv[i - 1] = (char *)malloc(slen + 1);
    if (argv[i - 1] == NULL) {
      lua_pop(L, 1);
      free_argv_and_env(argv, i - 1, NULL, 0);
      luaL_error(L, "out of memory");
    }
    memcpy(argv[i - 1], s, slen + 1);
    lua_pop(L, 1);
  }
  argv[n] = NULL;
  *out_argv = argv;
  *out_argc = n;
}

struct proc_opts {
  const char *stdin_data;
  size_t stdin_len;
  int has_stdin;
  const char *cwd;
  int clear_env;
  int merge_stderr;
  int64_t timeout_ms;
  struct env_kv *envs;
  size_t n_env;
};

static void parse_opts(lua_State *L, int idx, char **argv, size_t argc,
                       struct proc_opts *opts) {
  memset(opts, 0, sizeof(*opts));
  opts->timeout_ms = -1;
  if (lua_isnoneornil(L, idx)) {
    return;
  }
  if (!lua_istable(L, idx)) {
    free_argv_and_env(argv, argc, NULL, 0);
    luaL_typerror(L, idx, "table");
  }

  lua_getfield(L, idx, "stdin");
  if (!lua_isnil(L, -1)) {
    if (lua_type(L, -1) != LUA_TSTRING) {
      lua_pop(L, 1);
      free_argv_and_env(argv, argc, NULL, 0);
      luaL_argerror(L, idx, "opts.stdin must be a string");
    }
    opts->stdin_data = lua_tolstring(L, -1, &opts->stdin_len);
    opts->has_stdin = 1;
  }
  lua_pop(L, 1);

  lua_getfield(L, idx, "cwd");
  if (!lua_isnil(L, -1)) {
    size_t clen = 0;
    const char *cstr = lua_tolstring(L, -1, &clen);
    if (cstr == NULL || memchr(cstr, '\0', clen) != NULL) {
      lua_pop(L, 1);
      free_argv_and_env(argv, argc, NULL, 0);
      luaL_argerror(L, idx, "opts.cwd must be a valid path string");
    }
    opts->cwd = cstr;
  }
  lua_pop(L, 1);

  lua_getfield(L, idx, "clear_env");
  opts->clear_env = lua_toboolean(L, -1);
  lua_pop(L, 1);

  lua_getfield(L, idx, "merge_stderr");
  opts->merge_stderr = lua_toboolean(L, -1);
  lua_pop(L, 1);

  lua_getfield(L, idx, "timeout_ms");
  if (!lua_isnil(L, -1)) {
    if (!lua_isnumber(L, -1)) {
      lua_pop(L, 1);
      free_argv_and_env(argv, argc, NULL, 0);
      luaL_argerror(L, idx, "opts.timeout_ms must be a number");
    }
    lua_Number t = lua_tonumber(L, -1);
    if (t > 0) {
      opts->timeout_ms = (int64_t)t;
      if (opts->timeout_ms < 1) {
        opts->timeout_ms = 1;
      }
    }
  }
  lua_pop(L, 1);

  lua_getfield(L, idx, "env");
  if (!lua_isnil(L, -1)) {
    if (!lua_istable(L, -1)) {
      lua_pop(L, 1);
      free_argv_and_env(argv, argc, NULL, 0);
      luaL_argerror(L, idx, "opts.env must be a table");
    }
    size_t cap = 8;
    size_t cnt = 0;
    struct env_kv *envs = (struct env_kv *)calloc(cap, sizeof(struct env_kv));
    if (envs == NULL) {
      lua_pop(L, 1);
      free_argv_and_env(argv, argc, NULL, 0);
      luaL_error(L, "out of memory");
    }
    lua_pushnil(L);
    while (lua_next(L, -2) != 0) {
      if (lua_type(L, -2) != LUA_TSTRING || lua_type(L, -1) != LUA_TSTRING) {
        lua_pop(L, 3);
        free_argv_and_env(argv, argc, envs, cnt);
        luaL_argerror(L, idx, "opts.env keys and values must be strings");
      }
      size_t klen = 0, vlen = 0;
      const char *k = lua_tolstring(L, -2, &klen);
      const char *v = lua_tolstring(L, -1, &vlen);
      if (klen == 0 || memchr(k, '=', klen) != NULL ||
          memchr(k, '\0', klen) != NULL || memchr(v, '\0', vlen) != NULL) {
        lua_pop(L, 3);
        free_argv_and_env(argv, argc, envs, cnt);
        luaL_argerror(L, idx, "invalid environment variable name or value");
      }
      if (cnt == cap) {
        cap *= 2;
        struct env_kv *grown =
            (struct env_kv *)realloc(envs, cap * sizeof(struct env_kv));
        if (grown == NULL) {
          lua_pop(L, 3);
          free_argv_and_env(argv, argc, envs, cnt);
          luaL_error(L, "out of memory");
        }
        envs = grown;
      }
      envs[cnt].key = dup_lstring_checked(L, k, klen, "env key");
      envs[cnt].val = dup_lstring_checked(L, v, vlen, "env value");
      cnt++;
      lua_pop(L, 1);
    }
    opts->envs = envs;
    opts->n_env = cnt;
  }
  lua_pop(L, 1);
}

static void child_ReportAndExit(int err_fd, int stage, int err_code) {
  struct exec_err_msg msg;
  msg.stage = stage;
  msg.err = err_code;
  ssize_t wr = write(err_fd, &msg, sizeof(msg));
  (void)wr;
  _exit(127);
}

static void reset_child_signals(void) {
  sigset_t empty;
  sigemptyset(&empty);
  (void)sigprocmask(SIG_SETMASK, &empty, NULL);
  signal(SIGPIPE, SIG_DFL);
}

static int read_exec_err(int err_fd, struct exec_err_msg *out) {
  size_t got = 0;
  char *p = (char *)out;
  while (got < sizeof(*out)) {
    ssize_t r = read(err_fd, p + got, sizeof(*out) - got);
    if (r < 0) {
      if (errno == EINTR) {
        continue;
      }
      break;
    }
    if (r == 0) {
      break;
    }
    got += (size_t)r;
  }
  return got == sizeof(*out);
}

static void wait_with_timeout(pid_t pid, int64_t deadline_ms, int *status_out,
                              int *timed_out) {
  *timed_out = 0;
  if (deadline_ms < 0) {
    while (waitpid(pid, status_out, 0) < 0) {
      if (errno != EINTR) {
        *status_out = 0;
        return;
      }
    }
    return;
  }

  for (;;) {
    pid_t w = waitpid(pid, status_out, WNOHANG);
    if (w == pid) {
      return;
    }
    if (w < 0 && errno != EINTR) {
      *status_out = 0;
      return;
    }
    if (monotonic_ms() >= deadline_ms) {
      *timed_out = 1;
      kill(pid, SIGKILL);
      while (waitpid(pid, status_out, 0) < 0 && errno == EINTR) {
      }
      return;
    }
    struct timespec nap;
    nap.tv_sec = 0;
    nap.tv_nsec = 2000000L; /* 2ms poll interval after pipes close */
    nanosleep(&nap, NULL);
  }
}

static int l_proc_exec(lua_State *L) {
  char **argv = NULL;
  size_t argc = 0;
  struct proc_opts opts;
  parse_argv(L, 1, &argv, &argc);
  parse_opts(L, 2, argv, argc, &opts);

  int err_pipe[2] = {-1, -1};
  int in_pipe[2] = {-1, -1};
  int out_pipe[2] = {-1, -1};
  int stderr_pipe[2] = {-1, -1};

  if (pipe(err_pipe) != 0 || pipe(out_pipe) != 0) {
    int en = errno;
    safe_close(&err_pipe[0]);
    safe_close(&err_pipe[1]);
    safe_close(&out_pipe[0]);
    safe_close(&out_pipe[1]);
    free_argv_and_env(argv, argc, opts.envs, opts.n_env);
    lua_pushnil(L);
    lua_pushfstring(L, "pipe failed: %s", strerror(en));
    return 2;
  }
  set_cloexec(err_pipe[0]);
  set_cloexec(err_pipe[1]);

  if (opts.has_stdin && pipe(in_pipe) != 0) {
    int en = errno;
    safe_close(&err_pipe[0]);
    safe_close(&err_pipe[1]);
    safe_close(&out_pipe[0]);
    safe_close(&out_pipe[1]);
    free_argv_and_env(argv, argc, opts.envs, opts.n_env);
    lua_pushnil(L);
    lua_pushfstring(L, "pipe failed: %s", strerror(en));
    return 2;
  }

  if (!opts.merge_stderr && pipe(stderr_pipe) != 0) {
    int en = errno;
    safe_close(&err_pipe[0]);
    safe_close(&err_pipe[1]);
    safe_close(&out_pipe[0]);
    safe_close(&out_pipe[1]);
    safe_close(&in_pipe[0]);
    safe_close(&in_pipe[1]);
    free_argv_and_env(argv, argc, opts.envs, opts.n_env);
    lua_pushnil(L);
    lua_pushfstring(L, "pipe failed: %s", strerror(en));
    return 2;
  }

  int64_t deadline_ms =
      opts.timeout_ms > 0 ? (monotonic_ms() + opts.timeout_ms) : -1;

  pid_t pid = fork();
  if (pid < 0) {
    int en = errno;
    safe_close(&err_pipe[0]);
    safe_close(&err_pipe[1]);
    safe_close(&in_pipe[0]);
    safe_close(&in_pipe[1]);
    safe_close(&out_pipe[0]);
    safe_close(&out_pipe[1]);
    safe_close(&stderr_pipe[0]);
    safe_close(&stderr_pipe[1]);
    free_argv_and_env(argv, argc, opts.envs, opts.n_env);
    lua_pushnil(L);
    lua_pushfstring(L, "fork failed: %s", strerror(en));
    return 2;
  }

  if (pid == 0) {
    static char *empty_environ[] = {NULL};
    size_t i;
    reset_child_signals();
    close(err_pipe[0]);

    if (opts.has_stdin) {
      close(in_pipe[1]);
      if (dup2(in_pipe[0], STDIN_FILENO) < 0) {
        child_ReportAndExit(err_pipe[1], 2, errno);
      }
      close(in_pipe[0]);
    } else {
      int devnull = open("/dev/null", O_RDONLY);
      if (devnull >= 0) {
        (void)dup2(devnull, STDIN_FILENO);
        if (devnull > STDIN_FILENO) {
          close(devnull);
        }
      }
    }

    close(out_pipe[0]);
    if (dup2(out_pipe[1], STDOUT_FILENO) < 0) {
      child_ReportAndExit(err_pipe[1], 2, errno);
    }
    if (opts.merge_stderr) {
      if (dup2(out_pipe[1], STDERR_FILENO) < 0) {
        child_ReportAndExit(err_pipe[1], 2, errno);
      }
    } else {
      close(stderr_pipe[0]);
      if (dup2(stderr_pipe[1], STDERR_FILENO) < 0) {
        child_ReportAndExit(err_pipe[1], 2, errno);
      }
      close(stderr_pipe[1]);
    }
    close(out_pipe[1]);

    if (opts.clear_env) {
      environ = empty_environ;
    }
    for (i = 0; i < opts.n_env; i++) {
      setenv(opts.envs[i].key, opts.envs[i].val, 1);
    }
    if (opts.cwd != NULL && chdir(opts.cwd) != 0) {
      child_ReportAndExit(err_pipe[1], 1, errno);
    }

    execvp(argv[0], argv);
    child_ReportAndExit(err_pipe[1], 2, errno);
  }

  /* Parent */
  safe_close(&err_pipe[1]);
  safe_close(&in_pipe[0]);
  safe_close(&out_pipe[1]);
  safe_close(&stderr_pipe[1]);

  struct exec_err_msg child_err;
  int spawn_failed = read_exec_err(err_pipe[0], &child_err);
  safe_close(&err_pipe[0]);

  if (spawn_failed) {
    int st = 0;
    safe_close(&in_pipe[1]);
    safe_close(&out_pipe[0]);
    safe_close(&stderr_pipe[0]);
    while (waitpid(pid, &st, 0) < 0 && errno == EINTR) {
    }
    lua_pushnil(L);
    if (child_err.stage == 1) {
      lua_pushfstring(L, "chdir '%s': %s", opts.cwd ? opts.cwd : "",
                      strerror(child_err.err));
    } else {
      lua_pushfstring(L, "%s: %s", argv[0], strerror(child_err.err));
    }
    free_argv_and_env(argv, argc, opts.envs, opts.n_env);
    return 2;
  }

  if (in_pipe[1] >= 0) {
    if (opts.stdin_len == 0) {
      safe_close(&in_pipe[1]);
    } else {
      set_nonblocking(in_pipe[1]);
    }
  }
  set_nonblocking(out_pipe[0]);
  if (stderr_pipe[0] >= 0) {
    set_nonblocking(stderr_pipe[0]);
  }

  struct sigaction sa_ign, sa_old;
  memset(&sa_ign, 0, sizeof(sa_ign));
  sa_ign.sa_handler = SIG_IGN;
  sigemptyset(&sa_ign.sa_mask);
  int restored_sigpipe = (sigaction(SIGPIPE, &sa_ign, &sa_old) == 0);

  struct proc_buf stdout_buf, stderr_buf;
  buf_init(&stdout_buf);
  buf_init(&stderr_buf);

  size_t stdin_written = 0;
  int timed_out = 0;
  int oom = 0;
  char io_chunk[8192];

  while ((in_pipe[1] >= 0 || out_pipe[0] >= 0 || stderr_pipe[0] >= 0) && !oom) {
    struct pollfd pfds[3];
    int nfds = 0;
    int in_idx = -1, out_idx = -1, err_idx = -1;

    if (in_pipe[1] >= 0) {
      in_idx = nfds++;
      pfds[in_idx].fd = in_pipe[1];
      pfds[in_idx].events = POLLOUT;
      pfds[in_idx].revents = 0;
    }
    if (out_pipe[0] >= 0) {
      out_idx = nfds++;
      pfds[out_idx].fd = out_pipe[0];
      pfds[out_idx].events = POLLIN;
      pfds[out_idx].revents = 0;
    }
    if (stderr_pipe[0] >= 0) {
      err_idx = nfds++;
      pfds[err_idx].fd = stderr_pipe[0];
      pfds[err_idx].events = POLLIN;
      pfds[err_idx].revents = 0;
    }

    int poll_wait = -1;
    if (deadline_ms >= 0) {
      int64_t rem = deadline_ms - monotonic_ms();
      if (rem <= 0) {
        timed_out = 1;
        kill(pid, SIGKILL);
        safe_close(&in_pipe[1]);
        safe_close(&out_pipe[0]);
        safe_close(&stderr_pipe[0]);
        break;
      }
      poll_wait = rem > 60000 ? 60000 : (int)rem;
    }

    int pr = poll(pfds, (nfds_t)nfds, poll_wait);
    if (pr < 0) {
      if (errno == EINTR) {
        continue;
      }
      break;
    }
    if (pr == 0) {
      continue;
    }

    if (in_idx >= 0 &&
        (pfds[in_idx].revents & (POLLOUT | POLLERR | POLLHUP))) {
      size_t rem_bytes = opts.stdin_len - stdin_written;
      ssize_t w = write(in_pipe[1], opts.stdin_data + stdin_written, rem_bytes);
      if (w > 0) {
        stdin_written += (size_t)w;
        if (stdin_written >= opts.stdin_len) {
          safe_close(&in_pipe[1]);
        }
      } else if (w < 0 && (errno == EAGAIN || errno == EWOULDBLOCK ||
                           errno == EINTR)) {
        /* wait for next poll */
      } else {
        safe_close(&in_pipe[1]);
      }
    }

    if (out_idx >= 0 &&
        (pfds[out_idx].revents & (POLLIN | POLLHUP | POLLERR))) {
      for (;;) {
        ssize_t r = read(out_pipe[0], io_chunk, sizeof(io_chunk));
        if (r > 0) {
          if (!buf_append(&stdout_buf, io_chunk, (size_t)r)) {
            oom = 1;
            break;
          }
        } else if (r == 0) {
          safe_close(&out_pipe[0]);
          break;
        } else if (errno == EINTR) {
          continue;
        } else if (errno == EAGAIN || errno == EWOULDBLOCK) {
          break;
        } else {
          safe_close(&out_pipe[0]);
          break;
        }
      }
    }

    if (err_idx >= 0 &&
        (pfds[err_idx].revents & (POLLIN | POLLHUP | POLLERR))) {
      for (;;) {
        ssize_t r = read(stderr_pipe[0], io_chunk, sizeof(io_chunk));
        if (r > 0) {
          if (!buf_append(&stderr_buf, io_chunk, (size_t)r)) {
            oom = 1;
            break;
          }
        } else if (r == 0) {
          safe_close(&stderr_pipe[0]);
          break;
        } else if (errno == EINTR) {
          continue;
        } else if (errno == EAGAIN || errno == EWOULDBLOCK) {
          break;
        } else {
          safe_close(&stderr_pipe[0]);
          break;
        }
      }
    }
  }

  if (restored_sigpipe) {
    sigaction(SIGPIPE, &sa_old, NULL);
  }

  safe_close(&in_pipe[1]);
  safe_close(&out_pipe[0]);
  safe_close(&stderr_pipe[0]);

  int status = 0;
  if (timed_out) {
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
    }
  } else {
    wait_with_timeout(pid, deadline_ms, &status, &timed_out);
  }

  free_argv_and_env(argv, argc, opts.envs, opts.n_env);

  if (oom) {
    buf_free(&stdout_buf);
    buf_free(&stderr_buf);
    return luaL_error(L, "out of memory capturing subprocess output");
  }

  const char *why = "exit";
  int code = -1;
  int ok_bool = 0;

  if (timed_out) {
    why = "timeout";
    code = -1;
    ok_bool = 0;
  } else if (WIFEXITED(status)) {
    why = "exit";
    code = WEXITSTATUS(status);
    ok_bool = (code == 0);
  } else if (WIFSIGNALED(status)) {
    why = "signal";
    code = WTERMSIG(status);
    ok_bool = 0;
  }

  lua_createtable(L, 0, 5);
  lua_pushboolean(L, ok_bool);
  lua_setfield(L, -2, "ok");
  lua_pushstring(L, why);
  lua_setfield(L, -2, "why");
  lua_pushinteger(L, code);
  lua_setfield(L, -2, "code");
  lua_pushlstring(L, stdout_buf.data ? stdout_buf.data : "", stdout_buf.len);
  lua_setfield(L, -2, "stdout");
  lua_pushlstring(L, stderr_buf.data ? stderr_buf.data : "", stderr_buf.len);
  lua_setfield(L, -2, "stderr");

  buf_free(&stdout_buf);
  buf_free(&stderr_buf);
  return 1;
}

static int l_proc_run(lua_State *L) {
  char **argv = NULL;
  size_t argc = 0;
  struct proc_opts opts;
  parse_argv(L, 1, &argv, &argc);
  parse_opts(L, 2, argv, argc, &opts);

  int err_pipe[2] = {-1, -1};
  if (pipe(err_pipe) != 0) {
    int en = errno;
    free_argv_and_env(argv, argc, opts.envs, opts.n_env);
    lua_pushnil(L);
    lua_pushfstring(L, "pipe failed: %s", strerror(en));
    return 2;
  }
  set_cloexec(err_pipe[0]);
  set_cloexec(err_pipe[1]);

  int64_t deadline_ms =
      opts.timeout_ms > 0 ? (monotonic_ms() + opts.timeout_ms) : -1;

  pid_t pid = fork();
  if (pid < 0) {
    int en = errno;
    safe_close(&err_pipe[0]);
    safe_close(&err_pipe[1]);
    free_argv_and_env(argv, argc, opts.envs, opts.n_env);
    lua_pushnil(L);
    lua_pushfstring(L, "fork failed: %s", strerror(en));
    return 2;
  }

  if (pid == 0) {
    static char *empty_environ[] = {NULL};
    size_t i;
    reset_child_signals();
    close(err_pipe[0]);
    if (opts.clear_env) {
      environ = empty_environ;
    }
    for (i = 0; i < opts.n_env; i++) {
      setenv(opts.envs[i].key, opts.envs[i].val, 1);
    }
    if (opts.cwd != NULL && chdir(opts.cwd) != 0) {
      child_ReportAndExit(err_pipe[1], 1, errno);
    }
    execvp(argv[0], argv);
    child_ReportAndExit(err_pipe[1], 2, errno);
  }

  safe_close(&err_pipe[1]);
  struct exec_err_msg child_err;
  int spawn_failed = read_exec_err(err_pipe[0], &child_err);
  safe_close(&err_pipe[0]);

  if (spawn_failed) {
    int st = 0;
    while (waitpid(pid, &st, 0) < 0 && errno == EINTR) {
    }
    lua_pushnil(L);
    if (child_err.stage == 1) {
      lua_pushfstring(L, "chdir '%s': %s", opts.cwd ? opts.cwd : "",
                      strerror(child_err.err));
    } else {
      lua_pushfstring(L, "%s: %s", argv[0], strerror(child_err.err));
    }
    free_argv_and_env(argv, argc, opts.envs, opts.n_env);
    return 2;
  }

  int status = 0;
  int timed_out = 0;
  wait_with_timeout(pid, deadline_ms, &status, &timed_out);
  free_argv_and_env(argv, argc, opts.envs, opts.n_env);

  if (timed_out) {
    lua_pushboolean(L, 0);
    lua_pushliteral(L, "timeout");
    lua_pushinteger(L, -1);
    return 3;
  }
  if (WIFEXITED(status)) {
    int code = WEXITSTATUS(status);
    lua_pushboolean(L, code == 0);
    lua_pushliteral(L, "exit");
    lua_pushinteger(L, code);
    return 3;
  }
  if (WIFSIGNALED(status)) {
    lua_pushboolean(L, 0);
    lua_pushliteral(L, "signal");
    lua_pushinteger(L, WTERMSIG(status));
    return 3;
  }
  lua_pushboolean(L, 0);
  lua_pushliteral(L, "exit");
  lua_pushinteger(L, -1);
  return 3;
}

/* ---- Asynchronous procedural child handle ---- */

#define LUAM_PROC_CHILD_MT "luam.proc.child"

struct proc_child {
  pid_t pid;
  int new_pgid;
  int stdin_fd;
  int stdout_fd;
  int stderr_fd;
  int waited;
  int exit_ok;
  const char *exit_why;
  int exit_code;
  int closed;
};

struct spawn_opts {
  const char *cwd;
  int clear_env;
  int stdin_pipe;
  int stdout_pipe;
  int stderr_pipe;
  int merge_stderr;
  int new_pgid;
  struct env_kv *envs;
  size_t n_env;
};

static struct proc_child *check_child(lua_State *L, int idx, int allow_closed) {
  struct proc_child *c =
      (struct proc_child *)luaL_checkudata(L, idx, LUAM_PROC_CHILD_MT);
  if (!allow_closed && c->closed) {
    luaL_error(L, "attempt to use a closed proc.child");
  }
  return c;
}

static void record_wait_status(struct proc_child *c, int status) {
  c->waited = 1;
  if (WIFEXITED(status)) {
    c->exit_why = "exit";
    c->exit_code = WEXITSTATUS(status);
    c->exit_ok = (c->exit_code == 0);
  } else if (WIFSIGNALED(status)) {
    c->exit_why = "signal";
    c->exit_code = WTERMSIG(status);
    c->exit_ok = 0;
  } else {
    c->exit_why = "exit";
    c->exit_code = -1;
    c->exit_ok = 0;
  }
}

static void child_cleanup(struct proc_child *c) {
  if (!c->closed) {
    safe_close(&c->stdin_fd);
    safe_close(&c->stdout_fd);
    safe_close(&c->stderr_fd);
    if (!c->waited && c->pid > 0) {
      int st = 0;
      pid_t w = waitpid(c->pid, &st, WNOHANG);
      if (w == c->pid) {
        record_wait_status(c, st);
      }
    }
    c->closed = 1;
  }
}

static void parse_spawn_opts(lua_State *L, int idx, char **argv, size_t argc,
                             struct spawn_opts *opts) {
  memset(opts, 0, sizeof(*opts));
  opts->stdout_pipe = 1;
  opts->stderr_pipe = 1;
  if (lua_isnoneornil(L, idx)) {
    return;
  }
  if (!lua_istable(L, idx)) {
    free_argv_and_env(argv, argc, NULL, 0);
    luaL_typerror(L, idx, "table");
  }

  lua_getfield(L, idx, "cwd");
  if (!lua_isnil(L, -1)) {
    size_t clen = 0;
    const char *cstr = lua_tolstring(L, -1, &clen);
    if (cstr == NULL || memchr(cstr, '\0', clen) != NULL) {
      lua_pop(L, 1);
      free_argv_and_env(argv, argc, NULL, 0);
      luaL_argerror(L, idx, "opts.cwd must be a valid path string");
    }
    opts->cwd = cstr;
  }
  lua_pop(L, 1);

  lua_getfield(L, idx, "clear_env");
  opts->clear_env = lua_toboolean(L, -1);
  lua_pop(L, 1);

  lua_getfield(L, idx, "stdin_pipe");
  opts->stdin_pipe = lua_toboolean(L, -1);
  lua_pop(L, 1);

  lua_getfield(L, idx, "stdout_pipe");
  if (!lua_isnil(L, -1)) {
    opts->stdout_pipe = lua_toboolean(L, -1);
  }
  lua_pop(L, 1);

  lua_getfield(L, idx, "stderr_pipe");
  if (!lua_isnil(L, -1)) {
    opts->stderr_pipe = lua_toboolean(L, -1);
  }
  lua_pop(L, 1);

  lua_getfield(L, idx, "merge_stderr");
  opts->merge_stderr = lua_toboolean(L, -1);
  lua_pop(L, 1);

  lua_getfield(L, idx, "new_pgid");
  opts->new_pgid = lua_toboolean(L, -1);
  lua_pop(L, 1);

  lua_getfield(L, idx, "env");
  if (!lua_isnil(L, -1)) {
    if (!lua_istable(L, -1)) {
      lua_pop(L, 1);
      free_argv_and_env(argv, argc, NULL, 0);
      luaL_argerror(L, idx, "opts.env must be a table");
    }
    size_t cap = 8;
    size_t cnt = 0;
    struct env_kv *envs = (struct env_kv *)calloc(cap, sizeof(struct env_kv));
    if (envs == NULL) {
      lua_pop(L, 1);
      free_argv_and_env(argv, argc, NULL, 0);
      luaL_error(L, "out of memory");
    }
    lua_pushnil(L);
    while (lua_next(L, -2) != 0) {
      if (lua_type(L, -2) != LUA_TSTRING || lua_type(L, -1) != LUA_TSTRING) {
        lua_pop(L, 3);
        free_argv_and_env(argv, argc, envs, cnt);
        luaL_argerror(L, idx, "opts.env keys and values must be strings");
      }
      size_t klen = 0, vlen = 0;
      const char *k = lua_tolstring(L, -2, &klen);
      const char *v = lua_tolstring(L, -1, &vlen);
      if (klen == 0 || memchr(k, '=', klen) != NULL ||
          memchr(k, '\0', klen) != NULL || memchr(v, '\0', vlen) != NULL) {
        lua_pop(L, 3);
        free_argv_and_env(argv, argc, envs, cnt);
        luaL_argerror(L, idx, "invalid environment variable name or value");
      }
      if (cnt == cap) {
        cap *= 2;
        struct env_kv *grown =
            (struct env_kv *)realloc(envs, cap * sizeof(struct env_kv));
        if (grown == NULL) {
          lua_pop(L, 3);
          free_argv_and_env(argv, argc, envs, cnt);
          luaL_error(L, "out of memory");
        }
        envs = grown;
      }
      envs[cnt].key = dup_lstring_checked(L, k, klen, "env key");
      envs[cnt].val = dup_lstring_checked(L, v, vlen, "env value");
      cnt++;
      lua_pop(L, 1);
    }
    opts->envs = envs;
    opts->n_env = cnt;
  }
  lua_pop(L, 1);
}

static void redirect_devnull(int target_fd, int flags) {
  int dn = open("/dev/null", flags);
  if (dn >= 0) {
    (void)dup2(dn, target_fd);
    if (dn != target_fd) {
      close(dn);
    }
  }
}

static int l_proc_spawn(lua_State *L) {
  char **argv = NULL;
  size_t argc = 0;
  struct spawn_opts opts;
  parse_argv(L, 1, &argv, &argc);
  parse_spawn_opts(L, 2, argv, argc, &opts);

  struct proc_child *child =
      (struct proc_child *)lua_newuserdata(L, sizeof(struct proc_child));
  memset(child, 0, sizeof(*child));
  child->pid = -1;
  child->stdin_fd = -1;
  child->stdout_fd = -1;
  child->stderr_fd = -1;
  child->closed = 1;
  luaL_getmetatable(L, LUAM_PROC_CHILD_MT);
  lua_setmetatable(L, -2);

  int err_pipe[2] = {-1, -1};
  int in_pipe[2] = {-1, -1};
  int out_pipe[2] = {-1, -1};
  int stderr_pipe[2] = {-1, -1};

  if (pipe(err_pipe) != 0 || (opts.stdin_pipe && pipe(in_pipe) != 0) ||
      (opts.stdout_pipe && pipe(out_pipe) != 0) ||
      (!opts.merge_stderr && opts.stderr_pipe && pipe(stderr_pipe) != 0)) {
    int en = errno;
    safe_close(&err_pipe[0]);
    safe_close(&err_pipe[1]);
    safe_close(&in_pipe[0]);
    safe_close(&in_pipe[1]);
    safe_close(&out_pipe[0]);
    safe_close(&out_pipe[1]);
    safe_close(&stderr_pipe[0]);
    safe_close(&stderr_pipe[1]);
    free_argv_and_env(argv, argc, opts.envs, opts.n_env);
    lua_pushnil(L);
    lua_pushfstring(L, "pipe failed: %s", strerror(en));
    return 2;
  }
  set_cloexec(err_pipe[0]);
  set_cloexec(err_pipe[1]);

  pid_t pid = fork();
  if (pid < 0) {
    int en = errno;
    safe_close(&err_pipe[0]);
    safe_close(&err_pipe[1]);
    safe_close(&in_pipe[0]);
    safe_close(&in_pipe[1]);
    safe_close(&out_pipe[0]);
    safe_close(&out_pipe[1]);
    safe_close(&stderr_pipe[0]);
    safe_close(&stderr_pipe[1]);
    free_argv_and_env(argv, argc, opts.envs, opts.n_env);
    lua_pushnil(L);
    lua_pushfstring(L, "fork failed: %s", strerror(en));
    return 2;
  }

  if (pid == 0) {
    static char *empty_environ[] = {NULL};
    size_t i;
    reset_child_signals();
    if (opts.new_pgid) {
      (void)setpgid(0, 0);
    }
    close(err_pipe[0]);

    if (opts.stdin_pipe) {
      close(in_pipe[1]);
      if (dup2(in_pipe[0], STDIN_FILENO) < 0) {
        child_ReportAndExit(err_pipe[1], 2, errno);
      }
      if (in_pipe[0] != STDIN_FILENO) {
        close(in_pipe[0]);
      }
    } else {
      redirect_devnull(STDIN_FILENO, O_RDONLY);
    }

    if (opts.stdout_pipe) {
      close(out_pipe[0]);
      if (dup2(out_pipe[1], STDOUT_FILENO) < 0) {
        child_ReportAndExit(err_pipe[1], 2, errno);
      }
    } else {
      redirect_devnull(STDOUT_FILENO, O_WRONLY);
    }

    if (opts.merge_stderr) {
      if (opts.stdout_pipe) {
        if (dup2(out_pipe[1], STDERR_FILENO) < 0) {
          child_ReportAndExit(err_pipe[1], 2, errno);
        }
      } else {
        redirect_devnull(STDERR_FILENO, O_WRONLY);
      }
    } else if (opts.stderr_pipe) {
      close(stderr_pipe[0]);
      if (dup2(stderr_pipe[1], STDERR_FILENO) < 0) {
        child_ReportAndExit(err_pipe[1], 2, errno);
      }
      if (stderr_pipe[1] != STDERR_FILENO) {
        close(stderr_pipe[1]);
      }
    } else {
      redirect_devnull(STDERR_FILENO, O_WRONLY);
    }

    if (opts.stdout_pipe && out_pipe[1] != STDOUT_FILENO &&
        out_pipe[1] != STDERR_FILENO) {
      close(out_pipe[1]);
    }

    if (opts.clear_env) {
      environ = empty_environ;
    }
    for (i = 0; i < opts.n_env; i++) {
      setenv(opts.envs[i].key, opts.envs[i].val, 1);
    }
    if (opts.cwd != NULL && chdir(opts.cwd) != 0) {
      child_ReportAndExit(err_pipe[1], 1, errno);
    }

    execvp(argv[0], argv);
    child_ReportAndExit(err_pipe[1], 2, errno);
  }

  /* Parent: set child pgid before returning to avoid kill(-pgid) races. */
  if (opts.new_pgid) {
    (void)setpgid(pid, pid);
  }

  safe_close(&err_pipe[1]);
  safe_close(&in_pipe[0]);
  safe_close(&out_pipe[1]);
  safe_close(&stderr_pipe[1]);

  struct exec_err_msg child_err;
  int spawn_failed = read_exec_err(err_pipe[0], &child_err);
  safe_close(&err_pipe[0]);

  if (spawn_failed) {
    int st = 0;
    safe_close(&in_pipe[1]);
    safe_close(&out_pipe[0]);
    safe_close(&stderr_pipe[0]);
    while (waitpid(pid, &st, 0) < 0 && errno == EINTR) {
    }
    lua_pushnil(L);
    if (child_err.stage == 1) {
      lua_pushfstring(L, "chdir '%s': %s", opts.cwd ? opts.cwd : "",
                      strerror(child_err.err));
    } else {
      lua_pushfstring(L, "%s: %s", argv[0], strerror(child_err.err));
    }
    free_argv_and_env(argv, argc, opts.envs, opts.n_env);
    return 2;
  }

  free_argv_and_env(argv, argc, opts.envs, opts.n_env);

  /* Parent pipe fds must be CLOEXEC + NONBLOCK so sibling spawns never leak. */
  if (in_pipe[1] >= 0) {
    set_cloexec(in_pipe[1]);
    set_nonblocking(in_pipe[1]);
  }
  if (out_pipe[0] >= 0) {
    set_cloexec(out_pipe[0]);
    set_nonblocking(out_pipe[0]);
  }
  if (stderr_pipe[0] >= 0) {
    set_cloexec(stderr_pipe[0]);
    set_nonblocking(stderr_pipe[0]);
  }

  child->pid = pid;
  child->new_pgid = opts.new_pgid;
  child->stdin_fd = in_pipe[1];
  child->stdout_fd = out_pipe[0];
  child->stderr_fd = stderr_pipe[0];
  child->waited = 0;
  child->closed = 0;
  return 1;
}

static int l_proc_pid(lua_State *L) {
  struct proc_child *c = check_child(L, 1, 0);
  lua_pushinteger(L, (lua_Integer)c->pid);
  return 1;
}

static int l_proc_stdin_fd(lua_State *L) {
  struct proc_child *c = check_child(L, 1, 0);
  if (c->stdin_fd < 0) {
    lua_pushnil(L);
  } else {
    lua_pushinteger(L, c->stdin_fd);
  }
  return 1;
}

static int l_proc_stdout_fd(lua_State *L) {
  struct proc_child *c = check_child(L, 1, 0);
  if (c->stdout_fd < 0) {
    lua_pushnil(L);
  } else {
    lua_pushinteger(L, c->stdout_fd);
  }
  return 1;
}

static int l_proc_stderr_fd(lua_State *L) {
  struct proc_child *c = check_child(L, 1, 0);
  if (c->stderr_fd < 0) {
    lua_pushnil(L);
  } else {
    lua_pushinteger(L, c->stderr_fd);
  }
  return 1;
}

static int l_proc_read(lua_State *L) {
  struct proc_child *c = check_child(L, 1, 0);
  const char *stream = luaL_checkstring(L, 2);
  int max_bytes = luaL_optint(L, 3, 8192);
  luaL_argcheck(L, max_bytes >= 1 && max_bytes <= 1048576, 3,
                "max_bytes must be 1..1048576");

  int fd = -1;
  if (strcmp(stream, "stdout") == 0) {
    fd = c->stdout_fd;
  } else if (strcmp(stream, "stderr") == 0) {
    fd = c->stderr_fd;
  } else {
    return luaL_argerror(L, 2, "stream must be 'stdout' or 'stderr'");
  }
  if (fd < 0) {
    lua_pushliteral(L, "");
    lua_pushboolean(L, 1);
    return 2;
  }

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
    r = read(fd, buf, (size_t)max_bytes);
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

static int l_proc_write(lua_State *L) {
  struct proc_child *c = check_child(L, 1, 0);
  size_t len = 0;
  const char *data = luaL_checklstring(L, 2, &len);
  int start_idx = luaL_optint(L, 3, 1);
  luaL_argcheck(L, start_idx >= 1, 3, "start_idx must be >= 1");

  if (c->stdin_fd < 0) {
    lua_pushnil(L);
    lua_pushliteral(L, "stdin pipe is closed");
    return 2;
  }

  size_t offset = (size_t)(start_idx - 1);
  if (offset >= len) {
    lua_pushinteger(L, 0);
    return 1;
  }

  struct sigaction sa_ign, sa_old;
  memset(&sa_ign, 0, sizeof(sa_ign));
  sa_ign.sa_handler = SIG_IGN;
  sigemptyset(&sa_ign.sa_mask);
  int restored = (sigaction(SIGPIPE, &sa_ign, &sa_old) == 0);

  ssize_t w;
  for (;;) {
    w = write(c->stdin_fd, data + offset, len - offset);
    if (w < 0 && errno == EINTR) {
      continue;
    }
    break;
  }
  int en = errno;
  if (restored) {
    (void)sigaction(SIGPIPE, &sa_old, NULL);
  }

  if (w >= 0) {
    lua_pushinteger(L, (lua_Integer)w);
    return 1;
  }
  if (en == EAGAIN || en == EWOULDBLOCK) {
    lua_pushinteger(L, 0);
    return 1;
  }
  lua_pushnil(L);
  lua_pushstring(L, strerror(en));
  return 2;
}

static int l_proc_close_stdin(lua_State *L) {
  struct proc_child *c = check_child(L, 1, 0);
  safe_close(&c->stdin_fd);
  lua_pushboolean(L, 1);
  return 1;
}

static void push_wait_table(lua_State *L, const struct proc_child *c) {
  lua_createtable(L, 0, 4);
  lua_pushboolean(L, 1);
  lua_setfield(L, -2, "done");
  lua_pushboolean(L, c->exit_ok);
  lua_setfield(L, -2, "ok");
  lua_pushstring(L, c->exit_why);
  lua_setfield(L, -2, "why");
  lua_pushinteger(L, c->exit_code);
  lua_setfield(L, -2, "code");
}

static int l_proc_wait(lua_State *L) {
  struct proc_child *c = check_child(L, 1, 0);
  int nohang = 0;
  if (!lua_isnoneornil(L, 2)) {
    luaL_checktype(L, 2, LUA_TBOOLEAN);
    nohang = lua_toboolean(L, 2);
  }

  if (c->waited) {
    push_wait_table(L, c);
    return 1;
  }

  int status = 0;
  pid_t w;
  for (;;) {
    w = waitpid(c->pid, &status, nohang ? WNOHANG : 0);
    if (w < 0 && errno == EINTR) {
      continue;
    }
    break;
  }

  if (w == 0) {
    lua_createtable(L, 0, 1);
    lua_pushboolean(L, 0);
    lua_setfield(L, -2, "done");
    return 1;
  }
  if (w < 0) {
    int en = errno;
    lua_pushnil(L);
    lua_pushstring(L, strerror(en));
    return 2;
  }

  record_wait_status(c, status);
  push_wait_table(L, c);
  return 1;
}

static int parse_kill_sig(const char *s) {
  if (strncmp(s, "SIG", 3) == 0) {
    s += 3;
  }
  if (strcmp(s, "TERM") == 0) return SIGTERM;
  if (strcmp(s, "KILL") == 0) return SIGKILL;
  if (strcmp(s, "INT") == 0) return SIGINT;
  if (strcmp(s, "HUP") == 0) return SIGHUP;
  if (strcmp(s, "QUIT") == 0) return SIGQUIT;
  if (strcmp(s, "USR1") == 0) return SIGUSR1;
  if (strcmp(s, "USR2") == 0) return SIGUSR2;
  if (strcmp(s, "ALRM") == 0) return SIGALRM;
  if (strcmp(s, "CONT") == 0) return SIGCONT;
  if (strcmp(s, "STOP") == 0) return SIGSTOP;
  if (strcmp(s, "0") == 0) return 0;
  return -1;
}

static int l_proc_kill(lua_State *L) {
  struct proc_child *c = check_child(L, 1, 0);
  const char *sig_name = luaL_checkstring(L, 2);
  int group = 0;
  if (!lua_isnoneornil(L, 3)) {
    luaL_checktype(L, 3, LUA_TBOOLEAN);
    group = lua_toboolean(L, 3);
  }
  int signo = parse_kill_sig(sig_name);
  if (signo < 0) {
    return luaL_argerror(L, 2, "unsupported signal name");
  }

  /* Never signal a PID that has already been reaped. */
  if (c->waited) {
    lua_pushboolean(L, 1);
    return 1;
  }

  pid_t target = (group && c->new_pgid) ? -c->pid : c->pid;
  if (kill(target, signo) == 0 || errno == ESRCH) {
    lua_pushboolean(L, 1);
    return 1;
  }
  int en = errno;
  lua_pushboolean(L, 0);
  lua_pushstring(L, strerror(en));
  return 2;
}

static int l_proc_close(lua_State *L) {
  struct proc_child *c = check_child(L, 1, 1);
  child_cleanup(c);
  lua_pushboolean(L, 1);
  return 1;
}

static int l_proc_child_gc(lua_State *L) {
  struct proc_child *c = check_child(L, 1, 1);
  child_cleanup(c);
  return 0;
}

static int l_proc_child_tostring(lua_State *L) {
  struct proc_child *c = check_child(L, 1, 1);
  if (c->closed) {
    lua_pushliteral(L, "proc.child (closed)");
  } else {
    lua_pushfstring(L, "proc.child (pid=%d)", (int)c->pid);
  }
  return 1;
}

static const struct luaL_Reg proclib[] = {
    {"exec", l_proc_exec},
    {"run", l_proc_run},
    {"spawn", l_proc_spawn},
    {"pid", l_proc_pid},
    {"stdin_fd", l_proc_stdin_fd},
    {"stdout_fd", l_proc_stdout_fd},
    {"stderr_fd", l_proc_stderr_fd},
    {"read", l_proc_read},
    {"write", l_proc_write},
    {"close_stdin", l_proc_close_stdin},
    {"wait", l_proc_wait},
    {"kill", l_proc_kill},
    {"close", l_proc_close},
    {NULL, NULL},
};

LUALIB_API int luaopen_proc(lua_State *L) {
  if (luaL_newmetatable(L, LUAM_PROC_CHILD_MT)) {
    lua_pushcfunction(L, l_proc_child_gc);
    lua_setfield(L, -2, "__gc");
    lua_pushcfunction(L, l_proc_child_tostring);
    lua_setfield(L, -2, "__tostring");
  }
  lua_pop(L, 1);

  lua_newtable(L);
  luaL_register(L, NULL, proclib);
  return 1;
}
