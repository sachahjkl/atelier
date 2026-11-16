#+build linux
package ateliertool

// live: the whole install, for real, in a home of its own (build/live/home: HOME and the XDG folders point there,
// nothing of the person's is touched). atelier installs itself and every program it carries from this system's bundle,
// then `list` must say each one is installed at the carried version; a second `install all` must leave them as they
// are. atelier then installs itself again and takes itself away (--install, --status, --uninstall), as every program
// does. The window's way follows: no setup dialog at its start, its own row installed with the others.

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import cdp "gt:cdp"
import cli "gt:cli"
import toolbox "gt:toolbox"

LIVE_DIR :: "build/live"

run_live :: proc(args: []string) -> cli.Exit {
	bundle := fmt.tprintf("build/bundle-%s.zip", THIS_PLATFORM)
	if !os.exists(bundle) && run_bundle(nil) != .Done { return .Failed }
	if run_build(nil) != .Done { return .Failed }
	_ = os.remove_all(LIVE_DIR)
	here, _ := os.get_working_directory(context.temp_allocator)
	home := fmt.tprintf("%s/%s/home", here, LIVE_DIR)
	for sub in ([]string{"", "/.config", "/.local/share", "/.local/state", "/.cache", "/Desktop"}) {
		if os.make_directory_all(fmt.tprintf("%s%s", home, sub)) != nil { fmt.eprintfln("live: %s cannot be made", home); return .Failed }
	}
	// (a runtime folder of its own too: the programs' single instances live there, and the person's own papier, which
	// runs, must neither be seen as this home's nor be closed by the test)
	runtime := fmt.tprintf("%s/run", home)
	if os.make_directory_all(runtime) != nil || os.chmod(runtime, {.Read_User, .Write_User, .Execute_User}) != nil { fmt.eprintfln("live: %s cannot be made", runtime); return .Failed }
	env := toolbox.env_with({"HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_DESKTOP_DIR", "XDG_RUNTIME_DIR"},
		fmt.tprintf("HOME=%s", home), fmt.tprintf("XDG_CONFIG_HOME=%s/.config", home), fmt.tprintf("XDG_DATA_HOME=%s/.local/share", home),
		fmt.tprintf("XDG_STATE_HOME=%s/.local/state", home), fmt.tprintf("XDG_CACHE_HOME=%s/.cache", home), fmt.tprintf("XDG_RUNTIME_DIR=%s", runtime))
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
	if failed { return .Failed }
	fmt.println("live: every program installed, in its own home")
	if !live_window() { return .Failed }
	return toolbox.ended(live_after_update())
}

// The new copy after the suite's update (`--after-update`, what atelier starts once its update is in place): it opens on
// the Programs step with its line. The update itself needs a newer release on GitHub: its pure parts are suite_test's.
@(private = "file")
live_after_update :: proc() -> bool {
	sway: toolbox.Sway
	if why := toolbox.sway_start(&sway, fmt.tprintf("%s/after", LIVE_DIR), {config = SHOTS_SWAY, homes = true, cache = true}); why != "" { fmt.eprintln("live:", why); return false }
	defer toolbox.sway_stop(&sway)
	home := fmt.tprintf("%s/home", sway.dir)
	_ = os.make_directory_all(home)
	bundle := fmt.tprintf("build/bundle-%s.zip", THIS_PLATFORM)
	p, why := toolbox.sway_program(&sway, {PROGRAM, "--bundle", bundle, "--after-update"}, {fmt.tprintf("TOOLKIT_DEVTOOLS=%d", LIVE_PORT)}, fmt.tprintf("%s/after/atelier.log", LIVE_DIR))
	if why != "" { fmt.eprintln("live:", why); return false }
	defer { _ = os.process_kill(p); _, _ = toolbox.sway_wait(&sway, p, SHOTS_WAIT) }
	c: cdp.Client
	ok := false
	deadline := time.tick_add(time.tick_now(), SHOTS_WAIT)
	for !ok && time.tick_diff(time.tick_now(), deadline) > 0 {
		if c, ok = cdp.connect(LIVE_PORT); !ok { time.sleep(SHOTS_POLL) }
	}
	if !ok { fmt.eprintln("live: the window after the update does not answer"); return false }
	defer cdp.close(&c)
	// (the up-to-date line, then the Programs step's own button)
	for words in ([]string{"choose what to update", "Select all"}) {
		if !cdp.wait_for(&c, words, SHOTS_WAIT) {
			shot := fmt.tprintf("%s/after/failed.png", LIVE_DIR)
			cdp.shot(&c, shot)
			fmt.eprintfln("live: %q never showed after --after-update (the window: %s)", words, shot)
			return false
		}
	}
	fmt.println("live: --after-update opens on the programs, with its line")
	return true
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
	// (sway_start's homes give HOME, XDG_DATA_HOME... of the session's own: an install in ~/.local/opt and the PATH's
	// link in ~/.local/bin stay in it)
	home := fmt.tprintf("%s/home", sway.dir)
	_ = os.make_directory_all(home)
	env := sway.env
	bundle := fmt.tprintf("build/bundle-%s.zip", THIS_PLATFORM)
	data := ""
	for e in env { if strings.has_prefix(e, "XDG_DATA_HOME=") { data = e[len("XDG_DATA_HOME="):] } }
	// A program that runs: papier installed, its manifest taken away (to repair: its box is ticked), its installed copy
	// started. The window must ask, close it and install it.
	open, ok_open, windowless := live_open_papier(&sway, env, bundle, data, home)
	if !ok_open { return false }
	// A program whose install fails once: a file where its install folder goes. The window must show Retry; once the
	// file is gone, the retry installs it.
	failing := PROGRAMS[1]
	obstacles := live_install_folders(failing, data, home)
	for obstacle in obstacles {
		_ = os.make_directory_all(filepath.dir(obstacle))
		if os.write_entire_file(obstacle, transmute([]u8)string("not a folder\n")) != nil { fmt.eprintfln("live: %s cannot be written", obstacle); return false }
	}
	p, why := toolbox.sway_program(&sway, {PROGRAM, "--bundle", bundle, "--look=dark"}, {fmt.tprintf("TOOLKIT_DEVTOOLS=%d", LIVE_PORT)}, fmt.tprintf("%s/window/atelier.log", LIVE_DIR))
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
	if len(cdp.find(&c, "Atelier Setup")) > 0 { fmt.eprintln("live: the setup dialog opened at the start"); return false }
	step(&c, "Not installed", "", SHOTS_WAIT) or_return   // (the states read: the boxes ticked)
	step(&c, "This installer, kept on your computer", "", SHOTS_WAIT) or_return   // (atelier's own row)
	step(&c, "Next", "Next", SHOTS_WAIT) or_return
	step(&c, "MIT License", "Accept and install", SHOTS_WAIT) or_return
	// (papier runs: the question names it, and its button closes it)
	if !windowless {
		step(&c, "This program is open: Papier.", "Close it and install", LIVE_WAIT) or_return
		if _, ended := toolbox.sway_wait(&sway, open, CLOSE_LIVE_WAIT); !ended { fmt.eprintln("live: the papier that ran was not closed"); return false }
		fmt.println("live: the papier that ran is closed")
	}
	step(&c, "1 failed", "", LIVE_WAIT) or_return
	// (the reason on the failed row itself, under its stepper: the first line of its --install's output)
	step(&c, "the install failed", "", SHOTS_WAIT) or_return
	for obstacle in obstacles {
		if os.remove(obstacle) != nil { fmt.eprintfln("live: %s cannot be removed", obstacle); return false }
	}
	// (the row's own Retry, not the panel's "Retry the failed ones": the row starts again in place)
	cdp.wait_idle(&c, SHOTS_WAIT)
	if !live_click_exact(&c, "Retry") { return false }
	step(&c, "programs are installed", "", LIVE_WAIT) or_return
	// (the same step all along: the rows keep their steppers, and nothing is left to retry)
	if len(cdp.find(&c, "Unpack")) == 0 { fmt.eprintln("live: the rows' steppers are gone after the retry"); return false }
	if live_exact(&c, "Retry") >= 0 || len(cdp.find(&c, "Retry the failed ones")) > 0 { fmt.eprintln("live: a Retry is left after the retry succeeded"); return false }
	fmt.println("live: the failed row retried from its own line, on the same step")
	cdp.close(&c)

	list, code := toolbox.capture({PROGRAM, "--bundle", bundle, "list"}, {env = env[:]})
	fmt.print(list)
	if code != 0 || strings.contains(list, "Not installed") || strings.contains(list, "Repair") { fmt.eprintln("live: the window's install left a program out"); return false }
	// (atelier installed itself from its own row: its menu entry in the window's home, and --status says installed)
	if !live_own_installed(list, data) { return false }
	if _, scode := toolbox.capture({PROGRAM, "--bundle", bundle, "--status"}, {env = env[:]}); scode != 0 { fmt.eprintfln("live: atelier --status says %d after the window's install", scode); return false }
	fmt.printfln("live: every program installed from the window, side by side, atelier with them; %sa failure retried", windowless ? "" : "papier closed first, ")
	return true
}

// The index, among the boxes whose text holds `text` (Toolkit.find, Toolkit.click's index), of the first whose text is
// `text` exactly: a row's "Retry", not the panel's "Retry the failed ones". -1: none.
@(private = "file")
live_exact :: proc(c: ^cdp.Client, text: string) -> int {
	for b, i in cdp.find(c, text) { if strings.trim_space(b.text) == text { return i } }
	return -1
}

// Clicks the box whose text is `text` exactly.
@(private = "file")
live_click_exact :: proc(c: ^cdp.Client, text: string) -> bool {
	i := live_exact(c, text)
	if i < 0 {
		shot := fmt.tprintf("%s/window/failed.png", LIVE_DIR)
		cdp.shot(c, shot)
		fmt.eprintfln("live: no button %q (the window: %s)", text, shot)
		return false
	}
	if _, ok := cdp.call(c, "Toolkit.click", fmt.tprintf(`{{"text":%s,"index":%d,"count":1,"button":"left"}}`, cdp.quote(text), i)); !ok {
		fmt.eprintfln("live: %q cannot be clicked", text)
		return false
	}
	fmt.printfln("live: clicked %s", text)
	return true
}

// Where a carried program installs itself in a home: its release's toolkit decides. Since gui_toolkit 0.282.0 it is
// the vendor's folder (~/.local/opt/FromentSoftware/<Name>); a release built before goes to $XDG_DATA_HOME/<slug>. The
// bundle carries both kinds until every program has a newer release, so live looks at both.
@(private = "file")
live_install_folders :: proc(p: Suite_Program, data, home: string) -> [2]string {
	return {fmt.tprintf("%s/%s", data, p.slug), fmt.tprintf("%s/.local/opt/FromentSoftware/%s", home, p.name)}
}

// How long the papier that runs may take to end once the window closes it (atelier's own bound is 10 s per act).
CLOSE_LIVE_WAIT :: 40 * time.Second

// papier installed in the window's home by the command line, its manifest taken away (to repair: the window ticks it),
// then its installed copy started in the session, until its --status says it runs.
@(private = "file")
live_open_papier :: proc(sway: ^toolbox.Sway, env: []string, bundle, data, home: string) -> (p: os.Process, ok: bool, windowless: bool) {
	if out, code := toolbox.capture({PROGRAM, "--bundle", bundle, "install", "papier"}, {env = env}); code != 0 {
		fmt.eprintfln("live: papier does not install:\n%s", out)
		return
	}
	folder := ""
	for f in live_install_folders(PROGRAMS[0], data, home) { if os.is_dir(f) { folder = f } }
	files, err := os.read_all_directory_by_path(folder, context.temp_allocator)
	if folder == "" || err != nil { fmt.eprintfln("live: papier's install folder cannot be read (%v)", live_install_folders(PROGRAMS[0], data, home)); return }
	for f in files {
		if strings.has_suffix(f.name, "_install.txt") { _ = os.remove(f.fullpath) }
	}
	exe := fmt.tprintf("%s/papier", folder)
	// (started here, not by atelier: on a distribution the release file takes the system's libraries, and the shell's
	// loader paths (Nix's C library) break it; on NixOS there are no system libraries and it needs the shell's)
	nixos := os.exists("/etc/NIXOS")
	plain_env := make([dynamic]string, context.temp_allocator)
	for e in env {
		// (and Nix's Vulkan driver, built for Nix's C library: the system's own drivers are found without it)
		if !nixos && (strings.has_prefix(e, "LD_LIBRARY_PATH=") || strings.has_prefix(e, "LD_PRELOAD=") || strings.has_prefix(e, "VK_DRIVER_FILES=")) { continue }
		append(&plain_env, e)
	}
	extra := make([dynamic]string, context.temp_allocator)
	append(&extra, fmt.tprintf("HOME=%s", home))
	if !nixos { append(&extra, "LD_LIBRARY_PATH=", "LD_PRELOAD=", "VK_DRIVER_FILES=") }
	why: string
	p, why = toolbox.sway_program(sway, {exe, "--hidden"}, extra[:], fmt.tprintf("%s/window/papier.log", LIVE_DIR))
	if why != "" { fmt.eprintln("live:", why); return }
	deadline := time.tick_add(time.tick_now(), SHOTS_WAIT)
	for time.tick_diff(time.tick_now(), deadline) > 0 {
		out, _ := toolbox.capture({exe, "--status"}, {env = plain_env[:]})
		if strings.contains(out, "running: true") && strings.contains(out, "to repair") {
			fmt.println("live: papier runs, its install to repair")
			return p, true, false
		}
		time.sleep(SHOTS_POLL)
	}
	// (a runner whose Vulkan the released file cannot reach: papier gets no surface and ends. That is the machine's,
	// not atelier's: the question of a program that runs is not tried here, the rest is)
	log_text, _ := os.read_entire_file(fmt.tprintf("%s/window/papier.log", LIVE_DIR), context.temp_allocator)
	// (a program on gui_toolkit before 0.278.0 aborts in wgpu; a later one says so in a sentence and ends)
	if strings.contains(string(log_text), "wgpuInstanceCreateSurface") || strings.contains(string(log_text), "no graphics device this program can draw with") {
		fmt.println("live: papier cannot open a window on this machine (no Vulkan surface for it): the question of a program that runs is not tried here")
		return p, true, true
	}
	out, _ := toolbox.capture({exe, "--status"}, {env = plain_env[:]})
	fmt.eprintfln("live: papier does not run, or is not to repair:\n%s", out)
	return
}
