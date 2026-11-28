package atelier

// The state machines of the window (src/md/README.md, "The steps of the window"): the steps, each chosen program's
// result, and the look for the programs that run. Each one changes only through its `_next` procedure; what a step
// needs before Next (a box ticked) is the view's: its button is disabled.
//
//   Welcome -> Programs -> Licences -> Checking -> Installing
//                ^  |         |  ^         |
//                +--+---------+  +---------+ (Back)
//
// Installing is the last step: its own stage (Install_Stage) says whether the installs are under way.

import "core:strings"
import "gt:render"

Step :: enum u8 { Welcome, Programs, Licences, Checking, Installing }

Step_Event :: enum u8 {
	Next,   // Choose the programs, Next, Accept and install; Checking: no program runs, or the person closes them
	Back,   // Checking: the person answered Back to the question
}

// The step after `event` on `step`. Installing has no way out: an install that started ends, and its result shows on
// the same rows.
step_next :: proc(step: Step, event: Step_Event) -> Step {
	switch step {
	case .Welcome:
		if event == .Next { return .Programs }
	case .Programs:
		#partial switch event {
		case .Next: return .Licences
		case .Back: return .Welcome
		}
	case .Licences:
		#partial switch event {
		case .Next: return .Checking
		case .Back: return .Programs
		}
	case .Checking:
		#partial switch event {
		case .Next: return .Installing
		case .Back: return .Licences
		}
	case .Installing:
	}
	return step
}

// The stage of the Installing step:
//
//   Running -> Finished -> Retrying
//                 ^           |
//                 +-----------+ (all ended)
//
// Retrying is not Running again: its top panel stays the summary, with "Retry the failed ones" busy, so that a retry
// moves nothing on the screen.
Install_Stage :: enum u8 {
	Running,    // the first installs: some row is Waiting or Installing
	Finished,   // no row is busy: the summary
	Retrying,   // a retry is under way
}

Stage_Event :: enum u8 {
	All_Ended,   // no row is busy any more
	Retry,       // failed rows start again
}

stage_next :: proc(s: Install_Stage, event: Stage_Event) -> Install_Stage {
	switch s {
	case .Running, .Retrying:
		if event == .All_Ended { return .Finished }
	case .Finished:
		if event == .Retry { return .Retrying }
	}
	return s
}

// The name of a step on the command line (--step). `done` is not a step: it is Installing once Finished (the demo).
STEP_NAMES := [Step]string{.Welcome = "welcome", .Programs = "programs", .Licences = "licences", .Checking = "checking", .Installing = "installing"}
STEP_DONE :: "done"

step_of :: proc(name: string) -> (step: Step, finished: bool, ok: bool) {
	if name == STEP_DONE { return .Installing, true, true }
	for n, s in STEP_NAMES { if n == name { return s, false, true } }
	return .Welcome, false, false
}

// The phases of one program's install, shown as its stepper's nodes: the copy that runs closed (Skipped when none ran),
// its file taken out (or checked again), its own `--install`, then `--status` read again (the carried version must be
// installed).
Install_Phase :: enum u8 { Close, Unpack, Install, Check }

// How the install of a chosen program goes.
//
//   None -> Waiting -> Installing -> Installed
//             |            |
//             v (Back)     v
//           None         Failed -> Retrying -> Installing
//                                     |
//                                     v (Back)
//                                   Failed
Result :: enum u8 {
	None,         // not chosen
	Waiting,      // chosen: the look for a copy that runs, then the question
	Retrying,     // failed, and started again: the look, then the question
	Installing,
	Installed,
	Failed,
}

Result_Event :: enum u8 {
	Choose,    // "Accept and install"
	Start,     // the look found no copy that runs, or the person agreed to close it
	Give_Up,   // the person answered Back
	Succeed,
	Fail,
	Retry,
}

result_next :: proc(r: Result, event: Result_Event) -> Result {
	switch r {
	case .None:
		if event == .Choose { return .Waiting }
	case .Waiting:
		#partial switch event {
		case .Start:   return .Installing
		case .Give_Up: return .None
		}
	case .Retrying:
		#partial switch event {
		case .Start:   return .Installing
		case .Give_Up: return .Failed
		}
	case .Installing:
		#partial switch event {
		case .Succeed: return .Installed
		case .Fail:    return .Failed
		}
	case .Installed:
	case .Failed:
		if event == .Retry { return .Retrying }
	}
	return r
}

// Whether the row's install is not over: its look, its question or its phases are under way.
result_busy :: proc(r: Result) -> bool {
	return r == .Waiting || r == .Retrying || r == .Installing
}

// The look for the programs that run, one at a time:
//
//   Idle -> Reading -> To_Ask -> Asking -> Idle (the answer)
//              |
//              +-> Idle (none runs)
//
// To_Ask: a dialog opens in a build, and the worker's answer comes between two builds.
Look :: enum u8 { Idle, Reading, To_Ask, Asking }

Look_Event :: enum u8 { Start, None_Run, Some_Run, Shown, Answer }

look_next :: proc(l: Look, event: Look_Event) -> Look {
	switch l {
	case .Idle:
		if event == .Start { return .Reading }
	case .Reading:
		#partial switch event {
		case .None_Run: return .Idle
		case .Some_Run: return .To_Ask
		}
	case .To_Ask:
		if event == .Shown { return .Asking }
	case .Asking:
		if event == .Answer { return .Idle }
	}
	return l
}

// The uninstall confirmation for one row on the Programs step:
//
//   Idle --(Start)--> Checking --(Ready)--> To_Ask --(Shown)--> Asking --(Answer)--> Idle
//     |                                       ^
//     +--------------(Ask_Now)----------------+   (Atelier's own row or demo: no look needed)
Uninstall_Ask :: enum u8 { Idle, Checking, To_Ask, Asking }

Uninstall_Event :: enum u8 { Start, Ask_Now, Ready, Shown, Answer }

uninstall_ask_next :: proc(u: Uninstall_Ask, event: Uninstall_Event) -> Uninstall_Ask {
	switch u {
	case .Idle:
		#partial switch event {
		case .Start:   return .Checking
		case .Ask_Now: return .To_Ask
		}
	case .Checking:
		if event == .Ready { return .To_Ask }
	case .To_Ask:
		if event == .Shown { return .Asking }
	case .Asking:
		if event == .Answer { return .Idle }
	}
	return u
}

// One program of the bundle in the window: its box, its state, its logo, its licences' texts and its install.
Row :: struct {
	ticked:       bool,
	uninstalling: bool,         // Programs: an uninstall worker is running for this row
	status:    Status,          // its strings owned
	scratch:   string,          // its file taken out ("": not, or deleted after its install; owned)
	logo:      render.Texture,
	logo_size: [2]f32,          // {}: no logo
	licences:  []string,        // each licence's text, read when the Licences step first shows them (owned; nil: not read)
	result:    Result,
	phase:     Install_Phase,   // Installing: the phase under way; Failed: the phase that failed
	close:     bool,            // a copy of it ran and the person agreed to close it: its Close phase runs
	output:    string,          // what its --install said, or why a phase failed (owned)
	exit_code: Maybe(int),      // its --install's exit code (nil: the phase that failed ran no process)
	details:   bool,            // Failed: its whole output is shown
}

row_destroy :: proc(r: ^Row) {
	status_destroy(&r.status)
	delete(r.scratch)
	for t in r.licences { delete(t) }
	delete(r.licences)
	delete(r.output)
	r^ = {}
}

// The status came: the box follows the state (state_ticked) when `tick`, and stays empty when not `ticked` (the
// preference programs.ticked off). A status that comes once the person went past the Programs step changes no box: the
// licences shown and the installs started are those of the boxes they saw.
row_status :: proc(r: ^Row, s: Status, tick := true, ticked := true) {
	status_destroy(&r.status)
	r.status = s
	if tick { r.ticked = ticked && state_ticked(s.state) }
}

// The file taken out for the row ("": none any more).
row_scratch_set :: proc(r: ^Row, path: string) {
	delete(r.scratch)
	r.scratch = strings.clone(path)
}
