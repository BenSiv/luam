#!/bin/bash
set -e

VERBOSE=0
if [[ "$1" == "-v" || "$1" == "--verbose" ]]; then
    VERBOSE=1
fi

log() {
    if [ $VERBOSE -eq 1 ]; then
        echo "$@"
    fi
}

status() {
    echo "- $@"
}

SRC_DIR="src"
BIN_DIR="bin"
mkdir -p "$BIN_DIR"

status "Building dependency graph"

# 1. Map all filenames to full paths
declare -A FILE_MAP
while IFS= read -r file; do
    name=$(basename "$file")
    FILE_MAP["$name"]="$file"
done < <(/usr/bin/find "$SRC_DIR" -name "*.[ch]" -type f)

# 2. Extract dependencies
DEPS_FILE="$BIN_DIR/deps.txt"
> "$DEPS_FILE"

ALL_FILES_LIST="$BIN_DIR/all_files.txt"
/usr/bin/find "$SRC_DIR" -name "*.[ch]" -type f > "$ALL_FILES_LIST"

while read -r file; do
    grep -E '^#include "[^"]+"' "$file" | while read -r line; do
        inc_name=$(echo "$line" | sed 's/#include "//; s/"//')
        dependency_file="${FILE_MAP[$inc_name]}"
        if [ -n "$dependency_file" ] && [ "$dependency_file" != "$file" ]; then
            echo "$dependency_file $file" >> "$DEPS_FILE"
        fi
    done || true
done < "$ALL_FILES_LIST"

# 3. Topological Sort
log "Sorting dependencies..."
ORDERED_FILES=$(tsort "$DEPS_FILE" 2>/dev/null || true)

if [ -z "$ORDERED_FILES" ]; then
    log "Warning: tsort produced empty output. Order may be random."
    ORDERED_FILES=""
fi

# 4. Concatenate Source
status "Generating source blob"
LIB_BLOB="$BIN_DIR/lib_blob.c"
> "$LIB_BLOB"
echo "/* Auto-generated Unity Build Blob */" > "$LIB_BLOB"

declare -A PROCESSED

process_file() {
    local file=$1
    if [[ "${PROCESSED[$file]}" == "1" ]]; then return; fi
    PROCESSED["$file"]=1
    
    if [[ "$file" == *"src/main/lua/lua.c"* ]] || [[ "$file" == *"src/main/luac/luac.c"* ]] || [[ "$file" == *"src/main/luac/print.c"* ]]; then
        return
    fi
    
    log "Processing $file"
    echo "/* SOURCE: $file */" >> "$LIB_BLOB"
    cat "$file" | sed 's/^#include "/\/\/ SKIP: #include "/' >> "$LIB_BLOB"
    echo "" >> "$LIB_BLOB"
}

for f in $ORDERED_FILES; do
    process_file "$f"
done
sort "$ALL_FILES_LIST" | while read -r f; do
    process_file "$f"
done

# 5. Compile Lua
status "Compiling luam"
LUA_SRC="$BIN_DIR/lua_final.c"
cp "$LIB_BLOB" "$LUA_SRC"
echo "/* SOURCE: src/main/lua/lua.c */" >> "$LUA_SRC"
cat "src/main/lua/lua.c" | sed 's/^#include "/\/\/ SKIP: #include "/' >> "$LUA_SRC"

GCC_OUTPUT="/dev/stdout"
if [ $VERBOSE -eq 0 ]; then
    GCC_OUTPUT="/dev/null"
fi

gcc -std=gnu99 -O2 -Wall -Wextra \
    -DLUA_COMPAT_5_3 -DLUA_USE_POSIX -DLUA_USE_DLOPEN -DLUA_PROGNAME="\"lua\"" -Dluaall_c -DLUA_CORE \
    -Wno-unused-parameter -Wno-unused-function \
    -o "$BIN_DIR/luam" \
    "$LUA_SRC" \
    -lm -ldl -Wl,-E > "$GCC_OUTPUT" 2>&1

# 6. Compile Luac
status "Compiling luamc"
LUAC_SRC="$BIN_DIR/luac_final.c"
cp "$LIB_BLOB" "$LUAC_SRC"
echo "/* SOURCE: src/main/luac/print.c */" >> "$LUAC_SRC"
cat "src/main/luac/print.c" | sed 's/^#include "/\/\/ SKIP: #include "/' >> "$LUAC_SRC"
echo "/* SOURCE: src/main/luac/luac.c */" >> "$LUAC_SRC"
cat "src/main/luac/luac.c" | sed 's/^#include "/\/\/ SKIP: #include "/' >> "$LUAC_SRC"

gcc -std=gnu99 -O2 -Wall -Wextra \
    -DLUA_COMPAT_5_3 -DLUA_USE_POSIX -DLUA_USE_DLOPEN -Dluaall_c -DLUA_CORE \
    -Wno-unused-parameter -Wno-unused-function \
    -o "$BIN_DIR/luamc" \
    "$LUAC_SRC" \
    -lm -ldl > "$GCC_OUTPUT" 2>&1

# Cleanup
status "Cleaning up"
rm -f "$DEPS_FILE" "$ALL_FILES_LIST" "$LIB_BLOB" "$LUA_SRC" "$LUAC_SRC"

status "Build complete"
