#!/bin/bash
# Build script for external modules

echo "Building modules..."

# Ensure lib directory exists
mkdir -p lib
mkdir -p lib/socket
mkdir -p lib/mime
mkdir -p lib/ssl

# 1. LuaFileSystem (lfs)
if [ -d "lib/lfs/src" ]; then
    echo "Compiling lfs.so..."
    gcc -O2 -shared -fPIC -Isrc/ -o lib/lfs/lfs.so lib/lfs/src/lfs.c
    if [ $? -eq 0 ]; then
        echo "lfs.so built successfully."
    else
        echo "Failed to build lfs.so"
    fi
else
    echo "Skipping lfs (source not found)"
fi

# 2. Lua-ML
if [ -d "lib/yaml" ]; then
    echo "Compiling yaml.so..."
    gcc -O2 -shared -fPIC -Isrc/ -Ilib/yaml -o lib/yaml/yaml.so lib/yaml/*.c
    if [ $? -eq 0 ]; then
        echo "yaml.so built successfully."
    else
        echo "Failed to build yaml.so"
    fi
else
    echo "Skipping yaml (source not found)"
fi

# 3. SQLite (lsqlite3)
if [ -d "lib/sqlite" ]; then
    echo "Compiling lsqlite3.so..."
    gcc -O2 -shared -fPIC -Isrc/ -o lib/sqlite/lsqlite3.so lib/sqlite/lsqlite3.c -lsqlite3
    if [ $? -eq 0 ]; then
        echo "lsqlite3.so built successfully."
    else
        echo "Failed to build lsqlite3.so (-lsqlite3 missing?)"
    fi
else
    echo "Skipping sqlite (source not found)"
fi

# 4. LuaSocket
if [ -d "lib/socket/src" ]; then
    echo "Compiling socket.core.so..."
    # Copy Lua files to lib/ structure
    cp lib/socket/src/socket.lua lib/socket/init.lua
    cp lib/socket/src/mime.lua lib/mime/init.lua
    cp lib/socket/src/ltn12.lua lib/ltn12/init.lua
    cp lib/socket/src/{ftp,http,smtp,tp,url,headers,mbox}.lua lib/socket/

    # Compile Socket Core (Linux files)
    gcc -O2 -shared -fPIC -Isrc/ -Ilib/socket/src \
        -DLUASOCKET_DEBUG \
        -o lib/socket/core.so \
        lib/socket/src/{luasocket,timeout,buffer,io,auxiliar,compat,options,inet,tcp,udp,except,select,usocket}.c
    
    if [ $? -eq 0 ]; then
        echo "socket.core.so built successfully."
    else
        echo "Failed to build socket.core.so"
    fi

    echo "Compiling mime.core.so..."
    gcc -O2 -shared -fPIC -Isrc/ -Ilib/socket/src \
        -DLUASOCKET_DEBUG \
        -o lib/mime/core.so \
        lib/socket/src/{mime,compat}.c
    
    if [ $? -eq 0 ]; then
        echo "mime.core.so built successfully."
    else
        echo "Failed to build mime.core.so"
    fi
else
    echo "Skipping socket (source not found)"
fi

# 5. LuaSec (ssl)
if [ -d "lib/ssl/src" ]; then
    echo "Compiling ssl.core.so..."

    # Vendor OpenSSL
    OPENSSL_VER="1.1.1w"
    OPENSSL_DIR="$(pwd)/dep/openssl-${OPENSSL_VER}"
    OPENSSL_TAR="openssl-${OPENSSL_VER}.tar.gz"
    
    mkdir -p dep
    if [ ! -d "$OPENSSL_DIR" ]; then
        echo "Downloading OpenSSL ${OPENSSL_VER}..."
        if [ ! -f "dep/$OPENSSL_TAR" ]; then
            cd dep
            wget "https://www.openssl.org/source/$OPENSSL_TAR" || curl -O "https://www.openssl.org/source/$OPENSSL_TAR"
            cd ..
        fi
        echo "Extracting OpenSSL..."
        cd dep
        tar -xzf "$OPENSSL_TAR"
        cd "openssl-${OPENSSL_VER}"
        echo "Configuring OpenSSL (static)..."
        ./config no-shared no-tests
        echo "Building OpenSSL..."
        make -j$(nproc)
        cd ../..
    fi

    # Copy Lua files
    cp lib/ssl/src/ssl.lua lib/ssl/init.lua
    cp lib/ssl/src/https.lua lib/ssl/


    # Compile SSL Core
    # Link against local OpenSSL static libs
    gcc -O2 -shared -fPIC -Isrc/ -Ilib/ssl/src -Ilib/socket/src \
        -I"$OPENSSL_DIR/include" \
        -o lib/ssl/core.so \
        lib/ssl/src/{options,x509,context,ssl,config,ec}.c \
        "$OPENSSL_DIR/libssl.a" "$OPENSSL_DIR/libcrypto.a" \
        lib/socket/core.so -ldl -lpthread

    if [ $? -eq 0 ]; then
        echo "ssl.core.so built successfully."
        # Create symlinks for context, x509, config
        cd lib/ssl
        ln -sf core.so context.so
        ln -sf core.so x509.so
        ln -sf core.so config.so
        cd ../..
        echo "Symlinks created for ssl modules."
    else
        echo "Failed to build ssl.core.so (openssl dev libs missing?)"
    fi
else
    echo "Skipping ssl (source not found)"
fi

# 6. Static ool
if [ -d "lib/static" ]; then
    echo "nstalling static tool..."
    cp lib/static/static.lua lib/static/init.lua
    chmod +x lib/static/init.lua
    echo "static tool installed to lib/static/init.lua"
else
    echo "Skipping static tool (source not found)"
fi

echo "Build complete."
