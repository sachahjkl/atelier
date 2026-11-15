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
import toolbox "gt:toolbox"

SHOTS_DIR  :: "build/shots"
SHOTS_PORT :: 9372
SHOTS_OUT  :: "docs/screenshots"
SHOTS_SITE :: "site/img"
SHOTS_WAIT :: 10 * time.Second
SHOTS_POLL :: 50 * time.Millisecond
// (atelier floats at its own size, as on a desktop: the pictures have its real proportions)
SHOTS_SWAY :: "for_window [app_id=\"atelier\"] floating enable, resize set 900 640\n"

// Each picture: its file, the step it shows, a text to wait for; then what is done in the window (a script's commands:
// "key ctrl+,", "click Appearance"), each followed by a text to wait for, before the picture is taken.
@(private = "file")
Shot :: struct { name, step, seen: string, then: []Shot_Act }

@(private = "file")
Shot_Act :: struct { command, arg, seen: string }

// (a variable: the acts' slices are the program's data, not made again where the table is used)
@(private = "file")
SHOTS := [?]Shot{
	{name = "main", step = "programs", seen = "Papier"},
	{name = "welcome", step = "welcome", seen = "Froment Software"},
	{name = "licences", step = "licences", seen = "MIT License"},
	{name = "installing", step = "installing", seen = "Papier"},
	{name = "done", step = "done", seen = "Papier"},
	// (the settings on their Appearance page: atelier's theme first among the cards)
	{name = "settings", step = "programs", seen = "Papier", then = {{"key", "ctrl+,", "General"}, {"click", "Appearance", "Midnight"}}},
	{name = "palette", step = "programs", seen = "Papier", then = {{"key", "ctrl+k", "Next step"}}},
}

run_shots :: proc(args: []string) -> int {
	out := SHOTS_OUT
	if len(args) == 2 && args[0] == "--out" { out = args[1] }
	bundle := fmt.tprintf("build/bundle-%s.zip", THIS_PLATFORM)
	if !os.exists(bundle) && run_bundle(nil) != 0 { return 1 }
	if run_build(nil) != 0 { return 1 }   // (a debug build: it has the DevTools server)
	_ = os.make_directory_all(out)
	toolbox.guard_groups()
	failed := false
	for s in SHOTS {
		if !take(s, bundle, out) { fmt.eprintfln("ateliertool shots: %s failed", s.name); failed = true }
	}
	if failed { return 1 }
	if out != SHOTS_OUT { return 0 }
	for s in SHOTS {
		data, err := os.read_entire_file(fmt.tprintf("%s/%s.png", out, s.name), context.temp_allocator)
		if err == nil { _ = os.write_entire_file(fmt.tprintf("%s/%s.png", SHOTS_SITE, s.name), data) }
	}
	return 0
}

// One picture: a sway of its own, atelier on the step, its frame once the text shows.
@(private = "file")
take :: proc(s: Shot, bundle, out: string) -> bool {
	sway: toolbox.Sway
	if why := toolbox.sway_start(&sway, SHOTS_DIR, {config = SHOTS_SWAY, homes = true}); why != "" { fmt.eprintln(why); return false }
	defer toolbox.sway_stop(&sway)
	devtools := fmt.tprintf("TOOLKIT_DEVTOOLS=%d", SHOTS_PORT)
	p, why := toolbox.sway_program(&sway, {PROGRAM, "--demo", "--look=dark", "--bundle", bundle, "--step", s.step}, {devtools}, fmt.tprintf("%s/atelier.log", sway.dir))
	if why != "" { fmt.eprintln(why); return false }
	defer { _ = os.process_kill(p); _, _ = toolbox.sway_wait(&sway, p, SHOTS_WAIT) }
	c: cdp.Client
	ok := false
	deadline := time.tick_add(time.tick_now(), SHOTS_WAIT)
	for !ok && time.tick_diff(time.tick_now(), deadline) > 0 {
		if c, ok = cdp.connect(SHOTS_PORT); !ok { time.sleep(SHOTS_POLL) }
	}
	if !ok { fmt.eprintln("the window does not answer"); return false }
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
