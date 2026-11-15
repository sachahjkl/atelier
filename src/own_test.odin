package atelier

import "core:testing"
import setup "gt:setup"

// gt:setup's states of atelier's install, as the states of its row (src/md/README.md, "atelier's own row").
@(test)
each_setup_state_is_a_row_state :: proc(t: ^testing.T) {
	Case :: struct { facts: setup.Facts, state: State, by_nix: bool }
	cases := []Case{
		{{state = .Not_Installed}, .Absent, false},
		{{state = .Removal_Scheduled}, .Absent, false},
		{{state = .Repair}, .Repair, false},
		{{state = .This_Copy, version = APP_VERSION, exe_there = true, exe = "/home/me/.local/share/atelier/atelier"}, .Current, false},
		{{state = .Other_Copy, version = "0.0.1", exe_there = true}, .Older, false},
		{{state = .Other_Copy, version = APP_VERSION, exe_there = true}, .Current, false},
		{{state = .Other_Copy, version = "99.0.0", exe_there = true}, .Newer, false},
		// (a version that does not read as one: installed, nothing to offer)
		{{state = .Other_Copy, version = "", exe_there = true}, .Current, false},
		{{state = .Nix_Package}, .Current, true},
	}
	for c in cases {
		s := own_status_of(c.facts)
		defer status_destroy(&s)
		testing.expectf(t, s.state == c.state && s.by_nix == c.by_nix, "%v: %v (nix %v), not %v", c.facts.state, s.state, s.by_nix, c.state)
	}
	s := own_status_of({state = .This_Copy, exe_there = true, exe = "/home/me/.local/share/atelier/atelier"})
	defer status_destroy(&s)
	testing.expect_value(t, s.program, "/home/me/.local/share/atelier/atelier")
}

// A Nix package of atelier has no box: the Nix configuration installs it.
@(test)
atelier_from_nix_has_no_box :: proc(t: ^testing.T) {
	b := Bundle{}
	app := App{bundle = &b, rows = make([]Row, 1, context.temp_allocator), known = true}
	app.rows[0].status = {state = .Current, by_nix = true}
	testing.expect(t, !row_choosable(&app, app.rows[0]), "a Nix package is not choosable")
	app.rows[0].status.by_nix = false
	testing.expect(t, row_choosable(&app, app.rows[0]), "an installed copy can be ticked again")
}

// atelier's own install takes nothing out: Unpack is skipped, never done, while it copies itself and once installed.
@(test)
the_own_stepper_skips_unpack :: proc(t: ^testing.T) {
	for result in ([]Result{.Installing, .Installed}) {
		steps := install_steps(Row{result = result, phase = .Install}, own = true)
		testing.expectf(t, steps[int(Install_Phase.Unpack)].state == .Skipped, "%v: Unpack %v", result, steps[0].state)
		testing.expect_value(t, steps[int(Install_Phase.Install)].label, "Copy")
	}
	carried := install_steps(Row{result = .Installing, phase = .Install})
	testing.expectf(t, carried[int(Install_Phase.Unpack)].state == .Done, "a carried program's Unpack is done: %v", carried[0].state)
}

// A bundle cannot name a program atelier: the slug is atelier's own row, on the command line too.
@(test)
a_bundle_cannot_carry_atelier :: proc(t: ^testing.T) {
	b := new(Bundle)
	defer bundle_destroy(b)
	manifest := `{"schema": 1, "platform": "linux-x64", "made": "2026-11-15", "programs": [{"slug": "atelier", "name": "atelier",
		"version": "0.1.0", "file": "atelier/atelier", "size": 1, "sha256": "0000000000000000000000000000000000000000000000000000000000000000"}]}`
	testing.expect(t, !bundle_parse(b, transmute([]u8)string(manifest)), "the slug atelier is refused")
}
