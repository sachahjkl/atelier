package atelier

// The debug panels (gt:debug, Ctrl+Alt+Shift+D in a build with the devtools): atelier's own state, and acts that run
// the program's own procedures. src/md/README.md, "The debug panels". A release build compiles every call away.

import "core:fmt"
import debug "gt:debug"
import "gt:ui"

debug_panels :: proc(s: ^ui.State, app: ^App) {
	debug.panel(s, "Steps", steps_debug, app)
	debug.panel(s, "Programs", programs_debug, app)
	debug.panel(s, "Bundle", bundle_debug, app)
	debug.panel(s, "Updates", updates_debug, app)
}

@(private = "file")
steps_debug :: proc(app: ^App) {
	debug.watch("step", app.step)
	debug.watch("stage", app.stage)
	debug.watch("look", app.look)
	debug.watch("batch", app.batch[:])
	debug.watch("asking", app.asking[:])
	debug.watch("known", app.known)
	// (the Nix lines above the programs, on any system)
	debug.toggle("nixos", &app.nixos)
	debug.watch("chosen", chosen_count(app))
	done, of := installed_count(app)
	debug.watch("installed", fmt.tprintf("%d of %d", done, of))
	debug.toggle("fail the next install", &app.fail_next)
	// (the buttons' own guards: an act that the window would not offer does nothing)
	for a in ([]Action{.Next, .Back, .Accept_Install, .Select_All, .Select_None, .Retry_Failed}) {
		if debug.act(STEP_ACTS[a]) { action_run(app, a) }
	}
}

@(private = "file")
STEP_ACTS := #partial [Action]string{
	.Next = "Next", .Back = "Back", .Accept_Install = "Accept and install", .Select_All = "Select all",
	.Select_None = "Select none", .Retry_Failed = "Retry failed",
}

@(private = "file")
programs_debug :: proc(app: ^App) {
	if debug.act("Read every status") { for _, i in app.rows { status_ask(app, i) } }
	for &r, i in app.rows {
		p := app.programs[i]
		// (the section's end is deferred to its block: the block form, never an early continue)
		if debug.section(p.name, open = false) {
			debug.watch("carried", p.version)
			debug.choice("state", &r.status.state)
			debug.watch("installed", r.status.installed)
			debug.watch("program", r.status.program)
			debug.watch("running", r.status.running)
			debug.watch("by nix", r.status.by_nix)
			debug.toggle("ticked", &r.ticked)
			debug.watch("result", r.result)
			debug.watch("phase", r.phase)
			debug.watch("taken out", r.scratch)
			debug.watch("exit code", r.exit_code)
			debug.watch("output", r.output)
			if debug.act("Read status") { status_ask(app, i) }
		}
	}
}

@(private = "file")
bundle_debug :: proc(app: ^App) {
	debug.watch("error", app.bundle_error)
	if app.bundle == nil { return }
	b := app.bundle
	debug.watch("platform", b.platform)
	debug.watch("made", b.made)
	debug.watch("schema", b.schema)
	debug.watch("programs", len(b.programs))
	if debug.act("Delete the files taken out") { scratch_drop(app) }
}

@(private = "file")
updates_debug :: proc(app: ^App) {
	debug.watch("updater", app.updates.updater != nil)
	debug.watch("phase", app.update_phase)
	debug.watch("suite on offer", app.suite_version)
	debug.watch("newer programs", app.suite_newer)
	debug.watch("suite asked", app.suite_asked)
	// (the line of the new copy after the suite's update)
	debug.toggle("after update", &app.after_update)
	if debug.act("Check now") { action_run(app, .Check_Updates) }
	debug.text("suite version", &app.debug_suite)
	if debug.act("Read this suite") && app.updates.updater != nil && app.debug_suite != "" { suite_read(app, app.debug_suite) }
}

// Every file taken out goes, on a task: the next install takes its file out again and checks it. Not while a row is
// busy: its job holds its file.
scratch_drop :: proc(app: ^App) {
	if app.look != .Idle { return }
	for r in app.rows { if result_busy(r.result) { return } }
	for &r in app.rows {
		delete(r.scratch)
		r.scratch = ""
	}
	// (the App's programs, read only: the App waits for its tasks)
	ui.task(&app.main.state, proc(data: rawptr) {
		for p in (^App)(data).programs { if !p.own { scratch_remove(p) } }
	}, proc(_: rawptr, _: u64) {}, app, nil)
}
