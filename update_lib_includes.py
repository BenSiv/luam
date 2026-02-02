
import os
import subprocess

MAPPINGS = {
    "lapi.h": "api.h",
    "lauxlib.h": "auxlib.h",
    "lbaselib.h": "baselib.h",
    "lcode.h": "code.h",
    "ldblib.h": "dblib.h",
    "ldebug.h": "debug.h",
    "ldo.h": "do.h",
    "ldump.h": "dump.h",
    "lfunc.h": "func.h",
    "lgc.h": "gc.h",
    "linit.h": "init.h",
    "liolib.h": "iolib.h",
    "llex.h": "lex.h",
    "llimits.h": "limits.h",
    "lmathlib.h": "mathlib.h",
    "lmem.h": "mem.h",
    "lobject.h": "object.h",
    "lopcodes.h": "opcodes.h",
    "loslib.h": "oslib.h",
    "lparser.h": "parser.h",
    "lstate.h": "state.h",
    "lstring.h": "string.h",
    "lstrlib.h": "strlib.h",
    "ltable.h": "table.h",
    "ltablib.h": "tablib.h",
    "ltm.h": "tm.h",
    "lundump.h": "undump.h",
    "lvm.h": "vm.h",
    "lzio.h": "zio.h",
}

def run():
    # Find all source files in lib
    cmd = ["/usr/bin/find", "lib", "-name", "*.[ch]"]
    files = subprocess.check_output(cmd).decode().strip().split("\n")
    
    for f in files:
        if not f: continue
        with open(f, 'r', errors='ignore') as fd:
            content = fd.read()
            
        new_content = content
        for old_name, new_name in MAPPINGS.items():
            # regex replace #include "lauxlib.h" -> #include "auxlib.h"
            # also <lauxlib.h> just in case
            new_content = new_content.replace(f'#include "{old_name}"', f'#include "{new_name}"')
            new_content = new_content.replace(f'#include <{old_name}>', f'#include <{new_name}>')
            
        if new_content != content:
            print(f"Updating includes in {f}")
            with open(f, 'w') as fd:
                fd.write(new_content)

if __name__ == "__main__":
    run()
