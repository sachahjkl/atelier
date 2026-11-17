#+build !windows
package atelier

import "core:fmt"

// Where the demo says a program was installed: where gt:setup puts it for a user on Linux, in its vendor's folder (the
// demo's pictures are made on Linux).
demo_place :: proc(p: Program) -> string {
	return fmt.aprintf("~/.local/opt/FromentSoftware/%s/%s", p.name, p.slug)
}
