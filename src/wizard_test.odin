package atelier

import "core:testing"

@(test)
the_steps_follow_the_intent :: proc(t: ^testing.T) {
	// (src/md/README.md, "The steps of the window"): every step and event, the step after it
	after := [Step][Step_Event]Step{
		.Welcome    = {.Next = .Programs, .Back = .Welcome},
		.Programs   = {.Next = .Licences, .Back = .Welcome},
		.Licences   = {.Next = .Checking, .Back = .Programs},
		// (the look for the programs that run: Next installs, Back is the person's answer to the question)
		.Checking   = {.Next = .Installing, .Back = .Licences},
		// (the last step: an install that started ends, and its result shows on the same rows)
		.Installing = {.Next = .Installing, .Back = .Installing},
	}
	for step in Step {
		for event in Step_Event {
			testing.expectf(t, step_next(step, event) == after[step][event], "%v + %v: %v, not %v", step, event, step_next(step, event), after[step][event])
		}
	}
}

@(test)
the_install_stage_follows_the_intent :: proc(t: ^testing.T) {
	// (src/md/README.md, "The steps of the window"): a retry never goes back to Running, so the top panel stays the summary
	after := [Install_Stage][Stage_Event]Install_Stage{
		// (a row retried while the first installs run: they are still the first installs)
		.Running  = {.All_Ended = .Finished, .Retry = .Running},
		.Finished = {.All_Ended = .Finished, .Retry = .Retrying},
		.Retrying = {.All_Ended = .Finished, .Retry = .Retrying},
	}
	for s in Install_Stage {
		for event in Stage_Event {
			testing.expectf(t, stage_next(s, event) == after[s][event], "%v + %v: %v, not %v", s, event, stage_next(s, event), after[s][event])
		}
	}
}

@(test)
a_failure_says_why_in_one_line :: proc(t: ^testing.T) {
	// (the first line that says something; advice is no cause)
	out := "\n  papier: on NixOS a Nix package is the better install: Nix updates it\npapier: the install failed: the folder cannot be written\n  more"
	testing.expect_value(t, failure_reason(out, .Install, 1), "papier: the install failed: the folder cannot be written")
	// (nothing said: the exit code; a Windows NTSTATUS in hex, with its meaning)
	testing.expect_value(t, failure_reason("", .Install, 3), "The install did not finish: the program gave no reason. Its exit code: 3")
	testing.expect_value(t, failure_reason("  \n", .Install, int(u32(0xC0000135))), "The install did not finish: the program gave no reason. Its exit code: 0xC0000135 (a DLL that it needs is missing)")
	testing.expect_value(t, failure_reason("", .Unpack, nil), "The Unpack phase failed: atelier has no reason for it.")
	// (read back as a signed 32-bit code, the same status)
	testing.expect_value(t, exit_code_words(int(i32(-1073741819))), "0xC0000005 (it crashed)")
	testing.expect_value(t, exit_code_words(int(u32(0xC0000142))), "0xC0000142")
	testing.expect_value(t, exit_code_words(0), "0")
}

@(test)
details_show_the_output_and_the_exit_code :: proc(t: ^testing.T) {
	testing.expect_value(t, failure_details(Row{output = "it failed", exit_code = 2}), "it failed\n\nExit code: 2")
	testing.expect_value(t, failure_details(Row{exit_code = int(u32(0xC0000135))}), "Exit code: 0xC0000135 (a DLL that it needs is missing)")
	// (atelier's own one-line why: the reason says it all)
	testing.expect_value(t, failure_details(Row{output = "the file cannot be read from the bundle"}), "")
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
		s, finished, ok := step_of(name)
		testing.expect(t, ok && s == step && !finished, name)
	}
	// (done: the install step once over, for the demo's pictures)
	s, finished, ok := step_of(STEP_DONE)
	testing.expect(t, ok && s == .Installing && finished, "done is the install, finished")
	_, _, ok = step_of("install")
	testing.expect(t, !ok, "an unknown step is refused")
}
