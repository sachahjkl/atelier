package atelier

// Windows runs a file by its extension: a file taken out of the zip runs as it is.
make_runnable :: proc(path: string) -> bool { return true }

// The environment of a program atelier runs: atelier's own (nil).
child_env :: proc(allocator := context.temp_allocator) -> []string { return nil }
