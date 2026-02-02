#!/bin/bash
set -e

VERBOSE=0
if [[ "$1" == "-v" || "$1" == "--verbose" ]]; then
    VERBOSE=1
fi

status() {
    echo "- $@"
}

log() {
    if [ $VERBOSE -eq 1 ]; then
        echo "$@"
    fi
}

mkdir -p bin

# Helper for Unity Build of Libs
build_lib() {
    local name=$1
    local output=$2
    local src_pattern=$3
    local extra_flags=$4
    local includes=$5
    
    status "Building $name..."
    local blob="bin/${name}_blob.c"
    echo "/* Unity Build for $name */" > "$blob"
    
    > "$blob"
    for f in $src_pattern; do
        if [ -f "$f" ]; then
             log "Processing $f"
             echo "/* SOURCE: $f */" >> "$blob"
             # Do NOT comment out includes, so external headers are found.
             cat "$f" >> "$blob"
             echo "" >> "$blob"
        fi
    done

    # Allow custom includes via flags
    gcc -std=gnu99 -O2 -shared -fPIC -Wall -Wextra \
        -Isrc/ -Isrc/core/defs -Isrc/api/aux -Isrc/api/lua \
        $includes \
        $extra_flags \
        -o "$output" \
        "$blob"
        
    if [ $? -eq 0 ]; then
        log "$name built successfully."
    else
        status "Failed to build $name"
    fi
    rm -f "$blob"
}

# Helper for Object-based Build (Avoids Unity Build conflicts)
build_lib_objs() {
    local name=$1
    local output=$2
    local src_pattern=$3
    local extra_flags=$4
    local includes=$5
    
    status "Building $name (via objects)..."
    local objs=""
    
    for f in $src_pattern; do
        if [ -f "$f" ]; then
             local obj="bin/${name}_$(basename "$f" .c).o"
             # Compile object
             gcc -std=gnu99 -O2 -fPIC -Wall -Wextra \
                -Isrc/ -Isrc/core/defs -Isrc/api/aux -Isrc/api/lua \
                $includes \
                $extra_flags \
                -c "$f" -o "$obj" > /dev/null 2>&1
             
             if [ $? -ne 0 ]; then
                status "Failed to compile $f"
                # Retry verbose
                gcc -std=gnu99 -O2 -fPIC -Wall -Wextra \
                    -Isrc/ -Isrc/core/defs -Isrc/api/aux -Isrc/api/lua \
                    $includes \
                    $extra_flags \
                    -c "$f" -o "$obj"
                return 1
             fi
             objs="$objs $obj"
        fi
    done

    # Link objects
    gcc -std=gnu99 -shared -fPIC \
        -o "$output" \
        $objs \
        $extra_flags
        
    if [ $? -eq 0 ]; then
        log "$name built successfully."
    else
        status "Failed to link $name"
    fi
    rm -f $objs
}

# 1. LuaFileSystem
build_lib "lfs" "bin/lfs.so" "lib/lfs/src/lfs.c" "" "-Ilib/lfs/src"

# 2. YAML
YAML_SRC="lib/yaml/api.c lib/yaml/b64.c lib/yaml/dumper.c lib/yaml/emitter.c lib/yaml/loader.c lib/yaml/lyaml.c lib/yaml/parser.c lib/yaml/reader.c lib/yaml/scanner.c lib/yaml/writer.c"
# Add -include limits.h to fix INT_MAX error in Unity Build
build_lib "yaml" "bin/yaml.so" "$YAML_SRC" "-include limits.h" "-Ilib/yaml"

# 3. SQLite
if [ -f "lib/sqlite/sqlite3.c" ]; then
    build_lib "sqlite3" "bin/lsqlite3.so" "lib/sqlite/lsqlite3.c lib/sqlite/sqlite3.c" "-lpthread -ldl -D_GNU_SOURCE" "-Ilib/sqlite"
else
    build_lib "sqlite3" "bin/lsqlite3.so" "lib/sqlite/lsqlite3.c" "-lsqlite3" "-Ilib/sqlite"
fi

# 4. LuaSocket - Use build_lib_objs to avoid static symbol conflicts
# Core
SOCKET_SRC="lib/socket/src/luasocket.c lib/socket/src/timeout.c lib/socket/src/buffer.c lib/socket/src/io.c lib/socket/src/auxiliar.c lib/socket/src/compat.c lib/socket/src/options.c lib/socket/src/inet.c lib/socket/src/tcp.c lib/socket/src/udp.c lib/socket/src/except.c lib/socket/src/select.c lib/socket/src/usocket.c"
mkdir -p bin/socket
build_lib_objs "socket.core" "bin/socket/core.so" "$SOCKET_SRC" "-DLUASOCKET_DEBUG" "-Ilib/socket/src"

# Mime
MIME_SRC="lib/socket/src/mime.c lib/socket/src/compat.c"
mkdir -p bin/mime
build_lib_objs "mime.core" "bin/mime/core.so" "$MIME_SRC" "-DLUASOCKET_DEBUG" "-Ilib/socket/src"

# 5. Struct
build_lib "struct" "bin/struct.so" "lib/struct/struct.c" "" "-Ilib/struct"

# Copy lua files for libs
status "Installing Lua files for libs"
mkdir -p bin/socket bin/mime bin/ssl
cp lib/socket/src/socket.lua bin/socket.lua 2>/dev/null || true
cp lib/socket/src/ftp.lua bin/socket/ 2>/dev/null || true
cp lib/socket/src/http.lua bin/socket/ 2>/dev/null || true
cp lib/socket/src/smtp.lua bin/socket/ 2>/dev/null || true
cp lib/socket/src/tp.lua bin/socket/ 2>/dev/null || true
cp lib/socket/src/url.lua bin/socket/ 2>/dev/null || true
cp lib/socket/src/headers.lua bin/socket/ 2>/dev/null || true
cp lib/socket/src/mbox.lua bin/socket/ 2>/dev/null || true
cp lib/socket/src/ltn12.lua bin/ltn12.lua 2>/dev/null || true
cp lib/socket/src/mime.lua bin/mime.lua 2>/dev/null || true

status "Library build complete"
