package atelier

// The settings: gui_toolkit's page of the preferences (gt:prefs_page), in place of the steps. The gear of the title bar,
// Ctrl+, or the palette opens it; the arrow, Escape or Ctrl+, again goes back. Each change is applied at once: the
// standard settings by prefs_page.standard_watch, atelier's by settings_changed. The preferences' writer saves the file
// off the window's thread (app_run's loop).

import "core:fmt"
import i18n "gt:i18n"
import lucide "gt:lucide"
import "gt:platform"
import prefs_page "gt:prefs_page"
import "gt:ui"

settings_toggle :: proc(app: ^App) {
	app.settings_open = !app.settings_open
	if app.settings_open { prefs_page.focus_search(&app.settings_page) }
}

open_whats_new :: proc(app: ^App) {
	app.settings_open = true
	prefs_page.show(&app.settings_page, &app.prefs, settings_options(app), prefs_page.CHANGELOG_PAGE)
}

// Bundle summary appended to About's "Copy diagnostics".
about_diagnostics :: proc(app: ^App, allocator := context.temp_allocator) -> string {
	if app.bundle == nil { return "Bundle: none" }
	return fmt.aprintf("Bundle: %s, %d programs, made %s", app.bundle.platform, len(app.bundle.programs), app.bundle.made, allocator = allocator)
}

about_build :: proc(app: ^App) {
	ui.about_modal("about", &app.about_open, {
		name         = APP_TITLE,
		version      = APP_VERSION,
		licence      = "MIT",
		copyright    = "© 2026 Froment Software",
		logo         = app.logo,
		on_whats_new = proc(user: rawptr) { open_whats_new((^App)(user)) },
		website_url  = "https://atelier.froment.software/",
		releases_url = "https://atelier.froment.software/changelog/",
		diagnostics  = about_diagnostics(app),
		user         = app,
	})
}

// Escape goes back, unless an editor of a preference has the keyboard (Escape gives it back to the list first).
settings_keys :: proc(app: ^App) {
	if prefs_page.escape_leaves(&app.settings_page) { app.settings_open = false }
}

// The General page shows where atelier says what it did and its language: general.menu and general.autostart are the
// install's, which puts the launcher in place.
@(private = "file", rodata) GENERAL_NAMES := [?]string{prefs_page.MESSAGES_PREF, prefs_page.LANGUAGE_PREF}

// The pages, their order and their icons: each a group of the registry. The titles are English: the page translates
// them where it shows them.
@(private = "file")
SETTINGS_PAGES := [?]prefs_page.Page_Info{
	{category = "general",    title = i18n.later("General"),          icon = lucide.SETTINGS, names = GENERAL_NAMES[:]},
	{category = "appearance", title = i18n.later("Appearance"),       icon = lucide.PALETTE},
	{category = "window",     title = i18n.later("Window"),           icon = lucide.APP_WINDOW},
	{category = "programs",   title = i18n.later("Programs"),         icon = lucide.LIST_CHECKS},
	{category = "scrolling",  title = i18n.later("Scrolling"),        icon = lucide.MOUSE},
	{category = "input",      title = i18n.later("Input"),            icon = lucide.KEYBOARD},
	{category = "timing",     title = i18n.later("Delays and menus"), icon = lucide.TIMER},
	{category = "keys",       title = i18n.later("Keys"),             icon = lucide.KEYBOARD},
	{category = "update",     title = i18n.later("Updates"),          icon = lucide.DOWNLOAD},
	{category = "rendering",  title = i18n.later("Rendering"),        icon = lucide.MONITOR},
}

// What atelier has to say under a line: a title bar the desktop does not draw.
@(private = "file")
settings_problem :: proc(user: rawptr, name: string) -> string {
	app := (^App)(user)
	if name == prefs_page.SYSTEM_TITLE_PREF && app.settings.system_title && !platform.system_title_available(app.main.win) {
		return i18n.tr("This desktop draws no title bar for Atelier's window (GNOME): Atelier keeps its own.")
	}
	return ""
}

// The page, as large as what is left under the title bar.
settings_build :: proc(app: ^App) {
	ui.next({width = ui.fill(), height = ui.fill()})
	prefs_page.build(&app.settings_page, &app.prefs, settings_options(app))
}

// What the page is given: its pages, atelier's themes and the user's, the updater, the install, the file. The palette
// lists the settings by them too.
settings_options :: proc(app: ^App) -> prefs_page.Page_Options {
	return {
		user = app, changed = settings_changed, problem = settings_problem,
		updater = app.updates.updater, restart = proc(user: rawptr) { app_restart((^App)(user)) },
		pages = SETTINGS_PAGES[:], icon_font = ui.lucide_icons(), search_icon = lucide.SEARCH, reset_icon = lucide.ROTATE_CCW,
		file = app.prefs_path,
		version = APP_TITLE + " " + APP_VERSION,
		themes = app.themes_file.all[:], themes_light = app.theme_shown.light, themes_file = &app.themes_file,
		install = &app.install, diagnostics = prefs_page.diagnostics_of(&app.main),
		changelog = &app.changelog,
	}
}

// A preference was set or reset: atelier's settings read again; the standard ones are applied by standard_watch already.
@(private = "file")
settings_changed :: proc(user: rawptr, name: string) {
	app := (^App)(user)
	settings_free(&app.settings)
	app.settings = prefs_read(&app.prefs)
	app.announcer.mode = app.settings.messages
	app_title_follow(app)
}
