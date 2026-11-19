#!/bin/bash
# Build script for Luam C extension modules

echo "Building modules"
mkdir -p log
LOG_FILE="$(pwd)/log/libs.log"
: > "$LOG_FILE"

# Modules that failed to build. Any failure makes the script exit 1, and
# only a complete build writes obj/libs.built, so callers never take a
# partial build for a finished one.
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

mkdir -p lib

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

# 2. YAML (lyaml + vendored LibYAML)
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

# 3. SQLite (lsqlite3 dynamically linked against system -lsqlite3, matching static/build.lua)
if [ -d "lib/sqlite" ]; then
    echo "Compiling sqlite3.so"
    run_cmd gcc -O2 -shared -fPIC -Isrc/ -o lib/sqlite3.so lib/sqlite/lsqlite3.c -lsqlite3
    if [ $? -eq 0 ]; then
        run_cmd ln -sf ../sqlite3.so lib/sqlite/lsqlite3.so
        if [ -d "bin" ]; then
            run_cmd ln -sf ../lib/sqlite3.so bin/sqlite3.so
        fi
        echo "sqlite3.so built successfully"
    else
        fail "sqlite3.so (-lsqlite3 / libsqlite3-dev missing?)"
    fi
else
    echo "Skipping sqlite (source not found)"
fi

# 4. bcrypt -- thin binding over glibc/libxcrypt crypt_gensalt + crypt_r
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

# 5. hmac -- thin binding over OpenSSL libcrypto HMAC-SHA256 (retained alias)
if [ -d "lib/hmac" ]; then
    echo "Compiling hmac.so"
    run_cmd gcc -O2 -shared -fPIC -Isrc/ -o lib/hmac/hmac.so lib/hmac/hmac.c -lcrypto
    if [ $? -eq 0 ]; then
        echo "hmac.so built successfully"
    else
        fail "hmac.so (-lcrypto / libssl-dev missing?)"
    fi
else
    echo "Skipping hmac (source not found)"
fi

# 6. crypto -- SHA-256, HMAC-SHA256, and CSPRNG random bytes/hex over -lcrypto
if [ -d "lib/crypto" ]; then
    echo "Compiling crypto.so"
    run_cmd gcc -O2 -shared -fPIC -Isrc/ -o lib/crypto/crypto.so lib/crypto/crypto.c -lcrypto
    if [ $? -eq 0 ]; then
        echo "crypto.so built successfully"
    else
        fail "crypto.so (-lcrypto / libssl-dev missing?)"
    fi
else
    echo "Skipping crypto (source not found)"
fi

# 7. vec -- dense little-endian float32 vector operations
if [ -d "lib/vec" ]; then
    echo "Compiling vec.so"
    run_cmd gcc -O2 -shared -fPIC -Isrc/ -o lib/vec/vec.so lib/vec/vec.c -lm
    if [ $? -eq 0 ]; then
        echo "vec.so built successfully"
    else
        fail "vec.so"
    fi
else
    echo "Skipping vec (source not found)"
fi

# 8. mariadb -- thin binding over MariaDB Connector/C (libmariadb)
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

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "Build incomplete, failed: ${FAILED[*]} (details in $LOG_FILE)" >&2
    exit 1
fi

mkdir -p obj
touch obj/libs.built
echo "Build complete"
