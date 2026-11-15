package atelier

import "core:fmt"

// Where the demo says a program was installed: where gt:setup puts it for a user on Windows.
demo_place :: proc(p: Program) -> string {
	return fmt.aprintf(`%%LOCALAPPDATA%%\Programs\%s\%s.exe`, p.slug, p.slug)
}
