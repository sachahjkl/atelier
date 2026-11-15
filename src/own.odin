package atelier

// atelier's own row (src/md/README.md, "atelier's own row"): atelier is the first program of the list, so that the
// person installs it as they install the others, with no dialog of its own at the start. Its state comes from gt:setup's
// facts and its install is gt:setup's, in this process: atelier is the running program, not a file of the bundle.
// own_status and own_install read and write the disk: they are a worker's (or the command line's).

import "core:strings"
import desktop "gt:desktop"
import i18n "gt:i18n"
import setup "gt:setup"
import update "gt:update"

// atelier's licences: the bundle does not carry atelier, so its texts are in the program.
OWN_LICENCE_TEXTS := [?]string{
	#load("../LICENSE", string),
	#load("../ext/gui_toolkit/src/lucide/LICENSE.txt", string),
}

// Their titles, as ateliertool's licence_title names the same files of a carried program.
@(rodata)
OWN_LICENCES := [?]Licence{{title = "MIT License"}, {title = "Lucide (ISC License)"}}

// atelier as a program of the list. Its tagline is English: the view translates it, so that a change of language shows.
own_program :: proc() -> Program {
	return Program{
		slug = APP_NAME, name = "atelier", version = APP_VERSION, repository = "https://github.com/sachahjkl/atelier",
		tagline = i18n.later("This installer, kept on your computer: it updates the suite and adds programs later."),
		licences = OWN_LICENCES[:], own = true,
	}
}

// The texts of atelier's licences, owned (a row frees them as it frees a carried program's).
own_licence_texts :: proc(allocator := context.allocator) -> []string {
	texts := make([]string, len(OWN_LICENCE_TEXTS), allocator)
	for t, i in OWN_LICENCE_TEXTS { texts[i] = strings.clone(t, allocator) }
	return texts
}

// The state of atelier's install, as gt:setup reads it (a worker's: it reads the disk). gt:setup's strings are in the
// temporary memory, which the caller frees.
own_status :: proc(allocator := context.allocator) -> Status {
	if !desktop.supported() {
		return {state = .Unknown, reason = strings.clone(i18n.tr("atelier cannot install itself on this system"), allocator)}
	}
	return own_status_of(setup.facts(setup_options()), allocator)
}

// gt:setup's facts as the states of a row. A copy installed elsewhere is compared with this one's version, as a carried
// program's --status is. A Nix package is installed and has no box: the Nix configuration installs it.
own_status_of :: proc(f: setup.Facts, allocator := context.allocator) -> (s: Status) {
	switch f.state {
	case .Not_Installed, .Removal_Scheduled: s.state = .Absent
	case .Repair:                            s.state = .Repair
	case .This_Copy:                         s.state = .Current
	case .Nix_Package:                       s.state, s.by_nix = .Current, true
	case .Other_Copy:
		s.state = .Current
		// (a version that does not read as one: installed, nothing to offer, as status_parse says it)
		if order, ok := update.version_compare(f.version, APP_VERSION); ok {
			if order < 0 { s.state = .Older } else if order > 0 { s.state = .Newer }
		}
	}
	s.installed = strings.clone(f.version, allocator)
	if f.exe_there { s.program = strings.clone(f.exe, allocator) }
	return
}

// Installs atelier: gt:setup copies the running file (the program and its bundle) into its folder, writes its menu
// entry and its record. No Desktop shortcut and the options' first values: as `atelier --install` does. `output`: why
// it failed (owned; "" when it installed).
own_install :: proc(allocator := context.allocator) -> (ok: bool, output: string) {
	done, exe_or_why := setup.install(setup_options(), desktop_shortcut = false, choices = nil)
	if !done { output = strings.clone(exe_or_why, allocator) }
	return done, output
}
