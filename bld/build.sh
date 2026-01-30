# Get script directory (bld/)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Root is one level up
PROJECT_ROOT="$DIR/.."

cd "$PROJECT_ROOT"

# Compile the C library and objects using the existing Makefile
echo "Building C library..."
cd src
make clean
make o a MYCFLAGS=-DLUA_USE_LINUX
cd ..

# Ensure build directory exists
mkdir -p bin

# Build Odin executable
echo "Building Odin executable..."
# We need to make sure Odin symbols for luaL_openlibs etc are used instead of what's in liblua.a if it still contains them.
# Given Makefile edits, they shouldn't be there, but we can be explicit.
odin build src -out:bin/luam_odin -extra-linker-flags:"obj/lua.o obj/liblua.a -ldl -lm -lreadline -rdynamic"

echo "Build complete: bin/luam_odin"

# Run tests
echo "Running tests..."
export LUAM_BIN="./bin/luam_odin"
./bld/test.sh
