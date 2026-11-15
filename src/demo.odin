package atelier

// The demo (--demo): made-up states for the programs of a real bundle, for the pictures of the site. Nothing of the
// computer is read and nothing runs: no file is taken out, no --status, no --install. The names, the logos and the
// licences are the bundle's.

import "core:fmt"
import "core:strconv"
import "core:strings"

// The states the demo gives the programs, in the bundle's order, round again past the last.
@(private = "file")
DEMO_STATES := [?]State{.Absent, .Older, .Current, .Absent, .Repair, .Newer}

// Gives each row its made-up state, then shows `step` as a real run would have reached it.
demo_step :: proc(app: ^App, step: Step) {
	app.known = true
	for &r, i in app.rows {
		p := app.bundle.programs[i]
		s := Status{state = DEMO_STATES[i % len(DEMO_STATES)]}
		#partial switch s.state {
		case .Older:   s.installed = demo_version(p.version, -1)
		case .Newer:   s.installed = demo_version(p.version, +1)
		case .Current: s.installed = strings.clone(p.version)
		}
		row_status(&r, s)
	}
	app.step = .Welcome
	if step == .Welcome { return }
	app_step(app, .Next)
	if step == .Programs { return }
	app_step(app, .Next)
	if step == .Licences { return }
	app_step(app, .Next)
	if step == .Installing { return }
	for &r, i in app.rows {
		if r.result == .None { continue }
		r.result = .Installed
		delete(r.status.program)
		r.status.program = demo_place(app.bundle.programs[i])
	}
	app.step = .Done
}

// The Installing step of the demo, as it looks halfway through installs side by side: each program at another phase,
// the first one done.
demo_install :: proc(app: ^App) {
	n := 0
	for &r in app.rows {
		if r.result != .Waiting { continue }
		switch n {
		case 0:  r.result = .Installed
		case 1:  r.result, r.phase = .Installing, .Check
		case 2:  r.result, r.phase = .Installing, .Install
		case:    r.result, r.phase = .Installing, .Unpack
		}
		n += 1
	}
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
