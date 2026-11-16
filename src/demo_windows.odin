package atelier

import "core:fmt"

// Where the demo says a program was installed: where gt:setup puts it for a user on Windows, in its vendor's folder.
demo_place :: proc(p: Program) -> string {
	return fmt.aprintf(`%%LOCALAPPDATA%%\Programs\FromentSoftware\%s\%s.exe`, p.name, p.slug)
}
