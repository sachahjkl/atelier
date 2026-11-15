package atelier

import "core:os"
import "core:strings"

// A file taken out of a zip is not runnable: mode 755, as the release's archive gives it.
make_runnable :: proc(path: string) -> bool {
	return os.chmod(path, os.perm_number(0o755)) == nil
}

// The environment of a program atelier runs: atelier's, without the loader's paths. A release file brings what it needs;
// a library path set for atelier (a development shell, a launcher's wrapper) would load another C library's pieces into
// it, and it would not start.
child_env :: proc(allocator := context.temp_allocator) -> []string {
	all, err := os.environ(allocator)
	if err != nil { return nil }
	out := make([dynamic]string, 0, len(all), allocator)
	for e in all {
		if strings.has_prefix(e, "LD_LIBRARY_PATH=") || strings.has_prefix(e, "LD_PRELOAD=") { continue }
		append(&out, e)
	}
	return out[:]
}
