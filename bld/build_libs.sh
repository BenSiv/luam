#!/bin/bash
# Build script for external modules

echo "Building modules"
mkdir -p log
LOG_FILE="$(pwd)/log/libs.log"
: > "$LOG_FILE"

# Modules that failed to build. Any failure makes the script exit 1, and
# only a complete build writes obj/libs.built, so callers (seder's
# "luam libs" step) never take a partial build for a finished one.
FAILED=()
fail() {
    echo "Failed to build $1"
    FAILED+=("$1")
}

VERBOSE=0
for arg in "$@"; do
    case $arg in
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
    esac
done

run_cmd() {
    if [ "$VERBOSE" -eq 1 ]; then
        "$@"
    else
        "$@" >> "$LOG_FILE" 2>&1
    fi
}

# Ensure lib directory exists
mkdir -p lib
mkdir -p lib/socket
mkdir -p lib/mime
mkdir -p lib/ssl

# 1. LuaFileSystem (lfs)
if [ -d "lib/lfs/src" ]; then
    echo "Compiling lfs.so"
    run_cmd gcc -O2 -shared -fPIC -Isrc/ -o lib/lfs/lfs.so lib/lfs/src/lfs.c
    if [ $? -eq 0 ]; then
        echo "lfs.so built successfully"
    else
        fail "lfs.so"
    fi
else
    echo "Skipping lfs (source not found)"
fi

# 2. Lua-ML
if [ -d "lib/yaml" ]; then
    echo "Compiling yaml.so"
    run_cmd gcc -O2 -shared -fPIC -Isrc/ -Ilib/yaml -o lib/yaml/yaml.so lib/yaml/*.c
    if [ $? -eq 0 ]; then
        echo "yaml.so built successfully"
    else
        fail "yaml.so"
    fi
else
    echo "Skipping yaml (source not found)"
fi

# 3. SQLite (lsqlite3)
if [ -d "lib/sqlite" ]; then
    echo "Compiling lsqlite3.so"
    run_cmd gcc -O2 -shared -fPIC -Isrc/ -o lib/sqlite/lsqlite3.so lib/sqlite/lsqlite3.c -lsqlite3
    if [ $? -eq 0 ]; then
        echo "lsqlite3.so built successfully"
    else
        fail "lsqlite3.so (-lsqlite3 missing?)"
    fi
else
    echo "Skipping sqlite (source not found)"
fi

# 3b. bcrypt -- a thin binding over the platform's own crypt_gensalt/
# crypt_r bcrypt support (glibc/libxcrypt), not a vendored bcrypt
# implementation -- see lib/bcrypt/bcrypt.c's own header comment.
if [ -d "lib/bcrypt" ]; then
    echo "Compiling bcrypt.so"
    run_cmd gcc -O2 -shared -fPIC -Isrc/ -o lib/bcrypt/bcrypt.so lib/bcrypt/bcrypt.c -lcrypt
    if [ $? -eq 0 ]; then
        echo "bcrypt.so built successfully"
    else
        fail "bcrypt.so (-lcrypt missing?)"
    fi
else
    echo "Skipping bcrypt (source not found)"
fi

# 3c. hmac -- a thin binding over OpenSSL libcrypto's HMAC-SHA256, not
# a vendored/hand-rolled implementation -- see lib/hmac/hmac.c's own
# header comment.
if [ -d "lib/hmac" ]; then
    echo "Compiling hmac.so"
    run_cmd gcc -O2 -shared -fPIC -Isrc/ -o lib/hmac/hmac.so lib/hmac/hmac.c -lcrypto
    if [ $? -eq 0 ]; then
        echo "hmac.so built successfully"
    else
        fail "hmac.so (-lcrypto missing?)"
    fi
else
    echo "Skipping hmac (source not found)"
fi

# 3d. mariadb -- a thin binding over MariaDB Connector/C (libmariadb),
# not a vendored client implementation -- see lib/mariadb/lmariadb.c's
# own header comment. Debian/Ubuntu's libmariadb-dev package ships
# headers under /usr/include/mariadb (not the plain -I/usr/include
# default), hence the extra -I flags; `mariadb_config --cflags --libs`
# confirms this layout directly rather than guessing it.
if [ -d "lib/mariadb" ]; then
    echo "Compiling mariadb.so"
    run_cmd gcc -O2 -shared -fPIC -Isrc/ -I/usr/include/mariadb -I/usr/include/mariadb/mysql \
        -o lib/mariadb/mariadb.so lib/mariadb/lmariadb.c -lmariadb
    if [ $? -eq 0 ]; then
        echo "mariadb.so built successfully"
    else
        fail "mariadb.so (-lmariadb / libmariadb-dev missing?)"
    fi
else
    echo "Skipping mariadb (source not found)"
fi

# 4. LuaSocket
if [ -d "lib/socket/src" ]; then
    echo "Compiling socket.core.so"
    # Copy Lua files to lib/ structure. The copies are tracked too, so -p
    # keeps an unchanged copy's mtime: a build must not make tracked files
    # look edited (downstream rebuild checks, e.g. seder's, compare them).
    run_cmd cp -p lib/socket/src/socket.lua lib/socket/init.lua
    run_cmd cp -p lib/socket/src/mime.lua lib/mime/init.lua
    run_cmd cp -p lib/socket/src/ltn12.lua lib/ltn12/init.lua
    run_cmd cp -p lib/socket/src/{ftp,http,smtp,tp,url,headers,mbox}.lua lib/socket/

    # Compile Socket Core (Linux files)
    run_cmd gcc -O2 -shared -fPIC -Isrc/ -Ilib/socket/src \
        -DLUASOCKET_DEBUG \
        -o lib/socket/core.so \
        lib/socket/src/{luasocket,timeout,buffer,io,auxiliar,compat,options,inet,tcp,udp,except,select,usocket}.c
    
    if [ $? -eq 0 ]; then
        echo "socket.core.so built successfully"
    else
        fail "socket.core.so"
    fi

    echo "Compiling mime.core.so"
    run_cmd gcc -O2 -shared -fPIC -Isrc/ -Ilib/socket/src \
        -DLUASOCKET_DEBUG \
        -o lib/mime/core.so \
        lib/socket/src/{mime,compat}.c
    
    if [ $? -eq 0 ]; then
        echo "mime.core.so built successfully"
    else
        fail "mime.core.so"
    fi
else
    echo "Skipping socket (source not found)"
fi

# 5. LuaSec (ssl)
if [ -d "lib/ssl/src" ]; then
    echo "Compiling ssl.core.so"

    # Vendor OpenSSL
    OPENSSL_VER="1.1.1w"
    OPENSSL_DIR="$(pwd)/dep/openssl-${OPENSSL_VER}"
    OPENSSL_TAR="openssl-${OPENSSL_VER}.tar.gz"
    # Upstream's published SHA-256 (openssl.org/source/openssl-1.1.1w.tar.gz.sha256).
    OPENSSL_SHA256="cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8"
    # GitHub releases first (where openssl.org redirects), then Debian's copy
    # of the same upstream tarball -- byte-identical, checked by the hash.
    # Cloud Build could not reach GitHub's release assets for hours on
    # 2026-11-08 (wget retried ~4.5 min, then failed) while deb.debian.org,
    # which apt already uses there, kept working.
    OPENSSL_URLS="https://github.com/openssl/openssl/releases/download/OpenSSL_${OPENSSL_VER//./_}/$OPENSSL_TAR https://deb.debian.org/debian/pool/main/o/openssl/openssl_${OPENSSL_VER}.orig.tar.gz"
    
    mkdir -p dep
    if [ ! -d "$OPENSSL_DIR" ]; then
        echo "Downloading OpenSSL ${OPENSSL_VER}"
        if [ ! -f "dep/$OPENSSL_TAR" ]; then
            cd dep
            # Follow redirects (-L), fail on HTTP errors (-f), and give up on
            # a source quickly so the next one gets its turn.
            for OPENSSL_URL in $OPENSSL_URLS; do
                rm -f "$OPENSSL_TAR"
                if command -v curl > /dev/null 2>&1; then
                    curl -fsSL --connect-timeout 20 --max-time 180 --retry 2 -o "$OPENSSL_TAR" "$OPENSSL_URL" || rm -f "$OPENSSL_TAR"
                else
                    wget -q --tries=2 --timeout=30 -O "$OPENSSL_TAR" "$OPENSSL_URL" || rm -f "$OPENSSL_TAR"
                fi
                if [ -s "$OPENSSL_TAR" ]; then
                    if ! command -v sha256sum > /dev/null 2>&1; then
                        echo "sha256sum not found: not verifying $OPENSSL_TAR"
                        break
                    fi
                    if [ "$(sha256sum "$OPENSSL_TAR" | cut -d' ' -f1)" = "$OPENSSL_SHA256" ]; then
                        echo "OpenSSL from $OPENSSL_URL (sha256 ok)"
                        break
                    fi
                    echo "OpenSSL from $OPENSSL_URL has the wrong sha256; discarded"
                    rm -f "$OPENSSL_TAR"
                else
                    echo "Could not download OpenSSL from $OPENSSL_URL"
                fi
            done
            [ -s "$OPENSSL_TAR" ] || { echo "Failed to download OpenSSL from any of: $OPENSSL_URLS"; exit 1; }
            cd ..
        fi
        echo "Extracting OpenSSL"
        cd dep
        run_cmd tar -xzf "$OPENSSL_TAR" || { rm -f "$OPENSSL_TAR"; echo "Failed to extract dep/$OPENSSL_TAR"; exit 1; }
        cd "openssl-${OPENSSL_VER}"
        echo "Configuring OpenSSL (static)"
        run_cmd ./config no-shared no-tests
        echo "Building OpenSSL"
        run_cmd make -j$(nproc)
        cd ../..
    fi

    # Copy Lua files
    run_cmd cp -p lib/ssl/src/ssl.lua lib/ssl/init.lua
    run_cmd cp -p lib/ssl/src/https.lua lib/ssl/

    # Compile SSL Core
    # Link against local OpenSSL static libs
    run_cmd gcc -O2 -shared -fPIC -Isrc/ -Ilib/ssl/src -Ilib/socket/src \
        -I"$OPENSSL_DIR/include" \
        -o lib/ssl/core.so \
        lib/ssl/src/{options,x509,context,ssl,config,ec}.c \
        "$OPENSSL_DIR/libssl.a" "$OPENSSL_DIR/libcrypto.a" \
        lib/socket/core.so -ldl -lpthread

    if [ $? -eq 0 ]; then
        echo "ssl.core.so built successfully"
        # Create symlinks for context, x509, config
        cd lib/ssl
        run_cmd ln -sf core.so context.so
        run_cmd ln -sf core.so x509.so
        run_cmd ln -sf core.so config.so
        cd ../..
        echo "Symlinks created for ssl modules"
    else
        fail "ssl.core.so (openssl dev libs missing?)"
    fi
else
    echo "Skipping ssl (source not found)"
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "Build incomplete, failed: ${FAILED[*]} (details in $LOG_FILE)" >&2
    exit 1
fi

mkdir -p obj
touch obj/libs.built
echo "Build complete"
