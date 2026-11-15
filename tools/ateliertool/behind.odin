package ateliertool

// behind: whether atelier's latest release carries the latest release of each program. The daily workflow
// (.github/workflows/refresh.yml) runs it; when a program is newer, it writes the changelog fragment that says so, and
// the workflow ships a patch release, which carries the new versions.
//
//   ateliertool behind               exit 0: up to date; 1: behind, or the releases cannot be read
//   ateliertool behind --fragment    exit 0: up to date, or behind and the fragment written (changelog.d/*-programs.md:
//                                    the workflow sees the new file); 1: failed

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import changelog "gt:changelog"
import cli "gt:cli"
import toolbox "gt:toolbox"


run_behind :: proc(args: []string) -> cli.Exit {
	fragment := len(args) == 1 && args[0] == "--fragment"
	tag, tok := latest_tag(fmt.tprintf("%s/atelier", OWNER))
	carried := make(map[string]string, context.temp_allocator)
	if tok {
		// (the manifest of the Linux file: every program of the suite has a Linux file)
		version := strings.trim_prefix(tag, "v")
		name := fmt.tprintf("atelier-%s-linux-x64.json", version)
		text, code := toolbox.capture({"gh", "release", "download", tag, "--repo", fmt.tprintf("%s/atelier", OWNER), "--pattern", name, "--output", "-"})
		if code != 0 { fmt.eprintfln("behind: %s of %s cannot be read", name, tag); return .Failed }
		m: Bundle_Manifest
		if json.unmarshal_string(text, &m, allocator = context.temp_allocator) != nil { fmt.eprintfln("behind: %s does not read", name); return .Failed }
		for p in m.programs { carried[p.slug] = p.version }
	}
	news := make([dynamic]string, context.temp_allocator)
	for p in PROGRAMS {
		latest, ok := latest_tag(fmt.tprintf("%s/%s", OWNER, p.repository))
		if !ok { fmt.eprintfln("behind: %s has no release", p.repository); return .Failed }
		latest = strings.trim_prefix(latest, "v")
		have := carried[p.slug]
		if have == latest { fmt.printfln("%-16s %s", p.slug, latest); continue }
		fmt.printfln("%-16s %s -> %s", p.slug, have != "" ? have : "-", latest)
		append(&news, fmt.tprintf("%s %s", p.name, latest))
	}
	if len(news) == 0 { fmt.println("behind: atelier carries the latest of each program"); return .Done }
	if !fragment { fmt.println("behind: atelier is behind"); return .Failed }
	text := fmt.tprintf("type: Changed\n\n**The programs' latest versions**: atelier now carries %s.\n", strings.join(news[:], ", ", context.temp_allocator))
	y, mo, d := time.date(time.now())
	h, mi, s := time.clock(time.now())
	path := fmt.tprintf("changelog.d/%04d%02d%02d-%02d%02d%02d-programs.md", y, int(mo), d, h, mi, s)
	if os.write_entire_file(path, transmute([]u8)text) != nil { fmt.eprintfln("behind: %s cannot be written", path); return .Failed }
	p := project()
	if errors, _ := changelog.check(changelog.project_options(&p)); len(errors) > 0 {
		for e in errors { fmt.eprintln("behind:", e) }
		return .Failed
	}
	fmt.printfln("behind: wrote %s", path)
	return .Done
}
