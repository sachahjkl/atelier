package atelier

// The preferences: one registry (gt:config). The user's file is <config>/FromentSoftware/Atelier/prefs (`atelier set <name> <value>`
// writes it); `--pref name=value` overrides it for one run. The look, the text, the window, the scrolling, the input, the
// delays, the rendering, the updates and the language are the toolkit's standard settings (prefs_page.standard_register,
// gui_toolkit docs/settings.md), as in every program of the suite; atelier adds its own after them.

import "core:strings"
import config "gt:config"
import i18n "gt:i18n"
import "gt:platform"
import prefs_page "gt:prefs_page"
import "gt:ui"

// The preference of the boxes ticked when a state is read (row_status).
TICKED_PREF :: "programs.ticked"

// atelier's identity in the standard settings: its theme and its name; the rest is the toolkit's.
@(private = "file")
standard_defaults :: proc() -> prefs_page.Standard_Defaults {
	d := prefs_page.STANDARD_DEFAULTS
	d.theme, d.app_name = THEME_ATELIER.name, APP_TITLE
	return d
}

// atelier's own preferences. Their words are registered in English, before the language is known: the settings page
// translates them where it shows them (i18n.later marks them for the catalogue).
PREF_DEFS := [?]config.Def{
	{name = TICKED_PREF, title = i18n.later("Ticked at first"), description = i18n.later("Tick the programs that are not installed, older or to repair as soon as their state is read. Off: every box starts empty."), kind = .Bool, default = {b = true}, tags = {"select", "check", "boxes", "default"}},
}

// The values the program reads, copied out of the registry (prefs_read).
Settings :: struct {
	look:         prefs_page.Appearance,   // appearance.theme, mode, finish, glow, font_size
	system_title: bool,                    // window.system_title
	update_auto:  bool,
	messages:     ui.Announce_Mode,        // general.messages: where the update's notices are said
	ticked:       bool,                    // programs.ticked
}

prefs_file :: proc(allocator := context.temp_allocator) -> string {
	return strings.concatenate({platform.user_dir(.Config, APP_FOLDER, context.temp_allocator), "/prefs"}, allocator)
}

// The user's own themes, beside the preferences (prefs_page.Themes_File).
themes_file :: proc(allocator := context.temp_allocator) -> string {
	return strings.concatenate({platform.user_dir(.Config, APP_FOLDER, context.temp_allocator), "/themes.txt"}, allocator)
}

// Where the palette remembers what the user chose: the user's state folder, "palette_choices.txt".
palette_choices_path :: proc(allocator := context.temp_allocator) -> string {
	return strings.concatenate({platform.user_dir(.State, APP_FOLDER, context.temp_allocator), "/palette_choices.txt"}, allocator)
}

// Where the views remember how the user shows each dialog: the user's state folder, "views.txt".
views_path :: proc(allocator := context.temp_allocator) -> string {
	return strings.concatenate({platform.user_dir(.State, APP_FOLDER, context.temp_allocator), "/views.txt"}, allocator)
}

// The registry with the user's file and `args`' --pref read in. Returns the arguments that are not preferences.
// `descriptions`: where the standard preferences make their descriptions, which the registry keeps.
prefs_open :: proc(p: ^config.Prefs, args: []string, descriptions := context.allocator) -> (rest: [dynamic]string, problems: [dynamic]string) {
	p^ = config.prefs_make()
	prefs_page.standard_register(p, prefs_page.STANDARD_ALL, standard_defaults(), descriptions)
	config.register(p, PREF_DEFS[:])
	_, file_problems := config.load_file(p, prefs_file(), .User)
	rest, problems = config.apply_args(p, args, context.temp_allocator)
	append(&problems, ..file_problems[:])
	return
}

prefs_read :: proc(p: ^config.Prefs, allocator := context.allocator) -> (s: Settings) {
	s.look = prefs_page.appearance_read(p, allocator)
	s.system_title = config.bool_of(p, prefs_page.SYSTEM_TITLE_PREF)
	s.update_auto = config.bool_of(p, prefs_page.UPDATE_AUTO_PREF)
	s.messages = prefs_page.announce_mode(p)
	s.ticked = config.bool_of(p, TICKED_PREF)
	return
}

settings_free :: proc(s: ^Settings) {
	prefs_page.appearance_destroy(&s.look)
	s^ = {}
}
