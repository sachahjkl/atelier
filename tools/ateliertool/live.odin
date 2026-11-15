#+build linux
package ateliertool

// live: the whole install, for real, in a home of its own (build/live/home: HOME and the XDG folders point there,
// nothing of the person's is touched). atelier installs itself and every program it carries from this system's bundle,
// then `list` must say each one is installed at the carried version; a second `install all` must leave them as they
// are. atelier then installs itself again and takes itself away (--install, --status, --uninstall), as every program
// does. The window's way follows: no setup dialog at its start, its own row installed with the others.

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import cdp "gt:cdp"
import toolbox "gt:toolbox"

LIVE_DIR :: "build/live"

run_live :: proc(args: []string) -> int {
	bundle := fmt.tprintf("build/bundle-%s.zip", THIS_PLATFORM)
	if !os.exists(bundle) && run_bundle(nil) != 0 { return 1 }
	if run_build(nil) != 0 { return 1 }
	_ = os.remove_all(LIVE_DIR)
	here, _ := os.get_working_directory(context.temp_allocator)
	home := fmt.tprintf("%s/%s/home", here, LIVE_DIR)
	for sub in ([]string{"", "/.config", "/.local/share", "/.local/state", "/.cache", "/Desktop"}) {
		if os.make_directory_all(fmt.tprintf("%s%s", home, sub)) != nil { fmt.eprintfln("live: %s cannot be made", home); return 1 }
	}
	env := toolbox.env_with({"HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_DESKTOP_DIR"},
		fmt.tprintf("HOME=%s", home), fmt.tprintf("XDG_CONFIG_HOME=%s/.config", home), fmt.tprintf("XDG_DATA_HOME=%s/.local/share", home),
		fmt.tprintf("XDG_STATE_HOME=%s/.local/state", home), fmt.tprintf("XDG_CACHE_HOME=%s/.cache", home))
	atelier :: proc(env: []string, args: ..string) -> (out: string, code: int) {
		command := make([dynamic]string, context.temp_allocator)
		append(&command, PROGRAM, "--bundle", fmt.tprintf("build/bundle-%s.zip", THIS_PLATFORM))
		append(&command, ..args)
		out, code = toolbox.capture(command[:], {env = env})
		fmt.printf("> atelier %s (exit %d)\n%s", strings.join(args, " ", context.temp_allocator), code, out)
		return
	}
	failed := false
	if _, code := atelier(env, "install", "all"); code != 0 { fmt.eprintln("live: install all failed"); failed = true }
	list, lcode := atelier(env, "list")
	if lcode != 0 { fmt.eprintln("live: list failed"); failed = true }
	for p in PROGRAMS {
		line := ""
		rest := list
		for l in strings.split_lines_iterator(&rest) { if strings.has_prefix(strings.trim_space(l), p.slug) { line = l } }
		if line == "" { continue }   // (not carried on this platform)
		// (the state as list says it: "Installed" alone is the carried version, installed)
		if !strings.has_suffix(strings.trim_space(line), "Installed") {
			fmt.eprintfln("live: %s is not installed: %q", p.slug, line)
			failed = true
		}
		if !os.exists(fmt.tprintf("%s/.local/share/applications/%s.desktop", home, p.slug)) {
			fmt.eprintfln("live: %s has no menu entry", p.slug)
			failed = true
		}
	}
	// (install all includes atelier itself: its line, under the heading, says it is installed)
	if !live_own_installed(list, fmt.tprintf("%s/.local/share", home)) { failed = true }
	// (again: each program is current, nothing to do, still a success)
	if _, code := atelier(env, "install", "all"); code != 0 { fmt.eprintln("live: a second install all failed"); failed = true }
	// atelier itself, as every program: installed with its menu entry, said installed, then taken away
	if _, code := atelier(env, "--install"); code != 0 { fmt.eprintln("live: atelier --install failed"); failed = true }
	if _, code := atelier(env, "--status"); code != 0 { fmt.eprintln("live: atelier --status does not say installed"); failed = true }
	if !os.exists(fmt.tprintf("%s/.local/share/applications/atelier.desktop", home)) { fmt.eprintln("live: atelier has no menu entry"); failed = true }
	if _, code := atelier(env, "--uninstall"); code != 0 { fmt.eprintln("live: atelier --uninstall failed"); failed = true }
	if _, code := atelier(env, "--status"); code != 1 { fmt.eprintln("live: atelier --status does not say uninstalled"); failed = true }
	if failed { return 1 }
	fmt.println("live: every program installed, in its own home")
	return live_window() ? 0 : 1
}

// Whether `list` says atelier is installed (its own line: two spaces, then its slug; the heading starts with it too) and
// its menu entry is in `data` (XDG_DATA_HOME).
@(private = "file")
live_own_installed :: proc(list, data: string) -> bool {
	line := ""
	rest := list
	for l in strings.split_lines_iterator(&rest) { if strings.has_prefix(l, "  atelier ") { line = l } }
	ok := true
	if !strings.has_suffix(strings.trim_space(line), "Installed") {
		fmt.eprintfln("live: atelier is not installed: %q", line)
		ok = false
	}
	if !os.exists(fmt.tprintf("%s/applications/atelier.desktop", data)) {
		fmt.eprintln("live: atelier has no menu entry")
		ok = false
	}
	return ok
}

LIVE_PORT :: 9373
LIVE_WAIT :: 120 * time.Second   // (five programs installed side by side, on a CI's runner)

// The window's way: atelier in a sway nobody sees (its own homes: sway_start's), driven over the DevTools protocol through
// every step, the programs installed side by side; then `list` must say each one is installed.
@(private = "file")
live_window :: proc() -> bool {
	toolbox.guard_groups()
	sway: toolbox.Sway
	if why := toolbox.sway_start(&sway, fmt.tprintf("%s/window", LIVE_DIR), {config = SHOTS_SWAY, homes = true, cache = true}); why != "" { fmt.eprintln("live:", why); return false }
	defer toolbox.sway_stop(&sway)
	// (HOME too: the PATH's link goes to ~/.local/bin, which no XDG variable moves)
	home := fmt.tprintf("%s/home", sway.dir)
	_ = os.make_directory_all(home)
	env := make([dynamic]string, context.temp_allocator)
	for e in sway.env { if !strings.has_prefix(e, "HOME=") { append(&env, e) } }
	append(&env, fmt.tprintf("HOME=%s", home))
	bundle := fmt.tprintf("build/bundle-%s.zip", THIS_PLATFORM)
	p, why := toolbox.sway_program(&sway, {PROGRAM, "--bundle", bundle, "--look=dark"}, {fmt.tprintf("TOOLKIT_DEVTOOLS=%d", LIVE_PORT), fmt.tprintf("HOME=%s", home)}, fmt.tprintf("%s/window/atelier.log", LIVE_DIR))
	if why != "" { fmt.eprintln("live:", why); return false }
	defer { _ = os.process_kill(p); _, _ = toolbox.sway_wait(&sway, p, SHOTS_WAIT) }
	c: cdp.Client
	ok := false
	deadline := time.tick_add(time.tick_now(), SHOTS_WAIT)
	for !ok && time.tick_diff(time.tick_now(), deadline) > 0 {
		if c, ok = cdp.connect(LIVE_PORT); !ok { time.sleep(SHOTS_POLL) }
	}
	if !ok { fmt.eprintln("live: the window does not answer"); return false }
	defer cdp.close(&c)
	step :: proc(c: ^cdp.Client, wait, click: string, limit: time.Duration) -> bool {
		if !cdp.wait_for(c, wait, limit) {
			shot := fmt.tprintf("%s/window/failed.png", LIVE_DIR)
			cdp.shot(c, shot)
			fmt.eprintfln("live: %q never showed (the window: %s)", wait, shot)
			return false
		}
		if click != "" {
			cdp.wait_idle(c, SHOTS_WAIT)   // (a click on a frame still settling misses its button)
			// (the last box with the words: the button, under a paragraph that may hold the same words)
			found := cdp.find(c, click)
			if len(found) == 0 { fmt.eprintfln("live: no button %q", click); return false }
			if _, ok := cdp.call(c, "Toolkit.click", fmt.tprintf(`{{"text":%s,"index":%d,"count":1,"button":"left"}}`, cdp.quote(click), len(found) - 1)); !ok {
				fmt.eprintfln("live: %q cannot be clicked", click)
				return false
			}
		}
		fmt.printfln("live: %s", wait)
		return true
	}
	step(&c, "Choose the programs", "Choose the programs", SHOTS_WAIT) or_return
	// (no installer of the installer: atelier's own row offers its install, no dialog over the first step)
	if len(cdp.find(&c, "atelier Setup")) > 0 { fmt.eprintln("live: the setup dialog opened at the start"); return false }
	step(&c, "Not installed", "", SHOTS_WAIT) or_return   // (the states read: the boxes ticked)
	step(&c, "This installer, kept on your computer", "", SHOTS_WAIT) or_return   // (atelier's own row)
	step(&c, "Next", "Next", SHOTS_WAIT) or_return
	step(&c, "MIT License", "Accept and install", SHOTS_WAIT) or_return
	step(&c, "programs are installed", "", LIVE_WAIT) or_return
	cdp.close(&c)

	list, code := toolbox.capture({PROGRAM, "--bundle", bundle, "list"}, {env = env[:]})
	fmt.print(list)
	if code != 0 || strings.contains(list, "Not installed") || strings.contains(list, "Repair") { fmt.eprintln("live: the window's install left a program out"); return false }
	// (atelier installed itself from its own row: its menu entry in the window's home, and --status says installed)
	data := ""
	for e in env { if strings.has_prefix(e, "XDG_DATA_HOME=") { data = e[len("XDG_DATA_HOME="):] } }
	if !live_own_installed(list, data) { return false }
	if _, scode := toolbox.capture({PROGRAM, "--bundle", bundle, "--status"}, {env = env[:]}); scode != 0 { fmt.eprintfln("live: atelier --status says %d after the window's install", scode); return false }
	fmt.println("live: every program installed from the window, side by side, atelier with them")
	return true
}
