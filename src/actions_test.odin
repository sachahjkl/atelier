package atelier

import "core:slice"
import "core:testing"
import config "gt:config"
import prefs_page "gt:prefs_page"
import "gt:ui"

// No action's key types text: a key that types would never reach a field of the settings (gui_toolkit's
// src/md/features/commands.md).
@(test)
no_action_key_types_text :: proc(t: ^testing.T) {
	got := ui.command_typing_keys(slice.enumerated_array(&ACTIONS))
	testing.expectf(t, len(got) == 0, "keys that type text: %v", got)
}

// Each command's id is its name for good: the person's key and alias of it, and the palette's memory of it, are stored
// by it. Every one is set, well formed and alone in its table: the actions, then the programs' "Open" lines, whose ids
// come from the bundle's slugs (a capital in a slug included).
@(test)
every_command_has_an_id :: proc(t: ^testing.T) {
	table := make([dynamic]ui.Command, context.temp_allocator)
	append(&table, ..slice.enumerated_array(&ACTIONS))
	for slug in ([]string{APP_NAME, "papier", "Classeur", "opencode-native", "wren_2"}) {
		append(&table, ui.Command{id = open_command_id(slug, context.temp_allocator), label = slug})
	}
	got := ui.command_ids_check(slice.enumerated_array(&ACTIONS), table[:])
	testing.expectf(t, len(got) == 0, "ids: %v", got)
}

// The settings, the keys and quit are the window's: their keys work in the settings and over a dialog.
@(test)
the_window_actions_are_marked :: proc(t: ^testing.T) {
	for a in ([]Action{.Settings, .Shortcuts, .Quit}) {
		testing.expectf(t, ACTIONS[a].scope == .Window, "%v is the window's", a)
	}
	testing.expect_value(t, ACTIONS[.Next].scope, ui.Command_Scope.Page)
}

// The palette's keys are the toolkit's command (Ctrl+K, Ctrl+Shift+P), read by its own reader: no action of atelier's
// takes them, or the key would run twice.
@(test)
no_action_takes_the_palette_keys :: proc(t: ^testing.T) {
	for chord in ui.palette_command().keys {
		for a in Action {
			for k in ACTIONS[a].keys { testing.expectf(t, k != chord, "%v takes the palette's key %v", a, chord) }
		}
	}
}

// The prefixes atelier fills: its commands (and the views' moves) and its settings.
@(test)
the_palette_prefixes :: proc(t: ^testing.T) {
	p: ui.Command_Palette
	defer ui.palette_destroy(&p)
	prefs := config.prefs_make()
	defer config.prefs_destroy(&prefs)
	page: prefs_page.Page
	settings: prefs_page.Palette_Settings
	ui.palette_commands(&p, slice.enumerated_array(&ACTIONS), nil)
	options :: proc(user: rawptr) -> prefs_page.Page_Options { return {} }
	prefs_page.palette_settings_add(&p, &settings, &prefs, &page, options, nil)
	testing.expect(t, slice.equal(ui.palette_prefixes(&p), []string{"> Commands", ": Settings"}), "the prefixes")
}

// The steps' actions follow the step: Back only where the buttons offer it, the boxes only on Programs.
@(test)
the_actions_follow_the_step :: proc(t: ^testing.T) {
	b := Bundle{programs = make([]Program, 1, context.temp_allocator)}
	app := App{bundle = &b, rows = make([]Row, 1, context.temp_allocator), known = true}
	app.step = .Welcome
	testing.expect(t, action_enabled(&app, .Next), "Welcome: Next")
	testing.expect(t, !action_enabled(&app, .Back), "Welcome: no Back")
	testing.expect(t, !action_enabled(&app, .Select_All), "Welcome: no boxes")
	app.step = .Programs
	testing.expect(t, !action_enabled(&app, .Next), "Programs: Next waits for a box")
	app.rows[0].ticked = true
	testing.expect(t, action_enabled(&app, .Next), "Programs: a box ticked, Next")
	testing.expect(t, action_enabled(&app, .Back), "Programs: Back")
	app.step = .Checking
	testing.expect(t, !action_enabled(&app, .Back) && !action_enabled(&app, .Accept_Install), "Checking: the look decides")
	app.step = .Installing
	testing.expect(t, !action_enabled(&app, .Back), "Installing: no Back")
	testing.expect(t, !action_enabled(&app, .Retry_Failed), "Installing: nothing failed, no Retry")
	app.stage = .Finished
	app.rows[0].result = .Failed
	testing.expect(t, action_enabled(&app, .Retry_Failed), "Installing, finished: a row failed, Retry")
	app.look = .Asking
	testing.expect(t, !action_enabled(&app, .Retry_Failed), "one look at a time")
}
