package atelier

// Updates: gui_toolkit's Updater (gt:update) checks atelier's latest release a while after the start and then every day,
// downloads the file it names, checks it against its signed manifest (src/update: atelier's product and key) and puts it
// in place of this one; the new atelier runs at the next start (the badge's or the settings' Restart now). The file is
// the release's whole file: the program and the bundle of every program after it, so an update brings the programs'
// new versions too. Only the installed copy does it by itself (update.auto): a build, or a copy run where it was
// downloaded, is updated when the settings' Check now asks. A copy from the Nix store is left to Nix.

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:strings"
import "gt:platform"
import prefs_page "gt:prefs_page"
import process "gt:process"
import setup "gt:setup"
import "gt:ui"
import update "gt:update"
import atelier_update "update"

// The folder of the latest release's files: its manifests (update-<platform>.json and .sig) and its files.
UPDATE_FOLDER :: "https://github.com/sachahjkl/atelier/releases/latest/download/"

// (whether this is the installed copy comes with the start's reading of the install: setup_follow applies update.auto)
updates_start :: proc(app: ^App) {
	// (update.base_url: read at the start)
	folder, _ := prefs_page.update_source(&app.prefs)
	app.updater = update.updater_start({
		product = atelier_update.PRODUCT, folder = folder != "" ? folder : UPDATE_FOLDER, current = APP_VERSION,
		exe = process.executable_path(), user_agent = fmt.tprintf("atelier/%s", APP_VERSION),
		// (the updater's thread: the loop wakes, and updates_follow reads the state)
		news = proc(user: rawptr) { platform.wake((^App)(user).main.win) }, user = app,
	})
	updates_auto(app)
}

updates_stop :: proc(app: ^App) {
	if app.updater == nil { return }
	update.updater_stop(app.updater)
	app.updater = nil
}

// update.auto, read again when the preferences change.
updates_auto :: proc(app: ^App) {
	if app.updater == nil { return }
	auto := app.settings.update_auto && app.installed_copy
	update.set_auto(app.updater, auto ? .Install : .Off)
}

// At each turn of the loop: what changed is said once. The title bar's badge shows the phase; a toast says only what the
// badge cannot (update.notice).
updates_follow :: proc(app: ^App) {
	if app.updater == nil { return }
	st := update.status(app.updater)
	if st.serial == app.update_serial { return }
	app.update_serial = st.serial
	app.main.settle = max(app.main.settle, FRAMES_AFTER_INPUT)   // (the badge and the settings show the state)
	if words, bad := update.notice(st); words != "" { ui.announce(&app.announcer, bad ? .Bad : .Good, words) }
	// (the installed copy: its manifest and Settings > Apps say the new version; written on a worker)
	if st.phase == .Installed {
		version := new_clone(strings.clone(st.version, runtime.heap_allocator()), runtime.heap_allocator())
		ui.task(&app.main.state, proc(data: rawptr) {
			version := (^string)(data)
			defer { delete(version^, runtime.heap_allocator()); free(version, runtime.heap_allocator()) }
			if ok, why := setup.updated(setup_options(), version^); !ok { log.errorf("the update is in place, but %s", why) }
		}, nil, version)
	}
}

// The program starts again once this one has ended (it holds the single instance until then): an update put in place,
// or Restart asked.
app_restart :: proc(app: ^App) {
	delete(app.launch_after)
	app.launch_after = strings.clone(process.executable_path())
	platform.request_close(app.main.win)
}

// "Check for updates" (the palette): its answer said whatever it is.
update_check_asked :: proc(app: ^App) {
	if app.updater != nil { update.check_now(app.updater) }
}
