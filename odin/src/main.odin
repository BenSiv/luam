package main

import "core:fmt"
import "core:os"
import "core:c"

// Initial Odin entry point
// This will just transfer control to the existing C implementation for now

main :: proc() {
	args := os.args
	argc := i32(len(args))
	
	// Convert Odin strings to C strings for argv
	argv := make([]cstring, len(args) + 1)
	// defer delete(argv) - Unreachable due to os.exit
	
	for arg, i in args {
		argv[i] = cstring(raw_data(arg)) // basic conversion, assumes null-termination
	}
	argv[len(args)] = nil
	
	// Call into the renamed C main function
	status := luam_main(argc, raw_data(argv))
	
	os.exit(int(status))
}
