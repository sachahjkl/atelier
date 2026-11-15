package atelier

import "core:os"

// A file taken out of a zip is not runnable: mode 755, as the release's archive gives it.
make_runnable :: proc(path: string) -> bool {
	return os.chmod(path, os.perm_number(0o755)) == nil
}
