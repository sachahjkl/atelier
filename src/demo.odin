package atelier

// The demo (--demo): made-up states for the programs of a real bundle, for the pictures of the site. Nothing of the
// computer is read and nothing runs: no file is taken out, no --status, no --install. The names, the logos and the
// licences are the bundle's.

import "core:fmt"
import "core:strconv"
import "core:strings"

// What more the demo shows (--demo-case), for the pictures.
Demo_Case :: enum u8 {
	None,
	Failure,   // one install fails: its Retry
	Update,    // a newer suite is on offer: the banner, and the notes of the rows
}

DEMO_CASE_NAMES := [Demo_Case]string{.None = "none", .Failure = "failure", .Update = "update"}

demo_case_of :: proc(name: string) -> (Demo_Case, bool) {
	for n, c in DEMO_CASE_NAMES { if n == name { return c, true } }
	return .None, false
}

// The states the demo gives the programs, in the bundle's order, round again past the last. atelier's own row is
// Absent: the pictures show a first start, from the downloaded file.
@(private = "file")
DEMO_STATES := [?]State{.Absent, .Older, .Current, .Absent, .Repair, .Newer}

// Gives each row its made-up state, then shows `step` as a real run would have reached it.
demo_step :: proc(app: ^App, step: Step) {
	app.known = true
	carried := 0
	for &r, i in app.rows {
		p := app.programs[i]
		s := Status{state = .Absent}
		if !p.own {
			s.state = DEMO_STATES[carried % len(DEMO_STATES)]
			carried += 1
		}
		#partial switch s.state {
		case .Older:   s.installed = demo_version(p.version, -1)
		case .Newer:   s.installed = demo_version(p.version, +1)
		case .Current: s.installed = strings.clone(p.version)
		}
		row_status(&r, s)
	}
	if app.demo_case == .Update { demo_suite(app) }
	app.step = .Welcome
	if step == .Welcome { return }
	app_step(app, .Next)
	if step == .Programs { return }
	app_step(app, .Next)
	if step == .Licences { return }
	app_step(app, .Next)
	// (the same two programs run in every picture after it: their Close phase shows done)
	demo_ask(app)
	if step == .Checking { return }
	app.look = look_next(app.look, .Shown)
	app.look = look_next(app.look, .Answer)
	app_step(app, .Next)
	if step == .Installing { return }
	failed := false
	for &r, i in app.rows {
		if r.result == .None { continue }
		delete(r.output)
		r.output = ""
		// (the first carried program fails, with the words a program's --install says)
		if app.demo_case == .Failure && !failed && !app.programs[i].own {
			failed = true
			r.result, r.phase = .Failed, .Install
			r.output = strings.clone(fmt.tprintf("%s: the install failed: the install folder cannot be written", app.programs[i].name))
			continue
		}
		r.result = .Installed
		delete(r.status.program)
		r.status.program = demo_place(app.programs[i])
	}
	app.step = .Done
}

// A newer suite on offer in the demo: the next atelier, which carries the first two programs at their next version.
@(private = "file")
demo_suite :: proc(app: ^App) {
	app.suite_version = demo_version(APP_VERSION, +1)
	newer := make([dynamic]Newer_Program)
	for p in app.programs {
		if p.own { continue }
		if len(newer) == 2 { break }
		append(&newer, Newer_Program{strings.clone(p.slug), strings.clone(p.name), demo_version(p.version, +1)})
	}
	app.suite_newer = newer[:]
}

// The question of the demo: the first two carried programs chosen run.
@(private = "file")
demo_ask :: proc(app: ^App) {
	for i in app.batch {
		if app.programs[i].own { continue }
		if len(app.asking) == 2 { break }
		append(&app.asking, i)
	}
	app.look = look_next(look_next(app.look, .Start), .Some_Run)
}

// The Installing step of the demo, as it looks halfway through installs side by side: each program at another phase,
// the first one done. The programs the question named close first. With the case Failure, one has failed.
demo_install :: proc(app: ^App) {
	for i in app.asking { app.rows[i].close = true }
	clear(&app.batch)
	clear(&app.asking)
	n := 0
	for &r, i in app.rows {
		if r.result != .Waiting { continue }
		// (atelier's own copies itself: its stepper turns on Copy, its Close and Unpack skipped)
		if app.programs[i].own {
			r.result, r.phase = .Installing, .Install
			continue
		}
		switch n {
		case 0:  r.result = .Installed
		case 1:  r.result, r.phase = .Installing, .Check
		case 2:
			r.result, r.phase = .Installing, .Install
			if app.demo_case == .Failure {
				r.result = .Failed
				r.output = strings.clone(fmt.tprintf("%s: the install failed: the install folder cannot be written", app.programs[i].name))
			}
		case 3:  r.result, r.phase = .Installing, r.close ? .Close : .Unpack
		case:    r.result, r.phase = .Installing, .Unpack
		}
		n += 1
	}
}

// The demo's installs start after the question, or again after a retry: the rows retried install at once.
demo_go :: proc(app: ^App) {
	if app.step == .Checking {
		app_step(app, .Next)
		return
	}
	for i in app.batch {
		r := &app.rows[i]
		if r.result != .Retrying { continue }
		r.result = result_next(result_next(r.result, .Start), .Succeed)
		delete(r.status.program)
		r.status.program = demo_place(app.programs[i])
	}
	clear(&app.batch)
	clear(&app.asking)
	install_finished(app)
}

// A version next to `v`: its last number one lower (`delta` -1) or one higher (+1); "0.9.0" when `v` reads as none.
@(private = "file")
demo_version :: proc(v: string, delta: int) -> string {
	parts := strings.split(v, ".", context.temp_allocator)
	if len(parts) != 3 { return strings.clone("0.9.0") }
	n := [3]int{}
	for p, i in parts {
		x, ok := strconv.parse_int(p)
		if !ok { return strings.clone("0.9.0") }
		n[i] = x
	}
	switch {
	case delta > 0:  n[2] += 1
	case n[2] > 0:   n[2] -= 1
	case n[1] > 0:   n[1] -= 1
	case n[0] > 0:   n[0] -= 1
	}
	return fmt.aprintf("%d.%d.%d", n[0], n[1], n[2])
}
