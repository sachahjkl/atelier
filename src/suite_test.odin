package atelier

import "core:strings"
import "core:testing"

// What a newer atelier carries against this copy: a newer version, a program this copy lacks; never the same version,
// an older one, or one that does not read as a version. atelier's own row is no carried program.
@(test)
a_newer_suite_names_what_is_newer :: proc(t: ^testing.T) {
	carried := []Program{
		own_program(),
		{slug = "papier", name = "Papier", version = "0.24.0"},
		{slug = "classeur", name = "Classeur", version = "0.23.0"},
		{slug = "cliche", name = "cliche", version = "0.7.1"},
		{slug = "inspecteur", name = "Inspecteur", version = "0.8.0"},
	}
	published := []Program{
		{slug = "papier", name = "Papier", version = "0.25.0"},
		{slug = "classeur", name = "Classeur", version = "0.23.0"},
		{slug = "cliche", name = "cliche", version = "0.7.0"},
		{slug = "inspecteur", name = "Inspecteur", version = "next"},
		{slug = "wren", name = "Wren", version = "1.0.0"},
	}
	newer := suite_newer(carried, published)
	defer newer_destroy(newer)
	testing.expect_value(t, len(newer), 2)
	testing.expect_value(t, suite_available(newer, "papier"), "0.25.0")
	testing.expect_value(t, suite_available(newer, "wren"), "1.0.0")
	testing.expect_value(t, suite_available(newer, "classeur"), "")
	testing.expect_value(t, suite_available(newer, "cliche"), "")
	testing.expect_value(t, suite_available(newer, "inspecteur"), "")
}

@(test)
the_banner_names_the_newer_programs :: proc(t: ^testing.T) {
	none := suite_banner("0.4.0", nil)
	testing.expect_value(t, none, "A newer suite is available (atelier 0.4.0).")
	one := []Newer_Program{{"papier", "Papier", "0.25.0"}}
	testing.expect_value(t, suite_banner("0.4.0", one), "A newer suite is available (atelier 0.4.0): Papier 0.25.0 is newer than what this copy carries.")
	two := []Newer_Program{{"papier", "Papier", "0.25.0"}, {"cliche", "cliche", "0.9.0"}}
	banner := suite_banner("0.4.0", two)
	testing.expectf(t, strings.contains(banner, ": Papier 0.25.0, cliche 0.9.0 are newer"), "%s", banner)
}

// The published manifest is read as a bundle's: a manifest atelier cannot read names nothing.
@(test)
a_published_manifest_is_read :: proc(t: ^testing.T) {
	carried := []Program{{slug = "papier", name = "Papier", version = "0.24.0"}}
	manifest := `{"schema": 1, "platform": "linux-x64", "made": "2026-11-20", "programs": [{"slug": "papier", "name": "Papier",
		"version": "0.25.0", "file": "papier/papier", "size": 1, "sha256": "0000000000000000000000000000000000000000000000000000000000000000"}]}`
	newer, ok := suite_newer_of(carried, transmute([]u8)string(manifest))
	defer newer_destroy(newer)
	testing.expect(t, ok, "it reads")
	testing.expect_value(t, suite_available(newer, "papier"), "0.25.0")
	_, bad := suite_newer_of(carried, transmute([]u8)string("not json"))
	testing.expect(t, !bad, "not a manifest")
	testing.expect_value(t, suite_manifest_name("0.4.0", "linux-x64"), "atelier-0.4.0-linux-x64.json")
}
