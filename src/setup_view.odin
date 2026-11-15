package atelier

// atelier installs itself, as every program of the suite (gui_toolkit's setup, through prefs_page.Install): the program in
// %LOCALAPPDATA%\Programs\atelier (~/.local/share/atelier on Linux), its menu entry, its record (Settings > Apps, whose
// Uninstall runs `atelier --setup`), and on the PATH when the person ticks it. The person opens it again from the menu to
// add a program later. No start offers it in a dialog: atelier's own row of the Programs step installs it (own.odin).
// The settings' Installation page shows the install and acts on it.
//
// The install copies the running file: the program and its bundle after it. The installed copy carries the programs.
//
//   atelier --setup        the window, the install's dialog open
//   atelier --install      this copy installed, without a window
//   atelier --uninstall    the install taken away (the settings stay)
//   atelier --status       what is installed, and whether atelier runs

import "core:os"
import desktop "gt:desktop"
import i18n "gt:i18n"
import "gt:platform"
import prefs_page "gt:prefs_page"
import setup "gt:setup"

ICON_PNGS := [?]desktop.Icon{
	{16, #load("../assets/logo_16.png")},
	{32, #load("../assets/logo_32.png")},
	{64, #load("../assets/logo_64.png")},
	{128, #load("../assets/logo_128.png")},
	{256, #load("../assets/logo_256.png")},
}

// atelier to the desktop. No NixOS libraries: the toolkit would patch the installed file with patchelf, and the bundle
// after the program must stay as it was written.
atelier_identity :: proc() -> desktop.Identity {
	return desktop.Identity{
		name = "atelier", key = "Atelier", slug = APP_NAME,
		description = "The working man's tools: Froment Software's desktop programs, installed at once.",
		vendor = "Froment Software",
		entry_marker = "X-Atelier-Integration", registry_mark = "AtelierIntegration", vendor_key = "FromentSoftware",
		manifest_name = "atelier_install.txt",
		generic_name = "Software Installer", categories = "System;PackageManager;Utility;", keywords = "install;programs;suite;froment;",
		env_prefix = "ATELIER_DESKTOP_",
		uninstall_arguments = "--setup",   // (Settings > Apps: the install's dialog, its Uninstall)
	}
}

// What the setup knows of atelier.
setup_options :: proc() -> setup.Setup_Options {
	return setup.Setup_Options{
		identity = atelier_identity(), version = APP_VERSION, install_folder = APP_NAME, icons = ICON_PNGS[:],
		choices = SETUP_CHOICES[:], running = app_running, quit = app_quit_ask,
		prepare = proc(o: ^desktop.Integration_Options, choices: []bool, user: rawptr) {
			if len(choices) == len(SETUP_CHOICES) { o.add_to_path = choices[0] }
			// (a test's places come from the environment: its install never reaches the person's desktop)
			desktop.roots_from_env(o, proc(name: string) -> string { return os.get_env(name, context.temp_allocator) })
		},
	}
}

// The boxes of the dialog, in the order prepare reads them (their labels in English: the dialog translates them).
@(private = "file")
SETUP_CHOICES := [?]setup.Choice{
	{label = i18n.later("atelier in the terminal (on the PATH)"), on = false, parts = {.Path}},
}

// Once the start's reading of the install came (prefs_page.install_offer): whether this is the installed copy, which
// updates itself (update.auto).
@(private = "file")
setup_follow :: proc(app: ^App) {
	if app.setup_known || !app.install.known { return }
	app.setup_known = true
	app.installed_copy = app.install.running_it
	updates_auto(app)
}

// The install's machinery at each build: the work that ended, the dialog's answer. Opening the installed copy ends this
// one (app_run starts it once the instance is let go).
setup_build :: proc(app: ^App) {
	setup_follow(app)
	if prefs_page.install_frame(&app.install) == .Launched { platform.request_close(app.main.win) }
}
