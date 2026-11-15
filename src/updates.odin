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
import "core:time"
import http "gt:http"
import i18n "gt:i18n"
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
// badge cannot (update.notice), and the answer to a check asked, in the suite's words.
updates_follow :: proc(app: ^App) {
	if app.updater == nil { return }
	st := update.status(app.updater)
	if st.serial == app.update_serial { return }
	app.update_serial = st.serial
	app.update_phase = st.phase
	app.main.settle = max(app.main.settle, FRAMES_AFTER_INPUT)   // (the badge and the settings show the state)
	if words, bad := suite_notice(st); words != "" { ui.announce(&app.announcer, bad ? .Bad : .Good, words) }
	// (a newer atelier on offer, or in place: what its bundle carries, for the banner and the rows)
	#partial switch st.phase {
	case .Available, .Downloading, .Installed:
		if st.version != app.suite_version { suite_read(app, st.version) }
	}
	// ("Update atelier and the programs": the new copy goes on, on the Programs step)
	if st.phase == .Installed && app.suite_asked {
		app.suite_asked = false
		app_restart(app, after_update = true)
	}
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
// or Restart asked. `after_update`: the new copy opens on the Programs step (the suite's update goes on there).
app_restart :: proc(app: ^App, after_update := false) {
	delete(app.launch_after)
	app.launch_after = strings.clone(process.executable_path())
	app.launch_after_update = after_update
	platform.request_close(app.main.win)
}

// "Check for updates" (the Programs step's button, the palette): its answer said whatever it is.
update_check_asked :: proc(app: ^App) {
	if app.updater != nil { update.check_now(app.updater) }
}

// What a toast says of the updater's news: a check asked says "Everything is up to date" or why it could not be made
// (offline); the rest is update.notice's.
suite_notice :: proc(st: update.Status) -> (words: string, bad: bool) {
	if st.asked && !st.install && st.phase == .Idle {
		if st.failed { return fmt.tprintf(i18n.tr("The updates cannot be checked: %s."), st.result), true }
		return i18n.tr("Everything is up to date."), false
	}
	return update.notice(st)
}

// "Update atelier and the programs" (src/md/README.md, "The suite's updates, from atelier"): the updater downloads and
// checks the new atelier and puts it in place, then the new copy starts with --after-update (updates_follow). When it is
// in place already, the new copy starts at once.
suite_update :: proc(app: ^App) {
	if app.updater == nil { return }
	#partial switch app.update_phase {
	case .Installed: app_restart(app, after_update = true)
	case .Available:
		app.suite_asked = true
		update.install_now(app.updater)
	}
}

// Whether "Update atelier and the programs" can act now.
suite_update_possible :: proc(app: ^App) -> bool {
	return app.updater != nil && app.suite_version != "" && (app.update_phase == .Available || app.update_phase == .Installed)
}

// Reads, on a worker, the manifest published beside the newer atelier's release: what its bundle carries. It is not
// signed: it decides only what the window shows. When it cannot be read, the banner names atelier's version alone.
@(private = "file")
suite_read :: proc(app: ^App, version: string) {
	delete(app.suite_version)
	app.suite_version = strings.clone(version)
	newer_destroy(app.suite_newer)
	app.suite_newer = nil
	Suite_Job :: struct { url, version, agent: string, carried: []Program, newer: []Newer_Program }
	j := new(Suite_Job)
	folder, _ := prefs_page.update_source(&app.prefs)
	if folder == "" { folder = UPDATE_FOLDER }
	if !strings.has_suffix(folder, "/") { folder = strings.concatenate({folder, "/"}, context.temp_allocator) }
	j.url = strings.concatenate({folder, suite_manifest_name(version, update.PLATFORM)})
	j.version = strings.clone(version)
	j.agent = fmt.aprintf("atelier/%s", APP_VERSION)
	// (the App's, read only: the bundle's strings live as long as the App, which waits for its tasks)
	j.carried = app.programs
	lost :: proc(data: rawptr) {
		j := (^Suite_Job)(data)
		delete(j.url); delete(j.version); delete(j.agent)
		newer_destroy(j.newer)
		free(j)
	}
	ui.task(&app.main.state, proc(data: rawptr) {
		j := (^Suite_Job)(data)
		status, body, err := http.get(j.url, {max_bytes = SMALL_FILE_LIMIT, user_agent = j.agent, timeout = SUITE_READ_TIMEOUT}, context.temp_allocator)
		if err != .None || status != 200 {
			log.warnf("%s cannot be read (%v, %d): the banner names atelier alone", j.url, err, status)
			return
		}
		ok: bool
		j.newer, ok = suite_newer_of(j.carried, body)
		if !ok { log.warnf("%s does not read as a manifest", j.url) }
	}, proc(data: rawptr, _: u64) {
		j := (^Suite_Job)(data)
		defer lost(j)
		app := the_app
		// (an answer for a version no longer on offer is dropped)
		if app == nil || app.closing || j.version != app.suite_version { return }
		newer_destroy(app.suite_newer)
		app.suite_newer, j.newer = j.newer, nil
	}, j, lost)
}

// How long the read of the published manifest may take.
SUITE_READ_TIMEOUT :: 30 * time.Second
