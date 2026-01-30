package main

import "core:c"

// Bindings to the C functions we need
foreign import luam_c "system:c"

@(default_calling_convention="c")
foreign luam_c {
	luam_main :: proc(argc: c.int, argv: ^cstring) -> c.int ---
}
