// atelier: the suite of Froment Software's desktop programs as one download (src/md/README.md).
//
// The release is this program with a zip written after its own bytes: the programs it carries, their logos and
// licences (bundle.odin). The window (app.odin, view.odin) lets the person choose the programs, shows their licences,
// then has each one install itself (`<program> --install`, install.odin), all at once, each on a worker.
package atelier

import "core:fmt"
import "core:os"
import "core:strings"
import config "gt:config"
import host "gt:host"
import instance "gt:instance"
import "gt:platform"
import process "gt:process"
import setup "gt:setup"

APP_NAME :: "atelier"
// The name a person reads: the window, the menus, the texts. APP_NAME stays the technical name.
APP_TITLE :: "Atelier"

// Who makes it: its install's record and setup, the window's "By" line.
VENDOR     :: "Froment Software"
VENDOR_URL :: "https://froment.software"
// atelier's folders (settings, state, logs, scratch): its vendor's folder, then its own (gui_toolkit's
// src/md/features/folders.md). The runtime folder keeps APP_NAME: an old and a new copy still meet on its socket.
APP_FOLDER :: "FromentSoftware" + platform.USER_DIR_SEPARATOR + APP_TITLE
APP_VERSION :: "0.9.10"

USAGE :: `atelier: Froment Software's programs, chosen and installed at once

  atelier                         the window: choose the programs, read their licences, install them
  atelier list                    atelier, then the programs carried, their version and their state here; no window
  atelier install <slug>... | all those programs installed, without a window (exit 0 when each one installed); the
                                  slug atelier is atelier itself, and all includes it. A program that runs is left
                                  as it is (exit 1), unless --close: then atelier closes it first
  atelier --setup                 the window with atelier's own install shown (also in the settings: Installation)
  atelier --install               install this copy of atelier for you, with the programs it carries: the program, its
                                  menu entry, its uninstaller; no window
  atelier --uninstall             take atelier's install away (the programs it installed and your settings stay)
  atelier --status                what of atelier is installed, and whether it runs (exit 0 installed, 2 to repair,
                                  1 not installed)
  atelier --quit                  close the atelier that runs, and wait for it to end (exit 0 ended or not running)
  atelier prefs                   every preference, its value and what it does
  atelier set <name> <value>      change a preference (saved)
  atelier --bundle <file>         the programs of another file (a bundle made by ateliertool bundle)
  atelier --demo                  the window with made-up states: nothing is read of this computer, nothing runs
                                  (the pictures of the site); the names, logos and licences are the bundle's
  atelier --step <name>           the window on a step: welcome, programs, licences, checking, installing, or done
                                  (the install step once over) (with --demo: the pictures, checking with programs
                                  that run; without it, welcome or programs only)
  atelier --demo-case <name>      with --demo: failure (one install fails: its reason and its output shown) or
                                  update (a newer suite is on offer): the pictures of Retry and of the suite's update
  atelier --after-update          the window on the programs after atelier updated itself: those installed at an
                                  older version than it carries are ticked
  atelier --look=dark|light       --pref appearance.mode=dark|light: the window dark or light for this run
  atelier --version
  atelier --help
  --pref name=value               a preference for this run only
`

// The message of a copy built without a bundle (a development build).
NO_BUNDLE :: "This copy of atelier carries no programs: build it with ateliertool package."

main :: proc() {
	os.exit(run(process.command_line_args()))
}

// How the window starts (main's options).
Run_Options :: struct {
	bundle:     string,   // the file the programs are read from (the executable unless --bundle)
	demo:       bool,
	demo_case:  Demo_Case,   // with demo: what more it shows
	after_update: bool,      // this run is the new copy after the suite's update: on Programs, with its line
	step:       Step,
	finished:   bool,             // with step Installing (--step done): the installs over
	// the log, the last crash and the restart after the end (host.program_start): what is owned until main ends
	start:      ^host.Program_Start,
	owner:      instance.Owner,   // the single instance, held by this process (state None: not held)
}

run :: proc(all_args: []string) -> int {
	opts := Run_Options{step = .Welcome}
	step_asked := false
	args := make([dynamic]string, context.temp_allocator)
	for i := 0; i < len(all_args); i += 1 {
		a := all_args[i]
		switch a {
		case "--bundle", "--step", "--demo-case":
			if i + 1 >= len(all_args) { process.console_error(USAGE); return 2 }
			i += 1
			switch a {
			case "--bundle":
				opts.bundle = all_args[i]
			case "--step":
				s, finished, ok := step_of(all_args[i])
				if !ok { process.console_error(fmt.tprintf("atelier: no step %s\n", all_args[i])); return 2 }
				opts.step, opts.finished, step_asked = s, finished, true
			case "--demo-case":
				c, ok := demo_case_of(all_args[i])
				if !ok { process.console_error(fmt.tprintf("atelier: no demo case %s\n", all_args[i])); return 2 }
				opts.demo_case = c
			}
		case "--demo": opts.demo = true
		case "--after-update": opts.after_update = true
		// (the standard appearance.mode for this run: a picture's look never reaches the person's file)
		case "--look=dark":  append(&args, "--pref", "appearance.mode=dark")
		case "--look=light": append(&args, "--pref", "appearance.mode=light")
		case: append(&args, a)
		}
	}
	if opts.bundle == "" { opts.bundle = process.executable_path() }
	// (a real run starts from a step that needs no choice made before it)
	if step_asked && !opts.demo && opts.step > .Programs { process.console_error("atelier: --step licences, checking, installing and done need --demo\n"); return 2 }
	// (the new copy after the suite's update: the person chooses what to update)
	if opts.after_update && !step_asked { opts.step = .Programs }
	prefs: config.Prefs
	rest, problems := prefs_open(&prefs, args[:])
	defer config.prefs_destroy(&prefs)
	for p in problems { process.console_error(fmt.tprintf("atelier: %s\n", p)) }
	// (--install, --uninstall and --status: atelier's own install, no window; --setup is the window's)
	cmd, words := setup.command_of(rest[:])
	// (its Exit is the process's code: 0 done, 1 failed, 2 to repair for --status)
	if setup.command_alone(cmd) { return int(setup.command_run(cmd, setup_options(), process.console_write)) }
	verb := len(words) > 0 ? words[0] : ""
	switch verb {
	case "":
		return app_run_kept(opts, &prefs, cmd == .Setup)
	case "list":
		if len(words) > 1 { break }
		return list_run(opts.bundle)
	case "install":
		slugs := make([dynamic]string, context.temp_allocator)
		close := false
		for w in words[1:] {
			if w == "--close" { close = true } else { append(&slugs, w) }
		}
		if len(slugs) == 0 { break }
		return install_run(opts.bundle, slugs[:], close)
	case "prefs":
		return prefs_list(&prefs)
	case "set":
		if len(words) != 3 { break }
		return prefs_set(&prefs, words[1], words[2])
	case "version", "--version":
		process.console_write(fmt.tprintf("atelier %s\n", APP_VERSION))
		return 0
	case "help", "-h", "--help":
		process.console_write(USAGE)
		return 0
	}
	process.console_error(USAGE)
	return 2
}

// The bundle for the command line; nil: what is wrong was said.
@(private = "file")
bundle_for_command :: proc(path: string) -> ^Bundle {
	b, err := bundle_open(path)
	switch err {
	case .None:
	case .No_Bundle:    process.console_error(fmt.tprintf("atelier: %s\n", NO_BUNDLE))
	case .Bad_Manifest: process.console_error(fmt.tprintf("atelier: the list of programs in %s cannot be read\n", path))
	}
	return b
}

// `atelier list`: each program, its version carried and its state here (its file taken out and asked, as the window
// does).
list_run :: proc(path: string) -> int {
	b := bundle_for_command(path)
	if b == nil { return 1 }
	defer bundle_destroy(b)
	process.console_write(fmt.tprintf("atelier %s: %d programs for %s, made %s\n", APP_VERSION, len(b.programs), b.platform, b.made))
	// (atelier's own line first, as its row in the window)
	{
		s := own_status()
		process.console_write(fmt.tprintf("  %-16s %-10s %s\n", APP_NAME, APP_VERSION, state_words(s)))
		status_destroy(&s)
		free_all(context.temp_allocator)
	}
	for p in b.programs {
		s := status_of(b, p)
		process.console_write(fmt.tprintf("  %-16s %-10s %s\n", p.slug, p.version, state_words(s)))
		status_destroy(&s)
		scratch_remove(p)
		free_all(context.temp_allocator)
	}
	scratch_end()
	return 0
}

// The state of a program: its file taken out, then asked (Unknown when it cannot be taken out).
status_of :: proc(b: ^Bundle, p: Program, allocator := context.allocator) -> Status {
	path, why := take_out(b, p, context.temp_allocator)
	if why != "" { return {state = .Unknown, reason = strings.clone(why, allocator)} }
	return status_read(path, p.version, allocator)
}

// `atelier install <slug>... | all`: each program installs itself, one after the other. 0 when each one installed. The
// slug atelier is atelier itself (gt:setup, in this process); `all` includes it, first, as in the window. A command line
// asks no question: a program that runs is left as it is, a failure, unless `close` (--close) allows atelier to close it
// first, as the window's "Close them and install" does (src/md/README.md, "A program that runs").
install_run :: proc(path: string, slugs: []string, close := false) -> int {
	b := bundle_for_command(path)
	if b == nil { return 1 }
	defer bundle_destroy(b)
	// (heap: own_install's caller frees the temporary memory between programs)
	chosen := make([dynamic]^Program)
	defer delete(chosen)
	own := false
	for s in slugs {
		if s == "all" {
			own = true
			for &p in b.programs { append(&chosen, &p) }
			continue
		}
		if s == APP_NAME { own = true; continue }
		p := program_of(b, s)
		if p == nil { process.console_error(fmt.tprintf("atelier: no program %s in this bundle\n", s)); return 2 }
		append(&chosen, p)
	}
	failed := 0
	if own && !own_install_run() { failed += 1 }
	for p in chosen {
		file, why := take_out(b, p^, context.temp_allocator)
		ok: bool
		output: string
		exit_code: Maybe(int)
		if why != "" {
			ok, output = false, strings.clone(why)
		} else {
			// (a program installed at this version or a newer one stays as it is: the window does not tick it either)
			s := open_read(file, p.version)
			defer status_destroy(&s)
			if s.state == .Current || s.state == .Newer {
				process.console_write(fmt.tprintf("%s %s: %s, left as it is\n", p.slug, p.version, state_words(s)))
				scratch_remove(p^)
				continue
			}
			if s.running && !close {
				process.console_write(fmt.tprintf("%s %s: it runs: left as it is (close it, or run atelier install --close)\n", p.slug, p.version))
				scratch_remove(p^)
				failed += 1
				continue
			}
			not_closed := ""
			if s.running {
				not_closed = close_program(s.program, s.quits, file)
				if not_closed == "" { process.console_write(fmt.tprintf("%s %s: closed\n", p.slug, p.version)) }
			}
			if not_closed != "" {
				ok, output = false, strings.clone(not_closed)
			} else {
				ok, output, exit_code = install_one(file)
			}
		}
		result := "installed"
		if !ok {
			result = "failed"
			if code, ran := exit_code.?; ran { result = fmt.tprintf("failed (exit code %s)", exit_code_words(code)) }
		}
		process.console_write(fmt.tprintf("%s %s: %s\n", p.slug, p.version, result))
		if output != "" { process.console_write(fmt.tprintf("    %s\n", indent(output))) }
		delete(output)
		scratch_remove(p^)
		if !ok { failed += 1 }
	}
	scratch_end()
	return failed == 0 ? 0 : 1
}

// atelier's own install from the command line: left as it is when this version or a newer one is installed (or Nix
// installs it), as a carried program. True when it is in place.
@(private = "file")
own_install_run :: proc() -> bool {
	defer free_all(context.temp_allocator)   // (gt:setup's strings)
	s := own_status()
	defer status_destroy(&s)
	if s.state == .Current || s.state == .Newer {
		process.console_write(fmt.tprintf("%s %s: %s, left as it is\n", APP_NAME, APP_VERSION, state_words(s)))
		return true
	}
	ok, output := false, ""
	if s.state == .Unknown {
		output = strings.clone(s.reason)
	} else {
		ok, output = own_install()
	}
	defer delete(output)
	process.console_write(fmt.tprintf("%s %s: %s\n", APP_NAME, APP_VERSION, ok ? "installed" : "failed"))
	if output != "" { process.console_write(fmt.tprintf("    %s\n", indent(output))) }
	return ok
}

// A program's output under its line: each of its lines indented.
@(private = "file")
indent :: proc(text: string) -> string {
	s, _ := strings.replace_all(text, "\n", "\n    ", context.temp_allocator)
	return s
}

// The window's run, with its log (gt:log) and its crash reports (gt:crash): a crash leaves a report, which the window's
// bar and the log of the next start say. Nothing is sent anywhere. One atelier at a time: a second start hands its
// launcher's token to the first, whose window comes to the front, and ends (the demo owns nothing: its pictures run
// beside a real atelier).
app_run_kept :: proc(opts: Run_Options, prefs: ^config.Prefs, setup_asked: bool) -> int {
	o := opts
	if !o.demo {
		message := platform.activation_token_from_env(context.temp_allocator)
		outcome: instance.Outcome
		outcome, o.owner = instance.acquire({name = app_instance_name()}, transmute([]u8)message)
		if outcome == .Forwarded { return 0 }
	}
	// (the files keep the technical name; their folders are the vendor's)
	p := host.program_start({name = APP_NAME, folder = APP_FOLDER, version = APP_VERSION})
	defer host.program_end(&p)
	context.logger = p.logger
	o.start = &p
	return app_run(o, prefs, setup_asked)
}

// `atelier prefs`: each preference, its value, and what it does.
@(private = "file")
prefs_list :: proc(prefs: ^config.Prefs) -> int {
	for name in config.sorted_names(prefs) {
		r := config.ref_of(prefs, name)
		e := config.entry(prefs, r)
		if e.def.hidden { continue }
		process.console_write(fmt.tprintf("%s = %s%s\n    %s\n", name, config.value_string(prefs, r), config.is_default(prefs, r) ? "" : "   (changed)", e.def.description))
	}
	return 0
}

// `atelier set <name> <value>`: saved in the user's file (a running atelier reads it at its next start).
@(private = "file")
prefs_set :: proc(prefs: ^config.Prefs, name, value: string) -> int {
	if err := config.set_from_string(prefs, name, value, .User); err != .None {
		process.console_error(fmt.tprintf("atelier: %s: %s\n", name, config.set_error_text(err)))
		return 1
	}
	path := prefs_file()
	if !config.save_user(prefs, path) { process.console_error(fmt.tprintf("atelier: %s cannot be written\n", path)); return 1 }
	return 0
}
