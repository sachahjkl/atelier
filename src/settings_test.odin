package atelier

import "core:strings"
import "core:testing"

// Every preference of atelier's own has its line in docs/configuration.md: a setting nobody can read about does not
// exist for the person.
@(test)
every_preference_is_documented :: proc(t: ^testing.T) {
	doc := string(#load("../docs/configuration.md"))
	for d in PREF_DEFS {
		testing.expectf(t, strings.contains(doc, strings.concatenate({"| `", d.name, "` |"}, context.temp_allocator)), "%s is in docs/configuration.md", d.name)
	}
}

// programs.ticked off leaves every box empty, whatever the state; on, the box follows the state.
@(test)
the_boxes_follow_programs_ticked :: proc(t: ^testing.T) {
	r: Row
	row_status(&r, {state = .Absent}, tick = true, ticked = false)
	testing.expect(t, !r.ticked, "off: an absent program is not ticked")
	row_status(&r, {state = .Absent}, tick = true, ticked = true)
	testing.expect(t, r.ticked, "on: an absent program is ticked")
	row_destroy(&r)
}
