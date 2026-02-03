INSTALL for LuaM

* Building LuaM
  ------------
  LuaM uses xmake (https://xmake.io) for building.

  To build LuaM, run:
  
    xmake f -o bld -y
    xmake

  This will compile the core library, the interpreter (luam), the compiler (luamc), 
  and the sqlite3 module. All build artifacts, including intermediate files, 
  will be placed in the `bld/` directory.

  If you want to build for a specific platform or architecture, you can use:

    xmake config -p [iphoneos|android|macosx|linux|mingw|...] -a [armv7|arm64|i386|x86_64|...]
    xmake

* Testing LuaM
  ------------
  To verify that LuaM has been built correctly, run:

    xmake test

  This will execute the regression test suite.

* Installing LuaM
  --------------
  To install LuaM to your system, run:

    xmake install -o /usr/local

  You can change the installation prefix using the -o option.

(end of INSTALL)
