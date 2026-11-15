package atelier

import "core:strings"
import "core:testing"

// What gt:setup's --status prints (command.odin's status_text), with the installed copy's version and place.
@(private = "file")
status_text :: proc(state_words, program, version: string) -> string {
	return strings.concatenate({"Papier: ", state_words, "\n  program: ", program, "\n  version: ", version,
		"\n  this copy: 0.23.2 /home/me/.cache/atelier/papier-0.23.2/papier\n  menu entry: yes\n  start with the session: yes\n  on the PATH: yes\n  running: false\n"}, context.temp_allocator)
}

@(test)
each_exit_code_of_status_is_a_state :: proc(t: ^testing.T) {
	Case :: struct { code: int, text: string, carried: string, state: State, installed: string }
	cases := []Case{
		{1, status_text("not installed", "-", "-"), "0.23.2", .Absent, ""},
		{2, status_text("installed, to repair", "-", "0.23.2"), "0.23.2", .Repair, "0.23.2"},
		{0, status_text("installed (another copy)", "/home/me/.local/share/papier/papier", "0.23.1"), "0.23.2", .Older, "0.23.1"},
		{0, status_text("installed (another copy)", "/home/me/.local/share/papier/papier", "0.23.2"), "0.23.2", .Current, "0.23.2"},
		{0, status_text("installed (another copy)", "/home/me/.local/share/papier/papier", "0.24.0"), "0.23.2", .Newer, "0.24.0"},
		{0, status_text("installed (another copy)", "/home/me/.local/share/papier/papier", "0.9.10"), "0.10.0", .Older, "0.9.10"},
		// (installed, its version not said: nothing to offer)
		{0, status_text("installed by Nix", "-", "-"), "0.23.2", .Current, ""},
	}
	for c in cases {
		s := status_parse(c.code, c.text, c.carried)
		defer status_destroy(&s)
		testing.expectf(t, s.state == c.state, "exit %d, version %q: %v, not %v", c.code, c.installed, s.state, c.state)
		testing.expect_value(t, s.installed, c.installed)
	}
}

@(test)
the_installed_program_is_read_from_status :: proc(t: ^testing.T) {
	s := status_parse(0, status_text("installed (another copy)", "/home/me/.local/share/papier/papier", "0.23.2"), "0.23.2")
	defer status_destroy(&s)
	testing.expect_value(t, s.program, "/home/me/.local/share/papier/papier")
	none := status_parse(1, status_text("not installed", "-", "-"), "0.23.2")
	defer status_destroy(&none)
	testing.expect_value(t, none.program, "")
}

// `running: true` says that a copy runs: the look asks the person before the install (src/md/README.md, "A program that
// runs"). Only open_read sets `quits`, from the installed copy's own --status.
@(test)
a_copy_that_runs_is_read_from_status :: proc(t: ^testing.T) {
	runs := status_parse(0, "Papier: installed (another copy)\n  program: /p/papier\n  version: 0.23.2\n  running: true\n  quit: yes\n", "0.23.2")
	defer status_destroy(&runs)
	testing.expect(t, runs.running, "running: true")
	testing.expect(t, !runs.quits, "the carried file's quit says nothing of the copy that runs")
	idle := status_parse(0, "Papier: installed (another copy)\n  program: /p/papier\n  version: 0.23.2\n  running: false\n", "0.23.2")
	defer status_destroy(&idle)
	testing.expect(t, !idle.running, "running: false")
}

@(test)
a_program_that_cannot_answer_is_unknown_with_its_words :: proc(t: ^testing.T) {
	s := status_parse(127, "papier: error while loading shared libraries: libwayland-client.so.0\nmore\n", "0.23.2")
	defer status_destroy(&s)
	testing.expect_value(t, s.state, State.Unknown)
	testing.expect_value(t, s.reason, "papier: error while loading shared libraries: libwayland-client.so.0")
	silent := status_parse(139, "", "0.23.2")
	defer status_destroy(&silent)
	testing.expect_value(t, silent.state, State.Unknown)
	testing.expect(t, silent.reason != "", "a program that said nothing still has a reason")
}

@(test)
a_field_is_found_only_by_its_whole_key :: proc(t: ^testing.T) {
	text := "App: installed\n  programs: no\n  program: /a/b\n  version: 1.2.3\n"
	testing.expect_value(t, status_field(text, "program"), "/a/b")
	testing.expect_value(t, status_field(text, "version"), "1.2.3")
	testing.expect_value(t, status_field(text, "running"), "")
}

@(test)
each_state_ticks_and_offers_its_box_as_the_table_says :: proc(t: ^testing.T) {
	// (src/md/README.md, "The states of a program in atelier")
	ticked := [State]bool{.Reading = false, .Absent = true, .Older = true, .Current = false, .Newer = false, .Repair = true, .Unknown = false}
	choosable := [State]bool{.Reading = false, .Absent = true, .Older = true, .Current = true, .Newer = false, .Repair = true, .Unknown = false}
	for s in State {
		testing.expectf(t, state_ticked(s) == ticked[s], "%v ticked", s)
		testing.expectf(t, state_choosable(s) == choosable[s], "%v choosable", s)
	}
}
