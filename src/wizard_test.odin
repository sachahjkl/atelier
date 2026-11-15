package atelier

import "core:testing"

@(test)
the_steps_follow_the_intent :: proc(t: ^testing.T) {
	// (src/md/README.md, "The steps of the window"): every step and event, the step after it
	after := [Step][Step_Event]Step{
		.Welcome    = {.Next = .Programs, .Back = .Welcome, .Finished = .Welcome, .Retry = .Welcome},
		.Programs   = {.Next = .Licences, .Back = .Welcome, .Finished = .Programs, .Retry = .Programs},
		.Licences   = {.Next = .Checking, .Back = .Programs, .Finished = .Licences, .Retry = .Licences},
		// (the look for the programs that run: Next installs, Back is the person's answer to the question)
		.Checking   = {.Next = .Installing, .Back = .Licences, .Finished = .Checking, .Retry = .Checking},
		// (no Back: an install that started ends)
		.Installing = {.Next = .Installing, .Back = .Installing, .Finished = .Done, .Retry = .Installing},
		// (a retry goes back to Installing, and Finished brings it back)
		.Done       = {.Next = .Done, .Back = .Done, .Finished = .Done, .Retry = .Installing},
	}
	for step in Step {
		for event in Step_Event {
			testing.expectf(t, step_next(step, event) == after[step][event], "%v + %v: %v, not %v", step, event, step_next(step, event), after[step][event])
		}
	}
}

@(test)
a_result_follows_the_intent :: proc(t: ^testing.T) {
	// (src/md/README.md, "The steps of the window"): every result and event, the result after it
	after := [Result][Result_Event]Result{
		.None       = {.Choose = .Waiting, .Start = .None, .Give_Up = .None, .Succeed = .None, .Fail = .None, .Retry = .None},
		// (Back to the question: not chosen any more)
		.Waiting    = {.Choose = .Waiting, .Start = .Installing, .Give_Up = .None, .Succeed = .Waiting, .Fail = .Waiting, .Retry = .Waiting},
		// (Back to the question of a retry: failed, as before it)
		.Retrying   = {.Choose = .Retrying, .Start = .Installing, .Give_Up = .Failed, .Succeed = .Retrying, .Fail = .Retrying, .Retry = .Retrying},
		.Installing = {.Choose = .Installing, .Start = .Installing, .Give_Up = .Installing, .Succeed = .Installed, .Fail = .Failed, .Retry = .Installing},
		.Installed  = {.Choose = .Installed, .Start = .Installed, .Give_Up = .Installed, .Succeed = .Installed, .Fail = .Installed, .Retry = .Installed},
		.Failed     = {.Choose = .Failed, .Start = .Failed, .Give_Up = .Failed, .Succeed = .Failed, .Fail = .Failed, .Retry = .Retrying},
	}
	for r in Result {
		for event in Result_Event {
			testing.expectf(t, result_next(r, event) == after[r][event], "%v + %v: %v, not %v", r, event, result_next(r, event), after[r][event])
		}
	}
	testing.expect(t, result_busy(.Waiting) && result_busy(.Retrying) && result_busy(.Installing))
	testing.expect(t, !result_busy(.None) && !result_busy(.Installed) && !result_busy(.Failed))
}

@(test)
the_look_follows_the_intent :: proc(t: ^testing.T) {
	after := [Look][Look_Event]Look{
		.Idle    = {.Start = .Reading, .None_Run = .Idle, .Some_Run = .Idle, .Shown = .Idle, .Answer = .Idle},
		.Reading = {.Start = .Reading, .None_Run = .Idle, .Some_Run = .To_Ask, .Shown = .Reading, .Answer = .Reading},
		.To_Ask  = {.Start = .To_Ask, .None_Run = .To_Ask, .Some_Run = .To_Ask, .Shown = .Asking, .Answer = .To_Ask},
		.Asking  = {.Start = .Asking, .None_Run = .Asking, .Some_Run = .Asking, .Shown = .Asking, .Answer = .Idle},
	}
	for l in Look {
		for event in Look_Event {
			testing.expectf(t, look_next(l, event) == after[l][event], "%v + %v: %v, not %v", l, event, look_next(l, event), after[l][event])
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
