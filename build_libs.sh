#!/bin/bash
# Build script for external modules

echo "Building modules..."

# Ensure lib directory exists
mkdir -p lib
mkdir -p lib/socket
mkdir -p lib/mime
mkdir -p lib/ssl

# 1. LuaFileSystem (lfs)
if [ -d "lib/filesystem/src" ]; then
    echo "Compiling lfs.so..."
    gcc -O2 -shared -fPIC -I src/ -o lib/lfs.so lib/filesystem/src/lfs.c
    if [ $? -eq 0 ]; then
        echo "lfs.so built successfully."
    else
        echo "Failed to build lfs.so"
    fi
else
    echo "Skipping lfs (source not found)"
fi

# 2. Lua-YAML
if [ -d "lib/yaml" ]; then
    echo "Compiling yaml.so..."
    gcc -O2 -shared -fPIC -I src/ -I lib/yaml -o lib/yaml.so lib/yaml/*.c
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
    gcc -O2 -shared -fPIC -I src/ -o lib/lsqlite3.so lib/sqlite/lsqlite3.c -lsqlite3
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
    cp lib/socket/src/socket.lua lib/
    cp lib/socket/src/mime.lua lib/
    cp lib/socket/src/ltn12.lua lib/
    cp lib/socket/src/{ftp,http,smtp,tp,url,headers,mbox}.lua lib/socket/

    # Compile Socket Core (Linux files)
    gcc -O2 -shared -fPIC -I src/ -I lib/socket/src \
        -DLUASOCKET_NODEBUG \
        -o lib/socket/core.so \
        lib/socket/src/{luasocket,timeout,buffer,io,auxiliar,compat,options,inet,tcp,udp,except,select,usocket}.c
    
    if [ $? -eq 0 ]; then
        echo "socket.core.so built successfully."
    else
        echo "Failed to build socket.core.so"
    fi

    echo "Compiling mime.core.so..."
    gcc -O2 -shared -fPIC -I src/ -I lib/socket/src \
        -DLUASOCKET_NODEBUG \
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
    # Copy Lua files
    cp lib/ssl/src/ssl.lua lib/
    cp lib/ssl/src/https.lua lib/ssl/

    # Compile SSL Core
    # We link against socket.core.so to satisfy socket symbols if needed, and system openssl
    gcc -O2 -shared -fPIC -I src/ -I lib/ssl/src -I lib/socket/src \
        -o lib/ssl/core.so \
        lib/ssl/src/{options,x509,context,ssl,config,ec}.c \
        -lssl -lcrypto lib/socket/core.so

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

echo "Build complete."
