// ateliertool: the project's machinery, one program, whatever the shell.
//
//   odin run tools/ateliertool -collection:gt=ext/gui_toolkit/src -out:build/ateliertool -- <command>
//   (build.sh and build.bat are its shortcuts)
//
// What it needs is on the path: git, odin, cargo (the toolkit's text library), curl and gh (the programs' releases).
// GT=<folder>: another checkout of gui_toolkit (its root, not its src).
package ateliertool

import changelog "gt:changelog"
import release "gt:release"
import toolbox "gt:toolbox"

REPOSITORY :: "https://github.com/sachahjkl/atelier"
when ODIN_OS == .Windows {
	PROGRAM :: "build/atelier.exe"
} else {
	PROGRAM :: "build/atelier"
}

project :: proc() -> toolbox.Project {
	return {
		name = "atelier", repository = REPOSITORY, changelog = "CHANGELOG.md",
		version_file = "src/main.odin", version_line = "APP_VERSION :: ", program = PROGRAM,
		// (every command waits: atelier list and install give their output and exit code to the console)
		launcher = {default_rule = "wait", others = "(none)", refuses_exit = 2},
		title = "atelier", description = "The working man's tools: Froment Software's desktop programs, installed at once.",
		publisher = "Froment Software", copyright = "Copyright (c) 2026 Froment Software",
		features = {.Lucide_Subset},
	}
}

// What the French reader sees: atelier's texts, from its code, into i18n/<language>.txt (the program embeds them).
I18N := toolbox.I18n_Catalogues{dirs = {"src"}, folder = "i18n"}

commands :: proc() -> []toolbox.Command {
	p := project()
	// (notes and ship are the toolkit's; package is atelier's own: the program with the bundle after it)
	r := release.commands({project = p, dist = DIST, check = proc() -> int { return run_check(nil) }})
	list := make([dynamic]toolbox.Command, context.temp_allocator)
	append(&list,
		toolbox.Command{name = "build", usage = "[release]: the toolkit's text library when its sources changed, then build/atelier (no programs carried: --bundle reads them)", run = run_build},
		toolbox.Command{name = "test", usage = ": the tests of the program", run = run_test},
		toolbox.Command{name = "check", usage = ": the changelog and the roadmap, the scopes, the French catalogue, odin check for this system and Windows and of this tool (-vet), the tests, a release build", run = run_check},
		toolbox.Command{name = "bundle", usage = "[linux-x64|windows-x64] [--out file]: the programs' latest releases, checked, in build/bundle-<platform>.zip", run = run_bundle},
		toolbox.Command{name = "package", usage = "[version]: build/dist/atelier-<version>-<platform>: the release build with this platform's bundle after it, and its .sha256", run = run_package},
		toolbox.Command{name = "behind", usage = "[--fragment]: whether the latest atelier carries each program's latest release (exit 3 when not; --fragment writes the changelog's fragment)", run = run_behind},
		r[1], r[2],
		toolbox.logo_command(logo()),
		changelog.command(p),
		toolbox.i18n_command(I18N),
		site_command(),
	)
	when ODIN_OS == .Linux {
		append(&list,
			toolbox.Command{name = "shots", usage = "[--out folder]: the pictures of the README and the site, the program's own frames in a sway nobody sees", run = run_shots},
			toolbox.Command{name = "live", usage = ": every carried program installed for real by atelier, in a home of its own (build/live/home)", run = run_live},
		)
	}
	return list[:]
}

main :: proc() {
	toolbox.tool_main("ateliertool", commands(), toolbox.ROOT_MARK_DEFAULT)
}
