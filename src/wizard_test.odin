package atelier

import "core:testing"

@(test)
the_steps_follow_the_intent :: proc(t: ^testing.T) {
	// (src/md/README.md, "The steps of the window"): every step and event, the step after it
	after := [Step][Step_Event]Step{
		.Welcome    = {.Next = .Programs, .Back = .Welcome, .Finished = .Welcome},
		.Programs   = {.Next = .Licences, .Back = .Welcome, .Finished = .Programs},
		.Licences   = {.Next = .Installing, .Back = .Programs, .Finished = .Licences},
		// (no Back: an install that started ends)
		.Installing = {.Next = .Installing, .Back = .Installing, .Finished = .Done},
		.Done       = {.Next = .Done, .Back = .Done, .Finished = .Done},
	}
	for step in Step {
		for event in Step_Event {
			testing.expectf(t, step_next(step, event) == after[step][event], "%v + %v: %v, not %v", step, event, step_next(step, event), after[step][event])
		}
	}
}

@(test)
a_step_is_named_on_the_command_line :: proc(t: ^testing.T) {
	for name, step in STEP_NAMES {
		s, ok := step_of(name)
		testing.expect(t, ok && s == step, name)
	}
	_, ok := step_of("install")
	testing.expect(t, !ok, "an unknown step is refused")
}
