INSTALL for Luam

* Building the Core Language (`bld/build_lang.sh`)
  ------------------------------------------------
  Luam builds with a standard Lua-5.1-style `make`, wrapped by a helper
  script. There is no xmake dependency — the `bin/luam` you get is a plain
  `make linux` build (linking built-in `bit` and `struct` directly into the VM).

    ./bld/build_lang.sh          # make clean && make linux
    ./bld/build_lang.sh -v       # same, verbose (make ... V=1)

  Core build artifacts:

    obj/liblua.a    static Luam VM library (used by static downstream builds)
    bin/luam        interactive interpreter
    bin/luamc       bytecode compiler

  To target a platform other than Linux, call `make` directly from the repo
  root with one of the supported platform targets (see `Makefile`):

    make aix | ansi | bsd | freebsd | generic | linux | macosx | mingw | posix | solaris

* Building C Extension Modules (`bld/build_libs.sh`)
  --------------------------------------------------
  Shared C extension modules under `lib/` are built separately with:

    ./bld/build_libs.sh          # writes log/libs.log and obj/libs.built
    ./bld/build_libs.sh -v       # verbose compiler output

  This compiles:

    lib/lfs/lfs.so           LuaFileSystem (`lfs`)
    lib/sqlite3.so           SQLite3 binding (`sqlite3`, symlinked at `lib/sqlite/lsqlite3.so` and `bin/sqlite3.so`; needs `-lsqlite3`)
    lib/mariadb/mariadb.so   MariaDB Connector/C binding (`mariadb`; needs `-lmariadb`)
    lib/bcrypt/bcrypt.so     Password hashing (`bcrypt`; needs `-lcrypt`)
    lib/crypto/crypto.so     SHA-256, HMAC-SHA256, CSPRNG (`crypto`; needs `-lcrypto` / `libssl-dev`)
    lib/hmac/hmac.so         HMAC-SHA256 retained alias (`hmac`; needs `-lcrypto` / `libssl-dev`)
    lib/vec/vec.so           Dense float32 vector operations (`vec`)
    lib/yaml/yaml.so         YAML parser/emitter (`yaml`, vendored LibYAML)

  Note: Downstream projects built as standalone static binaries via
  `lib/static/build.lua` require `obj/liblua.a` (from `bld/build_lang.sh`) AND
  `lib/lfs/lfs.so` (from `bld/build_libs.sh`, or compiled directly from
  `lib/lfs/src/lfs.c`) because `lib/static/build.lua` uses `lfs` while scanning
  source trees.

* Testing Luam & the Stack
  ------------------------
  Run the full core language and `lib/` test suite via `make test`:

    make test                    # sets LUA_PATH/LUA_CPATH and runs ./bin/luam tst/run_tests.lua

  To rebuild `luam`, rebuild `lib/` C extensions, run `make test`, and run
  `bld/test.sh` across every sibling Luam-stack checkout (`daat`, `brain-ex`,
  `teken`, `seder`, `camopass`, `luametry`, `automations`):

    ./bld/test_stack.sh
    ./bld/test_stack.sh --skip-luam-build teken seder automations

  See `tst/README` for notes on the classic sample programs included in `tst/`.

* Installing Luam & Environment Wiring
  ------------------------------------
  For ad-hoc installs, copy `bin/luam`, `bin/luamc`, and `lib/` to wherever your
  `$PATH`, `LUA_PATH`, and `LUA_CPATH` expect them.

  In practice, Luam-stack environments are provisioned atomically with `teken`
  (see [teken design](../../teken/doc/design.md) and
  [configs/teken](../../configs/teken/README.md)), which installs `bin/luam`
  into the active generation's `bin/` and sets `LUAM_LIB` so shell sessions
  configure `LUA_PATH` and `LUA_CPATH` against the matching `lib/` tree.

(end of INSTALL)
