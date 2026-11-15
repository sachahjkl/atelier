package atelier

// The steps of the window, an explicit state machine (src/md/README.md, "The steps of the window"):
//
//   Welcome -> Programs -> Licences -> Installing -> Done
//                ^  |         |
//                +--+---------+  (Back)
//
// step_next is the only place a step changes. What a step needs before Next (a box ticked) is the view's: its button
// is disabled.

import "core:strings"
import "gt:render"

Step :: enum u8 { Welcome, Programs, Licences, Installing, Done }

Step_Event :: enum u8 {
	Next,       // Choose the programs, Next, Accept and install
	Back,
	Finished,   // the last install ended
}

// The step after `event` on `step`. Installing has no Back: an install that started ends.
step_next :: proc(step: Step, event: Step_Event) -> Step {
	switch step {
	case .Welcome:
		if event == .Next { return .Programs }
	case .Programs:
		switch event {
		case .Next:     return .Licences
		case .Back:     return .Welcome
		case .Finished:
		}
	case .Licences:
		switch event {
		case .Next:     return .Installing
		case .Back:     return .Programs
		case .Finished:
		}
	case .Installing:
		if event == .Finished { return .Done }
	case .Done:
	}
	return step
}

// The name of a step on the command line (--step).
STEP_NAMES := [Step]string{.Welcome = "welcome", .Programs = "programs", .Licences = "licences", .Installing = "installing", .Done = "done"}

step_of :: proc(name: string) -> (Step, bool) {
	for n, s in STEP_NAMES { if n == name { return s, true } }
	return .Welcome, false
}

// The phases of one program's install, shown as its stepper's nodes: its file taken out (or checked again), its own
// `--install`, then `--status` read again (the carried version must be installed).
Install_Phase :: enum u8 { Unpack, Install, Check }

// How the install of a chosen program went.
Result :: enum u8 {
	None,         // not chosen
	Waiting,
	Installing,
	Installed,
	Failed,
}

// One program of the bundle in the window: its box, its state, its logo, its licences' texts and its install.
Row :: struct {
	ticked:    bool,
	status:    Status,          // its strings owned
	scratch:   string,          // its file taken out ("": not, or deleted after its install; owned)
	logo:      render.Texture,
	logo_size: [2]f32,          // {}: no logo
	licences:  []string,        // each licence's text, read when the Licences step first shows them (owned; nil: not read)
	result:    Result,
	phase:     Install_Phase,   // Installing: the phase under way; Failed: the phase that failed
	output:    string,          // what its --install said, or why a phase failed (owned)
}

row_destroy :: proc(r: ^Row) {
	status_destroy(&r.status)
	delete(r.scratch)
	for t in r.licences { delete(t) }
	delete(r.licences)
	delete(r.output)
	r^ = {}
}

// The status came: the box follows the state (state_ticked) when `tick`. A status that comes once the person went past
// the Programs step changes no box: the licences shown and the installs started are those of the boxes they saw.
row_status :: proc(r: ^Row, s: Status, tick := true) {
	status_destroy(&r.status)
	r.status = s
	if tick { r.ticked = state_ticked(s.state) }
}

// The file taken out for the row ("": none any more).
row_scratch_set :: proc(r: ^Row, path: string) {
	delete(r.scratch)
	r.scratch = strings.clone(path)
}
