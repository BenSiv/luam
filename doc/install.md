INSTALL for Luam

* Building Luam
  -------------
  Luam builds with a standard Lua-5.1-style `make`, wrapped by a helper
  script. There is no xmake dependency — the `bin/luam` you get is a plain
  `make linux` build.

    ./bld/build_lang.sh          # make clean && make linux
    ./bld/build_lang.sh -v       # same, verbose (make ... V=1)

  Build artifacts (interpreter, compiler, sqlite3 module) are placed in
  `bin/`:

    bin/luam        interactive interpreter
    bin/luamc       bytecode compiler
    bin/sqlite3.so  sqlite3 module

  Other C libraries under `lib/` are built separately with:

    ./bld/build_libs.sh

  To target a platform other than Linux, call `make` directly from the repo
  root with one of the supported `PLATS` targets (see `Makefile`):

    make aix | ansi | bsd | freebsd | generic | linux | macosx | mingw | posix | solaris

* Testing Luam
  ------------
  There is no `xmake test`. The regression suite is a plain Lua test runner:

    ./bin/luam tst/run_tests.lua

  See `tst/README` for details on individual test files.

* Installing Luam
  ----------------
  There is no separate install step / installer target in this repo today.
  Copy `bin/luam`, `bin/luamc`, and whichever `lib/*.so` modules you need to
  wherever your `$PATH` / `LUA_CPATH` expects them, the same way you would
  with a stock Lua 5.1 build.

(end of INSTALL)
