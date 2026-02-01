package main

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"

import "core"

// Initial Odin entry point
// This will just transfer control to the existing C implementation for now

main :: proc() {
	fmt.printf("DEBUG: Odin main starting...\n")
	args := os.args
	argc := i32(len(args))

	// Convert Odin strings to C strings for argv
	argv := make([]cstring, len(args) + 1)

	for arg, i in args {
		argv[i] = strings.clone_to_cstring(arg)
	}
	argv[len(args)] = nil

	// Note: We are leaking memory here (the cstrings), but since we exit immediately after,
	// and this is the main function, the OS will clean up.

	// Call into the renamed C main function
	status := luam_main(argc, raw_data(argv))

	os.exit(int(status))
}
