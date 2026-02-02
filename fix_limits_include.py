
import os
import subprocess

def run():
    # Find all source files in src and lib (we updated includes in lib too)
    cmd = ["/usr/bin/find", "src", "lib", "-name", "*.[ch]"]
    files = subprocess.check_output(cmd).decode().strip().split("\n")
    
    for f in files:
        if not f: continue
        with open(f, 'r', errors='ignore') as fd:
            content = fd.read()
            
        # Replace #include "limits.h" with #include "llimits.h"
        # Only quote version, as that's what refers to our local file.
        new_content = content.replace('#include "limits.h"', '#include "llimits.h"')
        
        if new_content != content:
            print(f"Updating limits include in {f}")
            with open(f, 'w') as fd:
                fd.write(new_content)

if __name__ == "__main__":
    run()
