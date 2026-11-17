package atelier

// The window and its loop. The loop sleeps in the toolkit's wait until input, a worker's answer (ui.task posts it) or
// the updater's news: at rest, nothing runs. The frame reads and writes nothing: the logos, the licences, the states and
// the installs are workers' (the tasks below), each answer posted back to the window's thread.
//
// What the workers do, in order:
//   1. at the start, one task decodes the logos, reads the licences and whether the system is NixOS (start_work): after
//      it and the states, nothing reads the bundle again (src/md/README.md, "Everything is read from the bundle at the
//      start": an update may put a new file at its path);
//   2. then, unless in the demo, one task per program, all at once: its file taken out and its --status read
//      (status_work), so that a box shows its state as soon as it is known;
//   3. after "Accept and install" (or a retry), one task reads again whether each program chosen runs (look_work); when
//      one runs, the window asks the person before anything starts;
//   4. then one task per program, all at once: its phases (Close, Unpack, Install, Check), each one posted back as it
//      starts (install_work).

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:time"
import "core:slice"
import "core:strings"
import config "gt:config"
import crash_bar "gt:crash_bar"
import devtools "gt:devtools"
import "gt:font"
import host "gt:host"
import lucide "gt:lucide"
import i18n "gt:i18n"
import instance "gt:instance"
import "gt:platform"
import png "gt:png"
import prefs_page "gt:prefs_page"
import "gt:render"
import setup "gt:setup"
import "gt:ui"
import update "gt:update"

// The window's size at its first start, in logical pixels (then the toolkit's window.placement keeps it).
WINDOW_SIZE :: [2]int{820, 640}

// The program's catalogues of the languages it speaks besides English (i18n/<language>.txt, written by the i18n tool).
PROGRAM_CATALOGUES :: []i18n.Catalog{{"fr", #load("../i18n/fr.txt", string)}}

// atelier's own mark: in the title bar, on the welcome and in the install's dialog.
LOGO_PNG :: #load("../assets/logo_128.png")

// The vendor's mark, in the "By" line of the install (gt:setup).
VENDOR_MARK_PNG :: #load("../assets/froment-software-64.png")

App :: struct {
	shared:       host.Shared,
	main:         host.Host,
	bundle:       ^Bundle,         // nil: this copy carries no programs (bundle_error says why)
	bundle_error: Bundle_Error,
	started_ms:   i64,             // the wall clock at atelier's start, in ms since 1970: the "now" of the bundle's age
	programs:     []Program,       // atelier's own first (own_program), then the bundle's in its order; empty without a bundle
	rows:         []Row,           // one per program of `programs`, in its order
	step:         Step,
	stage:        Install_Stage,   // Installing: whether the installs are under way (wizard.odin)
	look:         Look,            // the look for the programs that run, one at a time (wizard.odin)
	batch:        [dynamic]int,    // the rows of the look under way: they start once it ends
	asking:       [dynamic]int,    // the rows of the batch whose copy runs: the question names them
	demo:         bool,            // made-up states, nothing runs (--demo)
	demo_case:    Demo_Case,       // what more the demo shows (--demo-case: the pictures of Retry, of a newer suite)
	known:        bool,            // the start's task answered: the logos and the licences are there, nixos is known
	nixos:        bool,            // Nix is the better install here: its lines are offered above the programs
	logo:         render.Texture,  // atelier's
	logo_size:    [2]f32,
	copied:       int,             // the row whose Nix line was just copied (-1: none): a check until the pointer leaves
	closing:      bool,            // the window closed: what the workers post is freed, not shown
	devtools:     ^devtools.Server,
	theme_shown:  ui.Theme_Shown,
	crash_bar:    crash_bar.Bar,   // the last run's crash, said in a bar at the top of the window

	// the preferences and the settings (settings.odin, settings_view.odin)
	prefs:         config.Prefs,
	prefs_writer:  config.User_Writer,       // the preferences file, written off the window's thread when they change
	prefs_path:    string,                   // the preferences file, at the settings' foot (owned)
	standard:      prefs_page.Standard_Watch,
	themes_file:   prefs_page.Themes_File,   // atelier's theme, the toolkit's, then the user's own (themes.txt)
	settings:      Settings,
	settings_open: bool,                     // the settings in place of the steps
	settings_page: prefs_page.Page,
	announcer:     ui.Announcer,             // where the update's notices are said (general.messages)
	placement:     prefs_page.Placement_Keeper,   // the window's place, the toolkit's window.placement

	// the palette and the dialogs (actions.odin)
	views:         ui.Views,
	palette:       ui.Command_Palette,
	palette_state: Palette_State,
	sheet:         ui.Shortcuts_Sheet,       // F1: the sheet of the keys
	keymap:        ui.Keymap,                // the person's keys and aliases (keys.custom, keys.aliases), set from the palette

	// atelier's own install and updates (setup_view.odin, updates.odin)
	install:        prefs_page.Install,
	updates:        prefs_page.Updates,   // its updater nil in the demo
	update_phase:   update.Phase,         // the updater's phase last said, for the builds (they never ask the updater)
	launch_after:   string,            // this program again after an update, started once this one has ended (owned)
	launch_after_update: bool,         // ... with --after-update: the suite's update goes on in the new copy

	// the suite's updates (updates.odin, suite.odin)
	suite_version: string,             // the newer atelier on offer whose programs were asked ("": none; owned)
	suite_newer:   []Newer_Program,    // what it carries that is newer than this copy (owned)
	suite_asked:   bool,               // "Update atelier and the programs": the new copy starts once it is in place
	after_update:  bool,               // this run is the new copy (--after-update): its line on the Programs step
}

// The App of the process: a worker's answer finds it.
the_app: ^App

// app_run takes the registry: it is the App's from now on (`prefs` is left empty).
app_run :: proc(opts: Run_Options, prefs: ^config.Prefs, setup_asked: bool) -> int {
	app := new(App)
	defer free(app)
	the_app = app
	defer the_app = nil
	app.demo, app.demo_case, app.after_update, app.copied = opts.demo, opts.demo_case, opts.after_update, -1
	// (read once, before the window: no frame reads the clock)
	app.started_ms = time.to_unix_nanoseconds(time.now()) / 1_000_000
	// (host.program_start said it in the log)
	if opts.last_crash != "" { crash_bar.init(&app.crash_bar, opts.last_crash) }
	app.prefs = prefs^
	prefs^ = {}
	app.settings = prefs_read(&app.prefs)
	prefs_page.install_init(&app.install, &app.prefs, setup_options())
	// (general.language is in the registry, and nothing is shown yet: every text from here on is in its language)
	prefs_page.language_start(&app.prefs, PROGRAM_CATALOGUES)
	// (the demo writes nothing: its pictures come from a run that leaves no trace)
	if !app.demo { config.user_writer_start(&app.prefs_writer, &app.prefs, prefs_file()) }
	// (the demo names no file at the settings' foot: it writes none, and its pictures show no folder of this computer)
	if !app.demo { app.prefs_path = prefs_file(context.allocator) }
	// (no file read here: the user's themes come at the first builds, read by a task)
	prefs_page.themes_file_init(&app.themes_file, themes_file(), themes())
	// (a start-up read, before the window: the end of the file, then the manifest; no frame waits for it)
	app.bundle, app.bundle_error = bundle_open(opts.bundle)
	if app.bundle != nil {
		app.programs = make([]Program, len(app.bundle.programs) + 1)
		app.programs[0] = own_program()
		copy(app.programs[1:], app.bundle.programs)
		app.rows = make([]Row, len(app.programs))
	} else if app.bundle_error == .Bad_Manifest {
		log.errorf("the list of programs in %s cannot be read", opts.bundle)
	}

	platform.set_app_id(APP_NAME)
	if !host.host_open(&app.main, &app.shared, {title = APP_TITLE, size = WINDOW_SIZE, integrated_title = !app.settings.system_title}, view_build, app) {
		log.error("no window")
		app_free(app)
		return 1
	}
	h := &app.main
	// (the views' memory read here, before the loop; written on its own thread from now on)
	ui.views_init(&app.views, {path = app.demo ? "" : views_path()})
	ui.set_views(&h.state, &app.views)
	// (the actions' ids known before the first command_pressed: else a person's key would not act in the first frames;
	// the programs' "Open" lines are known when their table is made, actions.odin)
	ui.keymap_known(&app.keymap, slice.enumerated_array(&ACTIONS))
	ui.keymap_use(&h.state, &app.keymap)
	app.announcer = {mode = app.settings.messages, window = h.win, state = &h.state}
	// (the zoom, the density, the scrolling, the delays, the text's rendering, the person's keys...: applied now, then
	// each as it changes)
	prefs_page.standard_watch(&app.standard, &app.prefs, &h.state, {renderer = &app.shared.r, fonts = &app.shared.fonts, partial_redraw = &h.partial_redraw, keymap = &app.keymap})
	// (Lucide: the icons of the steps, the palette, the settings; one face, the one ui.lucide_icons gives the widgets)
	icons, _ := font.load_embedded(&app.shared.fonts, lucide.DATA)
	h.state.icon_font, h.state.lucide_font = icons, icons
	h.params = app_params
	h.background = ui.theme_lookup(&app.shared.theme, {}, "background")
	// (TOOLKIT_DEVTOOLS=<port>: the window driven and captured over the DevTools protocol, for ateliertool shots and live)
	app.devtools = devtools.start_from_env(h.win, APP_NAME)
	h.before_input = proc(h: ^host.Host) { app := (^App)(h.user); devtools.service(app.devtools, &h.state, &app.shared.r) }
	// (the window where it was, at its size: the toolkit's window.placement; Wayland places it itself)
	if !app.demo { prefs_page.placement_restore(&app.placement, &app.prefs, h.win) }
	if logo, ok := setup.logo_make(&app.shared.r, LOGO_PNG); ok {
		app.logo, app.logo_size = logo.texture, logo.size
		app.install.logo = logo
		// (atelier's own row shows the same texture: app_run destroys it once)
		if len(app.rows) > 0 { app.rows[0].logo, app.rows[0].logo_size = app.logo, app.logo_size }
	}
	// (the vendor's mark in the "By" line of the install's dialog and of the Installation page: made before either opens)
	prefs_page.install_vendor_mark(&app.install, &app.shared.r, VENDOR_MARK_PNG)
	if app.bundle != nil { start_ask(app) }
	app.step = opts.step
	if app.demo { demo_step(app, opts.step, opts.finished) }
	// (the demo reaches no network and reads no install: the pictures show the steps alone)
	if !app.demo {
		updates_start(app)
		// (the install read on a task: updates_follow applies update.auto once it is known. Never offered at the start: atelier's own row of the Programs step
		// installs it, src/md/README.md "atelier's own row")
		prefs_page.install_offer(&app.install, &h.state, offer = false)
	}
	palette_init(app)
	// (a second start hands its launcher's token: this window comes to the front)
	server: ^instance.Server
	if opts.owner.state == .Claimed {
		server = instance.serve_start(opts.owner, app_message, app)
	}

	platform.show_window(h.win)
	if setup_asked { prefs_page.install_open(&app.install) }
	host.host_frame(h)
	hosts := [1]^host.Host{h}
	for !platform.is_closed(h.win) {
		host.hosts_wait(hosts[:])
		updates_follow(app)
		if !app.demo {
			prefs_page.placement_track(&app.placement, &app.prefs, h.win, ui.now_ms())
			config.user_writer_save(&app.prefs_writer, &app.prefs)
			if config.user_writer_failed(&app.prefs_writer) { ui.announce(&app.announcer, .Bad, i18n.tr("The preferences cannot be written")) }
		}
		if !platform.is_closed(h.win) { host.host_frame(h) }
	}

	// (an install under way ends first: each program's own install writes atomically, and the next one is not started.
	// What the workers posted is taken, so that it is freed with the rest)
	app.closing = true
	if !app.demo { prefs_page.placement_keep(&app.placement, &app.prefs, h.win) }
	updates_stop(app)
	devtools.stop(app.devtools)
	ui.chores_stop(0)
	ui.drain_posts(&h.state)
	prefs_page.install_end(&app.install)   // (its thread waited for, before the window's State goes)
	for &r, i in app.rows {
		if r.logo_size != {} && !app.programs[i].own { render.destroy_texture(&app.shared.r, r.logo) }
		row_destroy(&r)
	}
	// (app.logo is the install's logo: freed once, with it)
	setup.logo_destroy(&app.shared.r, &app.install.logo)
	// (after the last build, while the window's State is there: which views were open is written)
	ui.views_destroy(&app.views)
	host.host_close(h)
	// (the files taken out stay until atelier ends: a second look at a state needs no second copy of 30 MB)
	if app.bundle != nil && !app.demo {
		for p in app.bundle.programs { scratch_remove(p) }
		scratch_end()
	}
	// (the instance let go: the installed copy the install's dialog opened, or the updated one, is the running atelier now)
	instance.serve_stop(server)
	prefs_page.install_launch(&app.install)
	launch := app.launch_after
	app.launch_after = ""
	launch_args: []string = app.launch_after_update ? {"--after-update"} : nil
	app_free(app)
	if launch != "" {
		if !setup.launch(launch, launch_args) { log.errorf("%s does not start", launch) }
		delete(launch)
	}
	return 0
}

@(private = "file")
app_free :: proc(app: ^App) {
	delete(app.rows)
	delete(app.batch)
	delete(app.asking)
	delete(app.suite_version)
	newer_destroy(app.suite_newer)
	delete(app.programs)
	bundle_destroy(app.bundle)
	delete(app.prefs_path)
	delete(app.launch_after)
	crash_bar.destroy(&app.crash_bar)
	prefs_page.themes_file_destroy(&app.themes_file)
	palette_destroy(app)
	ui.shortcuts_sheet_destroy(&app.sheet)
	prefs_page.destroy(&app.settings_page)
	settings_free(&app.settings)
	prefs_page.standard_unwatch(&app.standard)
	ui.keymap_destroy(&app.keymap)   // (after standard_unwatch: its changes no longer reach the keymap)
	if !app.demo { config.user_writer_stop(&app.prefs_writer, &app.prefs) }   // (the last change written)
	prefs_page.placement_keeper_destroy(&app.placement)
	config.prefs_destroy(&app.prefs)
}

// atelier's theme: graphite surfaces, warm text, the orange of the site and of the bench's wood as its accent.
THEME_ATELIER :: ui.Theme_Def{"atelier",
	{{0x0f0f11ff, 0x141416ff, 0x1a1a1dff, 0x1c1c1fff, 0x252529ff, 0x2e2e33ff}, {0x5d5953ff, 0x9a958dff, 0xece8e1ff, 0xfffaf2ff},
		{0xec7a43ff, 0x8fa9c9ff, 0xa99bc4ff, 0x46a758ff, 0xf5a524ff, 0xe5484dff, 0x95c3c8ff, 0xc9a0b4ff}},
	{{0xebe8e3ff, 0xf6f4f0ff, 0xffffffff, 0xffffffff, 0xeeebe5ff, 0xe1ddd5ff}, {0xa39e95ff, 0x6f6a63ff, 0x1b1b1fff, 0x000000ff},
		{0xc4532aff, 0x3d6a9eff, 0x6b56a3ff, 0x2f8f46ff, 0xc98a10ff, 0xd93d42ff, 0x2f7c86ff, 0xa64a72ff}},
	.Both, nil, false, 0}

// The themes the window can show: atelier's, then the toolkit's (gui_toolkit docs/themes.md).
themes :: proc() -> []ui.Theme_Def {
	@(static) list: [len(ui.THEMES) + 1]ui.Theme_Def
	if list[0].name == "" {
		list[0] = THEME_ATELIER
		copy(list[1:], ui.THEMES[:])
	}
	return list[:]
}

// What each build of the window is given: the theme the settings name (atelier's by default, light or dark as the
// system), the base style.
@(private = "file")
app_params :: proc(h: ^host.Host, bp: ^ui.Build_Params) {
	app := (^App)(h.user)
	// (applied only when it changes, or the system goes light or dark: a palette applied starts a cross-fade)
	choice := prefs_page.appearance_choice(app.settings.look)
	if ui.theme_show(&app.shared.theme, app.themes_file.all[:], choice, &app.theme_shown, render.blend_space(&app.shared.r)) {
		platform.set_dark_title(h.win, !app.theme_shown.light)
		h.background = ui.theme_lookup(&app.shared.theme, {}, "background")
	}
	bp.inactive = !h.win.active
	bp.base = ui.Style{pref = {.X = ui.text_size(), .Y = ui.px(28)}, font = app.shared.font, font_size = app.settings.look.font_size, text_pad = 6, cursor = .Arrow}
}

// window.system_title: the system's title bar, or atelier's own, switched at once.
app_title_follow :: proc(app: ^App) {
	platform.set_integrated_title(app.main.win, !app.settings.system_title)
}

////////////////////////////////
// One atelier at a time

// The single instance's name: the person's (a debug build has its own).
app_instance_name :: proc() -> string {
	return instance.key(ODIN_DEBUG ? "atelier.dev" : "atelier", platform.user_dir(.Config, "", context.temp_allocator))
}

// Whether an atelier runs and answers (--status: setup.Setup_Options.running).
app_running :: proc() -> bool { return instance.running({name = app_instance_name()}) }

// Asks the running atelier to end, as its Quit does (--quit: setup.Setup_Options.quit).
app_quit_ask :: proc() -> bool { return instance.quit({name = app_instance_name()}) }

// A message of another process (on the instance's thread): a ping, a request to end, or a second start's launcher's
// activation token, handed to the window's thread.
@(private = "file")
app_message :: proc(user: rawptr, message: []byte) {
	app := (^App)(user)
	switch string(message) {
	case instance.MESSAGE_PING: return
	case instance.MESSAGE_QUIT:
		// (the window closes on its own thread, as Ctrl+Q does: an install under way ends first)
		ui.post(&app.main.state, proc(_: rawptr, _: u64) {
			if a := the_app; a != nil && !a.closing { platform.request_close(a.main.win) }
		}, nil, 0)
		return
	}
	token := strings.clone(string(message))
	if !ui.post(&app.main.state, app_message_raise, rawptr(raw_data(token)), u64(len(token))) { delete(token) }
}

// The window comes to the front, with the second start's token (Wayland gives it the keyboard with it).
@(private = "file")
app_message_raise :: proc(data: rawptr, word: u64) {
	token := string(([^]u8)(data)[:word])
	defer delete(token)
	app := the_app
	if app == nil || app.closing { return }
	platform.raise_window_token(app.main.win, token)
	host.host_settle(&app.main)
}

////////////////////////////////
// The steps

// Moves the window to the step after `event`, and starts what that step needs.
app_step :: proc(app: ^App, event: Step_Event) {
	next := step_next(app.step, event)
	if next == app.step { return }
	from := app.step
	app.step = next
	app.copied = -1
	// "Accept and install": the rows ticked are chosen, then the look for the copies that run
	if from == .Licences && next == .Checking {
		clear(&app.batch)
		for &r, i in app.rows {
			r.result, r.close = .None, false
			if !r.ticked { continue }
			r.result = result_next(r.result, .Choose)
			append(&app.batch, i)
		}
		// (the demo's look is made up: demo_step says what it shows)
		if !app.demo { look_start(app) }
	}
	if next == .Installing {
		app.stage = .Running
		if app.demo { demo_install(app) }
	}
}

// The rows chosen.
chosen_count :: proc(app: ^App) -> (n: int) {
	for r in app.rows { if r.ticked { n += 1 } }
	return
}

// Ticks every box that can be ticked (true), or none (false).
select_all :: proc(app: ^App, on: bool) {
	for &r in app.rows { r.ticked = on && row_choosable(app, r) }
}

// Whether the person can tick the row's box.
row_choosable :: proc(app: ^App, r: Row) -> bool {
	return app.known && state_choosable(r.status.state) && !r.status.by_nix
}

// Whether every licence of the programs chosen is read: "Accept and install" waits for it.
licences_ready :: proc(app: ^App) -> bool {
	for r in app.rows { if r.ticked && r.licences == nil { return false } }
	return true
}

////////////////////////////////
// 1. The start: the logos, the licences, NixOS

@(private = "file")
Start_Job :: struct {
	bundle:   ^Bundle,
	programs: []Program,    // the App's (read only, as the bundle)
	logos:    []Pixels,     // one per program (rgba nil: none)
	licences: [][]string,   // one per program: its licences' texts
	nixos:    bool,
	demo:     bool,
}

@(private = "file")
Pixels :: struct { rgba: []u8, w, h: int }

@(private = "file")
start_ask :: proc(app: ^App) {
	j := new(Start_Job)
	j.bundle, j.programs, j.demo = app.bundle, app.programs, app.demo
	ui.task(&app.main.state, start_work, start_done, j, start_lost)
}

@(private = "file")
start_work :: proc(data: rawptr) {
	j := (^Start_Job)(data)
	j.logos = make([]Pixels, len(j.programs))
	j.licences = make([][]string, len(j.programs))
	for p, i in j.programs {
		// (atelier's own: its logo is the window's, its licences are in the program)
		if p.own {
			j.licences[i] = own_licence_texts()
			continue
		}
		if p.logo != "" {
			if file, err := bundle_read(j.bundle, p.logo); !err {
				rgba, w, h, ok := png.decode(file)
				if ok { j.logos[i] = {rgba, w, h} }
				delete(file)
			}
		}
		texts := make([]string, len(p.licences))
		for l, k in p.licences {
			file, failed := bundle_read(j.bundle, l.file)
			// (a licence that cannot be read is said in its place: the person is never shown an empty licence as read)
			texts[k] = failed ? strings.clone(i18n.tr("This licence cannot be read from the bundle.")) : string(file)
		}
		j.licences[i] = texts
	}
	// (the demo reads nothing of the computer)
	j.nixos = !j.demo && nixos()
}

@(private = "file")
start_done :: proc(data: rawptr, _: u64) {
	j := (^Start_Job)(data)
	defer start_lost(j)
	app := the_app
	if app == nil || app.closing { return }
	for px, i in j.logos {
		if px.rgba == nil { continue }
		r := &app.rows[i]
		r.logo = render.create_texture_rgba(&app.shared.r, px.w, px.h)
		render.update_texture_rgba(&app.shared.r, r.logo, 0, 0, px.w, px.h, px.rgba)
		r.logo_size = {f32(px.w), f32(px.h)}
	}
	for &t, i in j.licences {
		app.rows[i].licences, t = t, nil
	}
	app.known, app.nixos = true, j.nixos
	if app.demo { return }
	// (every program asked at once: each reads its own file and runs its own process)
	for i in 0 ..< len(app.rows) { status_ask(app, i) }
}

@(private = "file")
start_lost :: proc(data: rawptr) {
	j := (^Start_Job)(data)
	for px in j.logos { delete(px.rgba) }
	delete(j.logos)
	for t in j.licences {
		for s in t { delete(s) }
		delete(t)
	}
	delete(j.licences)
	free(j)
}

////////////////////////////////
// 2. The states, one program after the other

@(private = "file")
Status_Job :: struct {
	bundle:  ^Bundle,
	program: Program,
	index:   int,
	scratch: string,
	status:  Status,
}

@(private = "file")
status_ask :: proc(app: ^App, index: int) {
	if index >= len(app.rows) { return }
	j := new(Status_Job)
	j.bundle, j.program, j.index = app.bundle, app.programs[index], index
	ui.task(&app.main.state, status_work, status_done, j, status_lost)
}

@(private = "file")
status_work :: proc(data: rawptr) {
	j := (^Status_Job)(data)
	p := j.program
	if p.own {
		j.status = own_status()
		free_all(context.temp_allocator)   // (gt:setup's facts)
		return
	}
	why: string
	j.scratch, why = take_out(j.bundle, p)
	if why != "" {
		j.status = {state = .Unknown, reason = strings.clone(why)}
		return
	}
	j.status = status_read(j.scratch, p.version)
}

@(private = "file")
status_done :: proc(data: rawptr, _: u64) {
	j := (^Status_Job)(data)
	defer free(j)
	app := the_app
	if app == nil || app.closing {
		status_destroy(&j.status)
		delete(j.scratch)
		return
	}
	r := &app.rows[j.index]
	// (programs.ticked off: every box starts empty, the person ticks what they want)
	row_status(r, j.status, tick = app.step <= .Programs, ticked = app.settings.ticked)
	delete(r.scratch)
	r.scratch = j.scratch
}

@(private = "file")
status_lost :: proc(data: rawptr) {
	j := (^Status_Job)(data)
	status_destroy(&j.status)
	delete(j.scratch)
	free(j)
}

////////////////////////////////
// 3. The look for the programs that run, and the question

// One task reads again, right before the installs, the --status of each program of the batch: the state may have
// changed while the person read the licences (src/md/README.md, "A program that runs"). The programs are read one
// after the other: a --status takes a moment, and the person waits for the whole answer anyway.

@(private = "file")
Look_Job :: struct {
	bundle: ^Bundle,
	rows:   []Look_Row,
}

@(private = "file")
Look_Row :: struct {
	index:   int,
	program: Program,
	scratch: string,   // the row's file taken out ("": take it out now; owned)
	status:  Status,
	read:    bool,     // the status was read (atelier's own is not: it never runs beside this atelier)
}

// Starts the look for the rows of the batch.
@(private = "file")
look_start :: proc(app: ^App) {
	app.look = look_next(app.look, .Start)
	clear(&app.asking)
	j := new(Look_Job)
	j.bundle = app.bundle
	j.rows = make([]Look_Row, len(app.batch))
	for i, k in app.batch {
		j.rows[k] = {index = i, program = app.programs[i], scratch = strings.clone(app.rows[i].scratch)}
	}
	ui.task(&app.main.state, look_work, look_done, j, look_lost)
}

@(private = "file")
look_work :: proc(data: rawptr) {
	j := (^Look_Job)(data)
	for &r in j.rows {
		// (one atelier at a time: no other atelier runs beside this one)
		if r.program.own { continue }
		if r.scratch == "" {
			why: string
			r.scratch, why = take_out(j.bundle, r.program)
			// (the install says why: its Unpack takes the file out again)
			if why != "" { continue }
		}
		r.status, r.read = open_read(r.scratch, r.program.version), true
		free_all(context.temp_allocator)
	}
}

@(private = "file")
look_done :: proc(data: rawptr, _: u64) {
	j := (^Look_Job)(data)
	defer look_lost(j)
	app := the_app
	if app == nil || app.closing { return }
	for &lr in j.rows {
		r := &app.rows[lr.index]
		if r.scratch == "" { r.scratch, lr.scratch = lr.scratch, "" }
		// (a status that could not be read says nothing of a copy that runs: the row keeps the one it had)
		if !lr.read || lr.status.state == .Unknown { continue }
		row_status(r, lr.status, tick = false)
		lr.status = {}
		if r.status.running { append(&app.asking, lr.index) }
	}
	if len(app.asking) == 0 {
		app.look = look_next(app.look, .None_Run)
		install_go(app)
		return
	}
	// (the next build opens the question: ask_build)
	app.look = look_next(app.look, .Some_Run)
}

@(private = "file")
look_lost :: proc(data: rawptr) {
	j := (^Look_Job)(data)
	for &r in j.rows {
		delete(r.scratch)
		status_destroy(&r.status)
	}
	delete(j.rows)
	free(j)
}

// The question's id among the window's views.
ASK_VIEW :: "close_running"

// The question, opened by the build after the look found a copy that runs, and its answer, read by the next builds.
ask_build :: proc(app: ^App) {
	#partial switch app.look {
	case .To_Ask:
		names := make([dynamic]string, context.temp_allocator)
		for i in app.asking { append(&names, app.programs[i].name) }
		n := len(names)
		list := strings.join(names[:], ", ", context.temp_allocator)
		ui.confirm_open(ASK_VIEW, {
			title = fmt.tprintf(i18n.tr(n, "This program is open: %s.", "These programs are open: %s."), list),
			note = i18n.tr(n, "Atelier closes it before it installs it. It keeps your data.", "Atelier closes them before it installs them. They keep your data."),
			act = i18n.tr(n, "Close it and install", "Close them and install"),
			act_intent = ui.Intent.Success,
			labels = {cancel = i18n.tr("Back"), enter = i18n.tr("%s (Enter)")},
		})
		app.look = look_next(app.look, .Shown)
	case .Asking:
		switch ui.confirm_answer(ASK_VIEW) {
		case .None:
		case .Confirmed: ask_answer(app, true)
		case .Cancelled: ask_answer(app, false)
		}
	}
}

// The person's answer: the programs that run are closed and the batch installs, or nothing of the batch starts (Back).
@(private = "file")
ask_answer :: proc(app: ^App, close: bool) {
	app.look = look_next(app.look, .Answer)
	if close {
		for i in app.asking { app.rows[i].close = true }
		install_go(app)
		return
	}
	for i in app.batch { app.rows[i].result = result_next(app.rows[i].result, .Give_Up) }
	clear(&app.batch)
	clear(&app.asking)
	// (the first install goes back to the licences; a retry leaves its rows failed)
	if app.step == .Checking { app_step(app, .Back) } else { install_finished(app) }
}

////////////////////////////////
// 4. The installs, side by side

// Each program installs itself in a process of its own, in a folder of its own: nothing is shared between two installs,
// so they all start at once (the chores run as many as they have threads). Each phase that starts is posted back for
// the program's stepper.

@(private = "file")
Install_Job :: struct {
	bundle:  ^Bundle,
	program: Program,
	index:   int,
	scratch: string,          // the file taken out at the start ("": take it out now)
	close:   bool,            // a copy runs, and the person agreed to close it: the Close phase runs
	exe:     string,          // the installed copy, which the Close phase frees ("": none)
	quits:   bool,            // the installed copy understands --quit
	phase:   Install_Phase,   // the phase that ran last (where it failed when !ok)
	ok:      bool,
	output:  string,
	exit_code: Maybe(int),    // the --install's (nil: the phase that failed ran no process)
	status:  Status,          // read again after the install: where the program is now
}

// Starts the install of every row of the batch (the look found no copy that runs, or the person agreed to close them).
@(private = "file")
install_go :: proc(app: ^App) {
	if app.demo {
		demo_go(app)
		return
	}
	if app.step == .Checking { app_step(app, .Next) }
	for i in app.batch {
		r := &app.rows[i]
		if r.result != .Waiting && r.result != .Retrying { continue }
		p := app.programs[i]
		r.result = result_next(r.result, .Start)
		// (atelier's own has nothing to take out nor to close: install_steps skips them)
		r.phase = p.own ? .Install : r.close ? .Close : .Unpack
		delete(r.output)
		r.output, r.exit_code, r.details = "", nil, false
		j := new(Install_Job)
		j.bundle, j.program, j.index, j.scratch, j.phase = app.bundle, p, i, strings.clone(r.scratch), r.phase
		j.close, j.exe, j.quits = r.close, strings.clone(r.status.program), r.status.quits
		ui.task(&app.main.state, install_work, install_done, j, install_lost)
	}
	clear(&app.batch)
	clear(&app.asking)
	install_finished(app)
}

// The Installing step's stage Finished once no row installs any more.
install_finished :: proc(app: ^App) {
	if app.step != .Installing { return }
	for r in app.rows { if result_busy(r.result) { return } }
	app.stage = stage_next(app.stage, .All_Ended)
}

// Starts the failed rows `rows` again, their whole way (src/md/README.md, "A failed install, again"). One look at a time:
// nothing while one is under way.
retry :: proc(app: ^App, rows: []int) {
	if app.look != .Idle { return }
	clear(&app.batch)
	for i in rows {
		r := &app.rows[i]
		if r.result != .Failed { continue }
		r.result, r.close, r.phase = result_next(r.result, .Retry), false, {}
		delete(r.output)
		r.output, r.exit_code, r.details = "", nil, false
		append(&app.batch, i)
	}
	if len(app.batch) == 0 { return }
	// (a row retried while others still install: the stage stays as it is, Running or Retrying)
	app.stage = stage_next(app.stage, .Retry)
	app.copied = -1
	if app.demo { install_go(app); return }
	look_start(app)
}

// Every failed row started again.
retry_failed :: proc(app: ^App) {
	failed := make([dynamic]int, context.temp_allocator)
	for r, i in app.rows { if r.result == .Failed { append(&failed, i) } }
	retry(app, failed[:])
}

// Whether a retry can start now: a row failed, and no look is under way.
retry_possible :: proc(app: ^App) -> bool {
	if app.look != .Idle || app.step != .Installing { return false }
	for r in app.rows { if r.result == .Failed { return true } }
	return false
}

// A phase starts, told to the window (from the worker): the word is the row and the phase.
@(private = "file")
phase_post :: proc(j: ^Install_Job, phase: Install_Phase) {
	j.phase = phase
	ui.post(&the_app.main.state, proc(_: rawptr, word: u64) {
		app := the_app
		if app == nil || app.closing { return }
		row, phase := int(word >> 8), Install_Phase(word & 0xff)
		if row < len(app.rows) && app.rows[row].result == .Installing { app.rows[row].phase = phase }
	}, nil, u64(j.index) << 8 | u64(phase))
}

@(private = "file")
install_work :: proc(data: rawptr) {
	j := (^Install_Job)(data)
	p := j.program
	if p.own {
		own_install_work(j)
		return
	}
	// (a failed install keeps its file: a retry checks it again and uses it)
	defer if j.ok { scratch_remove(p) }
	// Close: the copy that runs ends, and the installed file is free
	if j.close {
		// (no file taken out: its --quit has nowhere to write its output, and the process is ended instead)
		why := close_program(j.exe, j.quits && j.scratch != "", j.scratch)
		free_all(context.temp_allocator)
		if why != "" { j.output = strings.clone(why); return }
		phase_post(j, .Unpack)
	}
	// Unpack: the file taken out now, or the one taken out before checked again (taken out again when it changed)
	why: string
	if j.scratch != "" && check_scratch(j.scratch, p) != "" {
		delete(j.scratch)
		j.scratch = ""
	}
	if j.scratch == "" { j.scratch, why = take_out(j.bundle, p) }
	if why != "" { j.output = strings.clone(why); return }
	phase_post(j, .Install)
	j.ok, j.output, j.exit_code = install_one(j.scratch)
	if !j.ok { return }
	// Check: the carried version is the one installed now
	phase_post(j, .Check)
	j.status = status_read(j.scratch, p.version)
	if j.status.state != .Current {
		j.ok = false
		delete(j.output)
		j.output = strings.clone(fmt.tprintf(i18n.tr("After its install, the program says: %s"), state_words(j.status)))
	}
}

// atelier's own install: Copy (gt:setup copies the running file), then Check (the facts again: the installed copy is
// this version). Its phase starts at Install: Unpack has nothing to do.
@(private = "file")
own_install_work :: proc(j: ^Install_Job) {
	defer free_all(context.temp_allocator)   // (gt:setup's strings)
	j.phase = .Install
	j.ok, j.output = own_install()
	if !j.ok { return }
	phase_post(j, .Check)
	j.status = own_status()
	if j.status.state != .Current || j.status.installed != APP_VERSION {
		j.ok = false
		delete(j.output)
		j.output = strings.clone(fmt.tprintf(i18n.tr("After its install, the program says: %s"), state_words(j.status)))
	}
}

@(private = "file")
install_done :: proc(data: rawptr, _: u64) {
	j := (^Install_Job)(data)
	defer free(j)
	app := the_app
	if app == nil || app.closing {
		install_free(j)
		return
	}
	r := &app.rows[j.index]
	r.result, r.phase, r.exit_code, r.details = result_next(r.result, j.ok ? .Succeed : .Fail), j.phase, j.exit_code, false
	// (the window's lines go when atelier ends: the log keeps the whole failure. gt:log's writer thread writes it)
	if !j.ok {
		code := "-"
		if c, ran := j.exit_code.?; ran { code = exit_code_words(c) }
		log.errorf("%s %s: the %v phase failed (exit code %s):\n%s", j.program.slug, j.program.version, j.phase, code, j.output != "" ? j.output : "(no output)")
	}
	delete(r.output)
	r.output, j.output = j.output, ""
	if j.ok {
		status_destroy(&r.status)
		r.status, j.status = j.status, {}
		row_scratch_set(r, "")
	} else {
		// (kept for a retry: install_work checks it again)
		delete(r.scratch)
		r.scratch, j.scratch = j.scratch, ""
	}
	install_free(j)
	install_finished(app)
}

@(private = "file")
install_free :: proc(j: ^Install_Job) {
	delete(j.scratch)
	delete(j.exe)
	delete(j.output)
	status_destroy(&j.status)
}

@(private = "file")
install_lost :: proc(data: rawptr) {
	j := (^Install_Job)(data)
	install_free(j)
	free(j)
}

////////////////////////////////
// The installed program started

// Starts an installed program on its own (a worker: a start waits on the disk). It outlives atelier.
open_program :: proc(app: ^App, path: string) {
	if app.demo || path == "" { return }
	Open :: struct { path: string }
	o := new(Open, runtime.heap_allocator())
	o.path = strings.clone(path, runtime.heap_allocator())
	ui.task(&app.main.state, proc(d: rawptr) {
		o := (^Open)(d)
		if !setup.launch(o.path) { log.errorf("%s does not start", o.path) }
		delete(o.path, runtime.heap_allocator())
		free(o, runtime.heap_allocator())
	}, nil, o)
}

// The text of a step's count, for the Installing step.
installed_count :: proc(app: ^App) -> (done, of: int) {
	for r in app.rows {
		if r.result == .None { continue }
		of += 1
		if r.result == .Installed || r.result == .Failed { done += 1 }
	}
	return
}
