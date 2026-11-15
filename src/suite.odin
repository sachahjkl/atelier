package atelier

// The suite's updates (src/md/README.md, "The suite's updates, from atelier"): what a newer atelier carries that this
// copy does not, read from the manifest published beside its release (`atelier-<version>-<platform>.json`, the new
// bundle's bundle.json). That manifest is not signed: it decides only what the window shows, never what is installed.
// The procedures here are pure: no disk, no network.

import "core:fmt"
import "core:strings"
import i18n "gt:i18n"
import update "gt:update"

// A program that the newer atelier carries at a newer version than this copy, or that this copy does not carry.
Newer_Program :: struct {
	slug:    string,
	name:    string,
	version: string,   // the newer atelier's
}

// The name of the manifest published beside a release of atelier.
suite_manifest_name :: proc(version, platform: string, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("atelier-%s-%s.json", version, platform, allocator = allocator)
}

// The programs of a published manifest (`data`) newer than in `carried`, their strings owned (newer_destroy). ok false:
// not a manifest this atelier reads.
suite_newer_of :: proc(carried: []Program, data: []u8, allocator := context.allocator) -> (newer: []Newer_Program, ok: bool) {
	b := new(Bundle)
	defer bundle_destroy(b)
	if !bundle_parse(b, data) { return nil, false }
	return suite_newer(carried, b.programs, allocator), true
}

// The programs of `published` newer than in `carried` (atelier's own row is not a carried program), their strings owned.
// A version that does not read as one is not newer: nothing to offer.
suite_newer :: proc(carried, published: []Program, allocator := context.allocator) -> []Newer_Program {
	out := make([dynamic]Newer_Program, allocator)
	for p in published {
		have := ""
		for c in carried { if !c.own && c.slug == p.slug { have = c.version } }
		if have != "" {
			order, ok := update.version_compare(p.version, have)
			if !ok || order <= 0 { continue }
		}
		append(&out, Newer_Program{strings.clone(p.slug, allocator), strings.clone(p.name, allocator), strings.clone(p.version, allocator)})
	}
	return out[:]
}

newer_destroy :: proc(newer: []Newer_Program, allocator := context.allocator) {
	for n in newer {
		delete(n.slug, allocator); delete(n.name, allocator); delete(n.version, allocator)
	}
	delete(newer, allocator)
}

// The version of `slug` that the newer atelier carries ("": none newer).
suite_available :: proc(newer: []Newer_Program, slug: string) -> string {
	for n in newer { if n.slug == slug { return n.version } }
	return ""
}

// The banner's words: atelier's new version, and the programs newer than this copy's (temp memory).
suite_banner :: proc(version: string, newer: []Newer_Program) -> string {
	if len(newer) == 0 { return fmt.tprintf(i18n.tr("A newer suite is available (Atelier %s)."), version) }
	names := make([dynamic]string, context.temp_allocator)
	for n in newer { append(&names, fmt.tprintf("%s %s", n.name, n.version)) }
	list := strings.join(names[:], ", ", context.temp_allocator)
	return fmt.tprintf(i18n.tr(len(newer), "A newer suite is available (Atelier %s): %s is newer than what this copy carries.", "A newer suite is available (Atelier %s): %s are newer than what this copy carries."), version, list)
}
