package atelier

import "core:fmt"

// Where the demo says a program was installed: where gt:setup puts it for a user on Linux.
demo_place :: proc(p: Program) -> string {
	return fmt.aprintf("~/.local/share/%s/%s", p.slug, p.slug)
}
