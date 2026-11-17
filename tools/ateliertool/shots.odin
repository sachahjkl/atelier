#+build linux
package ateliertool

// shots: the pictures of the README and the site, the program's own frames (over the DevTools protocol) in a sway
// nobody sees. atelier runs with --demo (made-up states, nothing installed) on this system's bundle, once per step.
//
//   ateliertool shots [--out folder]      (default: docs/screenshots, copied to site/img)

import "core:fmt"
import "core:os"
import "core:time"
import cdp "gt:cdp"
import cli "gt:cli"
import toolbox "gt:toolbox"

SHOTS_DIR  :: "build/shots"
SHOTS_OUT  :: "docs/screenshots"
SHOTS_SITE :: "site/img"
// (a bound, not a delay: a loaded machine draws a software-rendered sway slowly, and a step's first frame can take seconds)
SHOTS_WAIT :: 30 * time.Second
SHOTS_POLL :: 50 * time.Millisecond
// (atelier floats at its own size, as on a desktop: the pictures have its real proportions)
SHOTS_SWAY :: "for_window [app_id=\"atelier\"] floating enable, resize set 900 640\n"

// Each picture: its file, the step it shows, a text to wait for; then what is done in the window (a script's commands:
// "key ctrl+,", "click Appearance"), each followed by a text to wait for, before the picture is taken.
@(private = "file")
Shot :: struct { name, step, seen: string, then: []Shot_Act, flags: []string }

@(private = "file")
Shot_Act :: struct { command, arg, seen: string }

// (a variable: the acts' slices are the program's data, not made again where the table is used)
@(private = "file")
SHOTS := [?]Shot{
	// (atelier's own row first, not installed: the picture of a first start)
	{name = "main", step = "programs", seen = "This installer, kept on your computer"},
	{name = "welcome", step = "welcome", seen = "Froment Software"},
	{name = "licences", step = "licences", seen = "MIT License"},
	// (the install under way: the steppers side by side, the count and the bar)
	{name = "installing", step = "installing", seen = "Copy"},
	// (the same step once over: each row's Open and its folder, the summary in the top panel)
	{name = "done", step = "done", seen = "programs are installed"},
	// (the question before the installs: two programs of the demo run)
	{name = "close", step = "checking", seen = "Close them and install"},
	// (the same step once over, one install failed: its reason under its stepper, its output open, its Retry)
	{name = "retry", step = "done", seen = "Exit code: 1", flags = {"--demo-case", "failure"}},
	// (a newer suite on offer: its banner, and the notes of the rows it updates)
	{name = "update", step = "programs", seen = "Update Atelier and the programs", flags = {"--demo-case", "update"}},
	// (the settings on their Appearance page: atelier's theme first among the cards)
	{name = "settings", step = "programs", seen = "Papier", then = {{"key", "ctrl+,", "General"}, {"click", "Appearance", "Midnight"}}},
	{name = "palette", step = "programs", seen = "Papier", then = {{"key", "ctrl+k", "Next step"}}},
}

run_shots :: proc(args: []string) -> cli.Exit {
	out := SHOTS_OUT
	if len(args) == 2 && args[0] == "--out" { out = args[1] }
	bundle := fmt.tprintf("build/bundle-%s.zip", THIS_PLATFORM)
	if !os.exists(bundle) && run_bundle(nil) != .Done { return .Failed }
	if !toolbox.program_build(build_options()) { return .Failed }   // (a debug build: it has the DevTools server)
	_ = os.make_directory_all(out)
	toolbox.guard_groups()
	failed := false
	for s in SHOTS {
		if !take(s, bundle, out) { fmt.eprintfln("ateliertool shots: %s failed", s.name); failed = true }
	}
	if failed { return .Failed }
	if out != SHOTS_OUT { return .Done }
	for s in SHOTS {
		data, err := os.read_entire_file(fmt.tprintf("%s/%s.png", out, s.name), context.temp_allocator)
		if err == nil { _ = os.write_entire_file(fmt.tprintf("%s/%s.png", SHOTS_SITE, s.name), data) }
	}
	return .Done
}

// One picture: a sway of its own, atelier on the step, its frame once the text shows.
@(private = "file")
take :: proc(s: Shot, bundle, out: string) -> bool {
	command := make([dynamic]string, context.temp_allocator)
	append(&command, PROGRAM, "--demo", "--look=dark", "--bundle", bundle, "--step", s.step)
	append(&command, ..s.flags)
	session: toolbox.Program_Session
	defer toolbox.program_session_stop(&session)
	if why := toolbox.program_session_start(&session, SHOTS_DIR, {command = command[:], desktop = {config = SHOTS_SWAY, homes = true}, wait = SHOTS_WAIT}); why != "" { fmt.eprintln(why); return false }
	c, why := toolbox.program_session_connect(&session)
	if why != "" { fmt.eprintln(why); return false }
	defer cdp.close(&c)
	if !cdp.wait_for(&c, s.seen, SHOTS_WAIT) { fmt.eprintfln("%q never showed", s.seen); return false }
	cdp.wait_idle(&c, SHOTS_WAIT)
	for a in s.then {
		if known, done := cdp.act(&c, a.command, {a.arg}); !known || !done { fmt.eprintfln("%s %s failed", a.command, a.arg); return false }
		if !cdp.wait_for(&c, a.seen, SHOTS_WAIT) { fmt.eprintfln("%q never showed after %s %s", a.seen, a.command, a.arg); return false }
		cdp.wait_idle(&c, SHOTS_WAIT)
	}
	path := fmt.tprintf("%s/%s.png", out, s.name)
	if !cdp.shot(&c, path) { return false }
	fmt.printfln("wrote %s", path)
	return true
}
