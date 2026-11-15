// atelier: the suite of Froment Software's desktop programs as one download (src/md/README.md).
//
// The release is this program with a zip written after its own bytes: the programs it carries, their logos and
// licences (bundle.odin). The window (app.odin, view.odin) lets the person choose the programs, shows their licences,
// then has each one install itself (`<program> --install`, install.odin), all at once, each on a worker.
package atelier

import "core:fmt"
import "core:os"
import "core:strings"
import crash "gt:crash"
import tk_log "gt:log"
import process "gt:process"
import "gt:ui"

APP_NAME :: "atelier"
APP_VERSION :: "0.1.2"

USAGE :: `atelier: Froment Software's programs, chosen and installed at once

  atelier                         the window: choose the programs, read their licences, install them
  atelier list                    the programs carried, their version and their state here; no window
  atelier install <slug>... | all those programs installed, without a window (exit 0 when each one installed)
  atelier --bundle <file>         the programs of another file (a bundle made by ateliertool bundle)
  atelier --demo                  the window with made-up states: nothing is read of this computer, nothing runs
                                  (the pictures of the site); the names, logos and licences are the bundle's
  atelier --step <name>           the window on a step: welcome, programs, licences, installing, done (with --demo:
                                  the pictures; without it, welcome or programs only)
  atelier --look=dark|light       the window dark or light, whatever the system prefers
  atelier --version
  atelier --help
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
	step:       Step,
	look:       ui.Theme_Mode,   // the theme's version: the system's, unless --look=dark or --look=light
	last_crash: string,   // the report of the last run, which crashed ("": it ended cleanly)
}

run :: proc(all_args: []string) -> int {
	opts := Run_Options{step = .Welcome}
	step_asked := false
	args := make([dynamic]string, context.temp_allocator)
	for i := 0; i < len(all_args); i += 1 {
		a := all_args[i]
		switch a {
		case "--bundle", "--step":
			if i + 1 >= len(all_args) { process.console_error(USAGE); return 2 }
			i += 1
			if a == "--bundle" {
				opts.bundle = all_args[i]
			} else {
				s, ok := step_of(all_args[i])
				if !ok { process.console_error(fmt.tprintf("atelier: no step %s\n", all_args[i])); return 2 }
				opts.step, step_asked = s, true
			}
		case "--demo": opts.demo = true
		case "--look=dark":  opts.look = .Dark
		case "--look=light": opts.look = .Light
		case: append(&args, a)
		}
	}
	if opts.bundle == "" { opts.bundle = process.executable_path() }
	// (a real run starts from a step that needs no choice made before it)
	if step_asked && !opts.demo && opts.step > .Programs { process.console_error("atelier: --step licences, installing and done need --demo\n"); return 2 }
	verb := len(args) > 0 ? args[0] : ""
	switch verb {
	case "":
		return app_run_kept(opts)
	case "list":
		if len(args) > 1 { break }
		return list_run(opts.bundle)
	case "install":
		if len(args) < 2 { break }
		return install_run(opts.bundle, args[1:])
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

// `atelier install <slug>... | all`: each program installs itself, one after the other. 0 when each one installed.
install_run :: proc(path: string, slugs: []string) -> int {
	b := bundle_for_command(path)
	if b == nil { return 1 }
	defer bundle_destroy(b)
	chosen := make([dynamic]^Program, context.temp_allocator)
	for s in slugs {
		if s == "all" {
			for &p in b.programs { append(&chosen, &p) }
			continue
		}
		p := program_of(b, s)
		if p == nil { process.console_error(fmt.tprintf("atelier: no program %s in this bundle\n", s)); return 2 }
		append(&chosen, p)
	}
	failed := 0
	for p in chosen {
		file, why := take_out(b, p^, context.temp_allocator)
		ok: bool
		output: string
		if why != "" {
			ok, output = false, strings.clone(why)
		} else {
			// (a program installed at this version or a newer one stays as it is: the window does not tick it either)
			s := status_read(file, p.version)
			defer status_destroy(&s)
			if s.state == .Current || s.state == .Newer {
				process.console_write(fmt.tprintf("%s %s: %s, left as it is\n", p.slug, p.version, state_words(s)))
				scratch_remove(p^)
				continue
			}
			ok, output = install_one(file)
		}
		process.console_write(fmt.tprintf("%s %s: %s\n", p.slug, p.version, ok ? "installed" : "failed"))
		if output != "" { process.console_write(fmt.tprintf("    %s\n", indent(output))) }
		delete(output)
		scratch_remove(p^)
		if !ok { failed += 1 }
	}
	scratch_end()
	return failed == 0 ? 0 : 1
}

// A program's output under its line: each of its lines indented.
@(private = "file")
indent :: proc(text: string) -> string {
	s, _ := strings.replace_all(text, "\n", "\n    ", context.temp_allocator)
	return s
}

// The window's run, with its log (gt:log) and its crash reports (gt:crash): a crash leaves a report, which the log of
// the next start says. Nothing is sent anywhere.
app_run_kept :: proc(opts: Run_Options) -> int {
	logger := tk_log.install({program = APP_NAME, echo = true})
	code: int
	{
		context.logger = logger
		crash.install({program = APP_NAME, version = APP_VERSION, log_tail = {tk_log.tail, logger.data}})
		crash.begin_session()
		o := opts
		last, crashed := crash.last_report(context.temp_allocator)
		// (the frames free the temporary memory: the report's path is kept on the heap)
		if crashed { o.last_crash = strings.clone(last) }
		code = app_run(o)
		delete(o.last_crash)
		crash.end_session()
	}
	tk_log.close(logger)
	return code
}
