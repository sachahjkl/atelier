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
//   3. after "Accept and install", one task per program chosen, all at once: its phases (Unpack, Install, Check), each
//      one posted back as it starts (install_work).

import "base:runtime"
import "core:fmt"
import "core:log"
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

// Frames owed after an event (what it set off settles: the layout of a step that just showed).
FRAMES_AFTER_INPUT :: 3

// The program's catalogues of the languages it speaks besides English (i18n/<language>.txt, written by the i18n tool).
PROGRAM_CATALOGUES :: []i18n.Catalog{{"fr", #load("../i18n/fr.txt", string)}}

// atelier's own mark: in the title bar, on the welcome and in the install's dialog.
LOGO_PNG :: #load("../assets/logo_128.png")

App :: struct {
	shared:       host.Shared,
	main:         host.Host,
	bundle:       ^Bundle,         // nil: this copy carries no programs (bundle_error says why)
	bundle_error: Bundle_Error,
	rows:         []Row,           // one per program of the bundle, in its order
	step:         Step,
	demo:         bool,            // made-up states, nothing runs (--demo)
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

	// atelier's own install and updates (setup_view.odin, updates.odin)
	install:        prefs_page.Install,
	setup_known:    bool,              // the start's reading of the install came (setup_follow)
	installed_copy: bool,              // this program is the installed copy: it updates itself (update.auto)
	updater:        ^update.Updater,   // nil in the demo
	update_serial:  int,               // the updater's state last said
	launch_after:   string,            // this program again after an update, started once this one has ended (owned)
}

// The App of the process: a worker's answer finds it.
the_app: ^App

// app_run takes the registry: it is the App's from now on (`prefs` is left empty).
app_run :: proc(opts: Run_Options, prefs: ^config.Prefs, setup_asked: bool) -> int {
	app := new(App)
	defer free(app)
	the_app = app
	defer the_app = nil
	app.demo, app.copied = opts.demo, -1
	if opts.last_crash != "" {
		log.warnf("the last run ended without its clean end: %s", opts.last_crash)
		crash_bar.init(&app.crash_bar, opts.last_crash)
	}
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
		app.rows = make([]Row, len(app.bundle.programs))
	} else if app.bundle_error == .Bad_Manifest {
		log.errorf("the list of programs in %s cannot be read", opts.bundle)
	}

	platform.set_app_id(APP_NAME)
	if !host.host_open(&app.main, &app.shared, {title = "atelier", size = WINDOW_SIZE, integrated_title = !app.settings.system_title}, view_build, app) {
		log.error("no window")
		app_free(app)
		return 1
	}
	h := &app.main
	// (the views' memory read here, before the loop; written on its own thread from now on)
	ui.views_init(&app.views, {path = app.demo ? "" : views_path()})
	ui.set_views(&h.state, &app.views)
	app.announcer = {mode = app.settings.messages, window = h.win, state = &h.state}
	// (the zoom, the density, the scrolling, the delays, the text's rendering...: applied now, then each as it changes)
	prefs_page.standard_watch(&app.standard, &app.prefs, &h.state, {renderer = &app.shared.r, fonts = &app.shared.fonts, partial_redraw = &h.partial_redraw})
	// (Lucide: the icons of the steps, the palette, the settings; one face, the one ui.lucide_icons gives the widgets)
	icons, _ := font.load_embedded(&app.shared.fonts, lucide.DATA)
	h.state.icon_font, h.state.lucide_font = icons, icons
	h.after_input = FRAMES_AFTER_INPUT
	h.params = app_params
	h.background = ui.theme_lookup(&app.shared.theme, {}, "background")
	// (TOOLKIT_DEVTOOLS=<port>: the window driven and captured over the DevTools protocol, for ateliertool shots and live)
	app.devtools = devtools.start_from_env(h.win, APP_NAME)
	h.before_input = proc(h: ^host.Host) { app := (^App)(h.user); devtools.service(app.devtools, &h.state, &app.shared.r) }
	// (the window where it was, at its size: the toolkit's window.placement; Wayland places it itself)
	if !app.demo { prefs_page.placement_restore(&app.placement, &app.prefs, h.win) }
	if img, ok := platform.clipboard_image_decode("image/png", LOGO_PNG, context.temp_allocator); ok {
		app.logo = render.create_texture_rgba(&app.shared.r, img.size.x, img.size.y)
		render.update_texture_rgba(&app.shared.r, app.logo, 0, 0, img.size.x, img.size.y, img.rgba)
		app.logo_size = {f32(img.size.x), f32(img.size.y)}
		app.install.logo = setup.Logo{app.logo, app.logo_size}
	}
	if app.bundle != nil { start_ask(app) }
	app.step = opts.step
	if app.demo { demo_step(app, opts.step) }
	// (the demo reaches no network and reads no install: the pictures show the steps alone)
	if !app.demo {
		updates_start(app)
		// (the install read on a task: setup_follow; offered on Windows, where nothing else installs atelier)
		prefs_page.install_offer(&app.install, &h.state, offer = ODIN_OS == .Windows && !setup_asked)
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
	for &r in app.rows {
		if r.logo_size != {} { render.destroy_texture(&app.shared.r, r.logo) }
		row_destroy(&r)
	}
	if app.logo_size != {} { render.destroy_texture(&app.shared.r, app.logo) }
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
	app_free(app)
	if launch != "" {
		if !setup.launch(launch) { log.errorf("%s does not start", launch) }
		delete(launch)
	}
	return 0
}

@(private = "file")
app_free :: proc(app: ^App) {
	delete(app.rows)
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

// What `atelier --status` hands the running one: only whether it answers.
APP_MESSAGE_PING :: "\x02ping"

// Whether an atelier runs and answers (--status: setup.Setup_Options.running).
app_running :: proc() -> bool {
	return instance.send({name = app_instance_name(), wait_ms = 2000}, transmute([]u8)string(APP_MESSAGE_PING)) == .Forwarded
}

// A second start's message (on the instance's thread): its launcher's activation token, handed to the window's thread.
@(private = "file")
app_message :: proc(user: rawptr, message: []byte) {
	app := (^App)(user)
	if string(message) == APP_MESSAGE_PING { return }
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
	app.main.settle = max(app.main.settle, FRAMES_AFTER_INPUT)
}

////////////////////////////////
// The steps

// Moves the window to the step after `event`, and starts what that step needs.
app_step :: proc(app: ^App, event: Step_Event) {
	next := step_next(app.step, event)
	if next == app.step { return }
	app.step = next
	app.copied = -1
	if next == .Installing {
		for &r in app.rows { r.result = r.ticked ? .Waiting : .None }
		if app.demo { demo_install(app) } else { install_start(app) }
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
	return app.known && state_choosable(r.status.state)
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
	j.bundle, j.demo = app.bundle, app.demo
	ui.task(&app.main.state, start_work, start_done, j, start_lost)
}

@(private = "file")
start_work :: proc(data: rawptr) {
	j := (^Start_Job)(data)
	j.logos = make([]Pixels, len(j.bundle.programs))
	j.licences = make([][]string, len(j.bundle.programs))
	for p, i in j.bundle.programs {
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
	index:   int,
	scratch: string,
	status:  Status,
}

@(private = "file")
status_ask :: proc(app: ^App, index: int) {
	if index >= len(app.rows) { return }
	j := new(Status_Job)
	j.bundle, j.index = app.bundle, index
	ui.task(&app.main.state, status_work, status_done, j, status_lost)
}

@(private = "file")
status_work :: proc(data: rawptr) {
	j := (^Status_Job)(data)
	p := j.bundle.programs[j.index]
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
// 3. The installs, side by side

// Each program installs itself in a process of its own, in a folder of its own: nothing is shared between two installs,
// so they all start at once (the chores run as many as they have threads). Each phase that starts is posted back for
// the program's stepper.

@(private = "file")
Install_Job :: struct {
	bundle:  ^Bundle,
	index:   int,
	scratch: string,          // the file taken out at the start ("": take it out now)
	phase:   Install_Phase,   // the phase that ran last (where it failed when !ok)
	ok:      bool,
	output:  string,
	status:  Status,          // read again after the install: where the program is now
}

// Starts the install of every row waiting.
install_start :: proc(app: ^App) {
	for &r, i in app.rows {
		if r.result != .Waiting { continue }
		r.result, r.phase = .Installing, .Unpack
		j := new(Install_Job)
		j.bundle, j.index, j.scratch = app.bundle, i, strings.clone(r.scratch)
		ui.task(&app.main.state, install_work, install_done, j, install_lost)
	}
	install_finished(app)
}

// The Done step once no row installs any more.
@(private = "file")
install_finished :: proc(app: ^App) {
	for r in app.rows { if r.result == .Waiting || r.result == .Installing { return } }
	app_step(app, .Finished)
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
	p := j.bundle.programs[j.index]
	defer scratch_remove(p)
	// Unpack: the file taken out now, or the one of the start checked again
	why: string
	if j.scratch == "" {
		j.scratch, why = take_out(j.bundle, p)
	} else {
		why = check_scratch(j.scratch, p)
	}
	if why != "" { j.output = strings.clone(why); return }
	phase_post(j, .Install)
	j.ok, j.output = install_one(j.scratch)
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
	r.result, r.phase = j.ok ? .Installed : .Failed, j.phase
	delete(r.output)
	r.output, j.output = j.output, ""
	if j.ok {
		status_destroy(&r.status)
		r.status, j.status = j.status, {}
	}
	row_scratch_set(r, "")
	install_free(j)
	install_finished(app)
}

@(private = "file")
install_free :: proc(j: ^Install_Job) {
	delete(j.scratch)
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
