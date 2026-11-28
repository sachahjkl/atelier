package atelier

// What the person can do in the window, named once: each action's label, group, keys and icon (gui_toolkit's commands).
// The same table gives the keys, the tooltips, the toolkit's command palette (Ctrl+K, its own command) and the sheet of
// the keys (F1). After the actions, the palette lists "Open <program>" for each program installed in this run, and the
// settings (`:`).

import "core:fmt"
import "core:slice"
import "core:strings"
import i18n "gt:i18n"
import lucide "gt:lucide"
import "gt:platform"
import prefs_page "gt:prefs_page"
import "gt:ui"
import update "gt:update"

Action :: enum u8 {
	// (in the palette's order: each group's actions together)
	Next, Back, Accept_Install, Retry_Failed, Select_All, Select_None,
	Settings, Check_Updates, Update_Suite, Install_Atelier, Shortcuts, Quit,
}

ACTIONS := [Action]ui.Command{
	.Next           = {id = "next", label = i18n.later("Next step"), group = i18n.later("Steps"), keys = {{.Right, {.Alt}}}, icon = lucide.ARROW_RIGHT, tags = {"continue", "forward", "choose"}},
	.Back           = {id = "back", label = i18n.later("Previous step"), group = i18n.later("Steps"), keys = {{.Left, {.Alt}}}, icon = lucide.ARROW_LEFT, tags = {"return", "previous"}},
	.Select_All     = {id = "select_all", label = i18n.later("Select every program"), group = i18n.later("Programs"), keys = {{.A, {.Ctrl}}}, icon = lucide.LIST_CHECKS, tags = {"tick", "check", "all"}},
	.Select_None    = {id = "select_none", label = i18n.later("Select no program"), group = i18n.later("Programs"), icon = lucide.SQUARE, tags = {"untick", "clear", "none"}},
	.Accept_Install = {id = "accept_install", label = i18n.later("Accept the licences and install"), group = i18n.later("Steps"), icon = lucide.DOWNLOAD, tags = {"install", "licence", "agree"}},
	.Retry_Failed   = {id = "retry_failed", label = i18n.later("Retry the failed installs"), group = i18n.later("Steps"), icon = lucide.ROTATE_CCW, tags = {"again", "failed", "install"}},
	.Settings       = {id = "settings", label = i18n.later("Settings"), group = i18n.later("Atelier"), keys = {{.Comma, {.Ctrl}}}, icon = lucide.SETTINGS, tags = {"preferences", "options", "configure"}, scope = .Window},
	.Check_Updates  = {id = "check_updates", label = i18n.later("Check for updates"), group = i18n.later("Atelier"), icon = lucide.REFRESH_CW, tags = {"upgrade", "version", "new"}},
	.Update_Suite   = {id = "update_suite", label = i18n.later("Update Atelier and the programs"), group = i18n.later("Atelier"), icon = lucide.DOWNLOAD, tags = {"upgrade", "suite", "newer"}},
	.Install_Atelier = {id = "install_atelier", label = i18n.later("Install Atelier…"), group = i18n.later("Atelier"), icon = lucide.PACKAGE_PLUS, tags = {"setup", "uninstall", "menu", "path"}},
	.Shortcuts      = {id = "shortcuts", label = i18n.later("Keyboard shortcuts"), group = i18n.later("Atelier"), keys = {{.F1, {}}}, icon = lucide.KEYBOARD, tags = {"help", "keys", "hotkeys"}, scope = .Window},
	.Quit           = {id = "quit", label = i18n.later("Quit Atelier"), group = i18n.later("Atelier"), keys = {{.Q, {.Ctrl}}}, icon = lucide.POWER, tags = {"exit", "close", "stop"}, scope = .Window},
}

// The id of a program's "Open" line: its slug, which the bundle keeps from one version to the next (lower case: an id
// has no capital).
open_command_id :: proc(slug: string, allocator := context.allocator) -> string {
	return strings.concatenate({"open.", strings.to_lower(slug, context.temp_allocator)}, allocator)
}

// Whether `a` can act now: what the step's buttons offer.
action_enabled :: proc(app: ^App, a: Action) -> bool {
	has := app.bundle != nil
	switch a {
	case .Next:
		#partial switch app.step {
		case .Welcome:  return has && len(app.rows) > 0
		case .Programs: return has && chosen_count(app) > 0 && !uninstall_busy(app)
		}
		return false
	case .Back:                     return has && (app.step == .Programs || app.step == .Licences)
	case .Select_All, .Select_None: return has && app.step == .Programs && app.known
	case .Accept_Install:           return has && app.step == .Licences && licences_ready(app) && chosen_count(app) > 0
	case .Retry_Failed:             return has && retry_possible(app)
	case .Check_Updates:            return app.updates.updater != nil
	case .Update_Suite:             return suite_update_possible(app)
	case .Install_Atelier:          return !app.demo
	case .Settings, .Shortcuts, .Quit: return true
	}
	return false
}

action_run :: proc(app: ^App, a: Action) {
	if !action_enabled(app, a) { return }
	switch a {
	case .Next, .Accept_Install: app_step(app, .Next)
	case .Back:                  app_step(app, .Back)
	case .Retry_Failed:          retry_failed(app)
	case .Select_All:            select_all(app, true)
	case .Select_None:           select_all(app, false)
	case .Settings:              settings_toggle(app)
	case .Check_Updates:         update_check_asked(app)
	case .Update_Suite:          suite_update(app)
	case .Install_Atelier:       prefs_page.install_open(&app.install)
	// (the sheet adds the toolkit's palette command itself)
	case .Shortcuts:             ui.shortcuts_sheet_open(&app.sheet, slice.enumerated_array(&ACTIONS), i18n.tr("Atelier's keys"))
	case .Quit:                  platform.request_close(app.main.win)
	}
}

// The keys of the window's actions (scope .Window): in every page, before anything else reads a key. The palette's
// first: its keys are the toolkit's, read by its own reader.
window_keys :: proc(app: ^App) {
	if palette_keys(app) { return }
	for a in Action {
		if ACTIONS[a].scope != .Window { continue }
		if ui.command_pressed(ACTIONS[a], !action_enabled(app, a)) { action_run(app, a); return }
	}
}

// The keys of the steps' actions, when the settings and the dialogs do not have the keyboard.
actions_keys :: proc(app: ^App) {
	for a in Action {
		if ACTIONS[a].scope == .Window { continue }
		if ui.command_pressed(ACTIONS[a], !action_enabled(app, a)) { action_run(app, a); return }
	}
	open_keys(app)
}

// What atelier gives the palette: the actions, then one "Open <program>" per program of the bundle (shown once it is
// installed), and which of them cannot act. The table is made again when the language changes (its labels are made
// with the words of a language); `disabled` when what it reads changes. The palette's commands source compares the
// version, never the table.
Palette_State :: struct {
	table:    [dynamic]ui.Command,   // the actions, then the programs' (their labels owned)
	disabled: [dynamic]bool,
	made:     bool,                  // the table is made (palette_table_make)
	language: u32,                   // i18n.version() of the table
	version:  u64,
	made_for: Can_Act_Key,
	settings: prefs_page.Palette_Settings,
}

// What action_enabled and the programs' lines read: a change of one reads `disabled` again.
@(private = "file")
Can_Act_Key :: struct {
	made:     bool,
	step:     Step,
	known:    bool,
	chosen:   int,
	ready:    bool,
	updater:  bool,
	results:  u64,   // the rows installed, one bit each
	failed:   u64,   // the rows failed, one bit each (Retry)
	look:     Look,
	phase:    update.Phase,
	suite:    bool,  // a newer suite is on offer
}

@(private = "file")
can_act_key :: proc(app: ^App) -> (k: Can_Act_Key) {
	k = {made = true, step = app.step, known = app.known, chosen = chosen_count(app), ready = licences_ready(app), updater = app.updates.updater != nil,
		look = app.look, phase = app.update_phase, suite = app.suite_version != ""}
	for r, i in app.rows {
		if i >= 64 { break }
		if program_openable(app, i) { k.results |= 1 << u64(i) }
		if r.result == .Failed { k.failed |= 1 << u64(i) }
	}
	return
}

// Whether a row's program can be started from the palette: installed in this run, its path known. Never atelier's
// own: it is open.
@(private = "file")
program_openable :: proc(app: ^App, row: int) -> bool {
	r := app.rows[row]
	return r.result == .Installed && r.status.program != "" && !(row < len(app.programs) && app.programs[row].own)
}

// The usage memory and the settings source, once the window, the updater and the install are made.
palette_init :: proc(app: ^App) {
	ui.palette_memory_open(&app.palette, &app.main.state, palette_choices_path())
	open :: proc(user: rawptr) { (^App)(user).settings_open = true }
	options :: proc(user: rawptr) -> prefs_page.Page_Options { return settings_options((^App)(user)) }
	prefs_page.palette_settings_add(&app.palette, &app.palette_state.settings, &app.prefs, &app.settings_page, options, open, app)
}

palette_destroy :: proc(app: ^App) {
	ps := &app.palette_state
	ui.palette_destroy(&app.palette)
	palette_table_free(ps)
	delete(ps.table)
	delete(ps.disabled)
}

// The search words of a program's "Open" line.
@(private = "file", rodata)
OPEN_TAGS := [?]string{"start", "run", "launch"}

@(private = "file")
palette_table_free :: proc(ps: ^Palette_State) {
	for c, i in ps.table {
		if i >= len(Action) {
			delete(c.label)
			delete(c.id)
		}
	}
	clear(&ps.table)
}

// The table, made again when the language changes. True when it was made now.
@(private = "file")
palette_table_make :: proc(app: ^App) -> (fresh: bool) {
	ps := &app.palette_state
	// (the keys of its "Open" lines are read at each frame: the table is made once per language, never at a frame)
	if ps.made && ps.language == i18n.version() { return false }
	palette_table_free(ps)
	for a in Action { append(&ps.table, ACTIONS[a]) }
	// (one line per row, atelier's own too, so that a line's index is its row's: atelier's is never enabled)
	for p in app.programs {
		// (the program's name is no word to translate: the label is made in the language in use)
		append(&ps.table, ui.Command{id = open_command_id(p.slug), label = fmt.aprintf(i18n.tr("Open %s"), p.name), group = i18n.later("Programs"), icon = lucide.PLAY, tags = OPEN_TAGS[:]})
	}
	// (a table made at run time: its ids known again, before a key of it is read)
	ui.keymap_known(&app.keymap, ps.table[:])
	resize(&ps.disabled, len(ps.table))
	ps.language, ps.made = i18n.version(), true
	return true
}

// The keys a person gave a program's "Open" line (it has none of its own): read with the steps' actions.
@(private = "file")
open_keys :: proc(app: ^App) {
	palette_table_make(app)
	ps := &app.palette_state
	for i in len(Action) ..< len(ps.table) {
		row := i - len(Action)
		if row >= len(app.rows) { break }
		if ui.command_pressed(ps.table[i], !program_openable(app, row)) { open_program(app, app.rows[row].status.program); return }
	}
}

// The table and what can act, given to the commands source.
@(private = "file")
palette_give :: proc(app: ^App) {
	ps := &app.palette_state
	fresh := palette_table_make(app)
	if key := can_act_key(app); fresh || key != ps.made_for {
		for a in Action { ps.disabled[int(a)] = !action_enabled(app, a) }
		for _, i in app.rows { ps.disabled[len(Action) + i] = !program_openable(app, i) }
		ps.made_for = key
		ps.version += 1
	}
	ui.palette_commands(&app.palette, ps.table[:], ps.disabled[:], {version = ps.version})
}

// Ctrl+K and Ctrl+Shift+P (the toolkit's command, read by its own reader): the palette opens or closes. True when they
// were pressed.
@(private = "file")
palette_keys :: proc(app: ^App) -> bool {
	if !ui.palette_keys(&app.palette) { return false }
	palette_give(app)
	return true
}

// Opens the palette (the title bar's button).
palette_show :: proc(app: ^App) {
	palette_give(app)
	ui.palette_toggle(&app.palette)
}

// The palette's choice (the toolkit's sources act in it), and what can act kept while it is open: at each build.
actions_build :: proc(app: ^App) {
	if c, ok := ui.palette_chosen(&app.palette); ok {
		if i, is := ui.palette_chosen_command(&app.palette, c); is && i >= 0 {
			if i < len(Action) {
				action_run(app, Action(i))
			} else if row := i - len(Action); row < len(app.rows) && program_openable(app, row) {
				open_program(app, app.rows[row].status.program)
			}
		}
	}
	if ui.palette_is_open(&app.palette) { palette_give(app) }
}

// A tooltip: the action's label and its key.
action_tip :: proc(a: Action) -> string { return ui.command_tip(ACTIONS[a]) }
