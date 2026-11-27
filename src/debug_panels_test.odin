package atelier

import "core:strings"
import "core:testing"
import debug "gt:debug"
import "gt:ui"

// The panels on a bare State, no window: their values set and their acts pressed as a tool does.
@(test)
the_debug_panels_act_on_atelier :: proc(t: ^testing.T) {
	s: ui.State
	ui.init(&s, nil, nil)
	defer ui.destroy(&s)
	b: Bundle
	b.platform = "linux-x64"
	programs := []Program{{slug = "atelier", name = "Atelier", own = true}, {slug = "papier", name = "Papier", version = "1.0.0"}}
	rows := make([]Row, len(programs))
	defer delete(rows)
	rows[1].status.state = .Absent
	app := App{bundle = &b, programs = programs, rows = rows, step = .Programs, known = true}
	debug_panels(&s, &app)

	sb := strings.builder_make(context.temp_allocator)
	debug.list(&s, &sb)
	for path in ([]string{"Steps/step", "Programs/Papier/state", "Bundle/platform", "Updates/phase"}) {
		testing.expectf(t, strings.contains(strings.to_string(sb), path), "%s listed", path)
	}

	testing.expect_value(t, debug.press(&s, "Steps/Select all"), "")
	testing.expect(t, rows[1].ticked, "Select all ticks a program that can be ticked")
	testing.expect_value(t, debug.press(&s, "Steps/Select none"), "")
	testing.expect(t, !rows[1].ticked, "Select none")

	testing.expect_value(t, debug.set(&s, "Programs/Papier/state", "Older"), "")
	testing.expect_value(t, rows[1].status.state, State.Older)

	testing.expect_value(t, debug.set(&s, "Steps/fail the next install", "true"), "")
	testing.expect(t, app.fail_next, "the failure on demand is asked")

	// (the window's guards: Retry needs the Installing step, so the act does nothing on Programs)
	testing.expect_value(t, debug.press(&s, "Steps/Retry failed"), "")
	testing.expect_value(t, app.step, Step.Programs)
	testing.expect_value(t, debug.press(&s, "Steps/Back"), "")
	testing.expect_value(t, app.step, Step.Welcome)
}
