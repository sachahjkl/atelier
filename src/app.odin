package atelier

// The window and its loop. The loop sleeps in the toolkit's wait until input or a worker's answer (ui.task posts it):
// at rest, nothing runs. The frame reads and writes nothing: the logos, the states, the licences and the installs are
// workers' (the tasks below), each answer posted back to the window's thread.
//
// What the workers do, in order:
//   1. at the start, one task decodes the logos and reads whether the system is NixOS (start_work);
//   2. then, unless in the demo, one task per program, all at once: its file taken out and its --status read
//      (status_work), so that a box shows its state as soon as it is known;
//   3. when the Licences step first shows, one task reads the licences of the programs chosen (licences_work);
//   4. after "Accept and install", one task per program chosen, all at once: its phases (Unpack, Install, Check), each
//      one posted back as it starts (install_work).

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:strings"
import devtools "gt:devtools"
import host "gt:host"
import i18n "gt:i18n"
import "gt:platform"
import png "gt:png"
import "gt:render"
import setup "gt:setup"
import "gt:ui"

// The window's size at its start, in logical pixels.
WINDOW_SIZE :: [2]int{820, 600}

// Frames owed after an event (what it set off settles: the layout of a step that just showed).
FRAMES_AFTER_INPUT :: 3

// The program's catalogues of the languages it speaks besides English (i18n/<language>.txt, written by the i18n tool).
PROGRAM_CATALOGUES :: []i18n.Catalog{{"fr", #load("../i18n/fr.txt", string)}}

// atelier's own mark, beside its name at the top of each step.
LOGO_PNG :: #load("../assets/logo_64.png")

App :: struct {
	shared:       host.Shared,
	main:         host.Host,
	bundle:       ^Bundle,         // nil: this copy carries no programs (bundle_error says why)
	bundle_error: Bundle_Error,
	rows:         []Row,           // one per program of the bundle, in its order
	step:         Step,
	demo:         bool,            // made-up states, nothing runs (--demo)
	known:        bool,            // the start's task answered: the logos are made, nixos is known
	nixos:        bool,            // Nix is the better install here: its lines are offered above the programs
	logo:         render.Texture,  // atelier's
	logo_size:    [2]f32,
	licences_asked: bool,          // the licences of the programs chosen are being read
	copied:       int,             // the row whose Nix line was just copied (-1: none): a check until the pointer leaves
	closing:      bool,            // the window closed: what the workers post is freed, not shown
	last_crash:   string,          // the last run's crash report, said in the log
	devtools:     ^devtools.Server,
	theme_shown:  ui.Theme_Shown,
	look:         ui.Theme_Mode,
}

// The App of the process: a worker's answer finds it.
the_app: ^App

app_run :: proc(opts: Run_Options) -> int {
	app := new(App)
	defer free(app)
	the_app = app
	defer the_app = nil
	app.demo, app.copied, app.look = opts.demo, -1, opts.look
	if opts.last_crash != "" { log.warnf("the last run ended without its clean end: %s", opts.last_crash) }
	// (the language before anything is formatted for display)
	if l, bad := i18n.load(platform.system_language(context.temp_allocator), PROGRAM_CATALOGUES); l != nil {
		for b in bad { log.warnf("i18n: %s", b) }
		i18n.use(l)
	}
	// (a start-up read, before the window: the end of the file, then the manifest; no frame waits for it)
	app.bundle, app.bundle_error = bundle_open(opts.bundle)
	if app.bundle != nil {
		app.rows = make([]Row, len(app.bundle.programs))
	} else if app.bundle_error == .Bad_Manifest {
		log.errorf("the list of programs in %s cannot be read", opts.bundle)
	}

	platform.set_app_id(APP_NAME)
	if !host.host_open(&app.main, &app.shared, {title = "atelier", size = WINDOW_SIZE}, view_build, app) {
		log.error("no window")
		bundle_destroy(app.bundle)
		delete(app.rows)
		return 1
	}
	h := &app.main
	h.after_input = FRAMES_AFTER_INPUT
	h.params = app_params
	h.partial_redraw = true
	h.background = ui.theme_lookup(&app.shared.theme, {}, "background")
	platform.set_dark_title(h.win, true)
	// (TOOLKIT_DEVTOOLS=<port>: the window driven and captured over the DevTools protocol, for ateliertool shots)
	app.devtools = devtools.start_from_env(h.win, APP_NAME)
	h.before_input = proc(h: ^host.Host) { app := (^App)(h.user); devtools.service(app.devtools, &h.state, &app.shared.r) }
	if img, ok := platform.clipboard_image_decode("image/png", LOGO_PNG, context.temp_allocator); ok {
		app.logo = render.create_texture_rgba(&app.shared.r, img.size.x, img.size.y)
		render.update_texture_rgba(&app.shared.r, app.logo, 0, 0, img.size.x, img.size.y, img.rgba)
		app.logo_size = {f32(img.size.x), f32(img.size.y)}
	}
	if app.bundle != nil { start_ask(app) }
	app.step = opts.step
	if app.demo { demo_step(app, opts.step) }

	platform.show_window(h.win)
	host.host_frame(h)
	hosts := [1]^host.Host{h}
	for !platform.is_closed(h.win) {
		host.hosts_wait(hosts[:])
		host.host_frame(h)
	}

	// (an install under way ends first: each program's own install writes atomically, and the next one is not started.
	// What the workers posted is taken, so that it is freed with the rest)
	app.closing = true
	devtools.stop(app.devtools)
	ui.chores_stop(0)
	ui.drain_posts(&h.state)
	for &r in app.rows {
		if r.logo_size != {} { render.destroy_texture(&app.shared.r, r.logo) }
		row_destroy(&r)
	}
	if app.logo_size != {} { render.destroy_texture(&app.shared.r, app.logo) }
	host.host_close(h)
	// (the files taken out stay until atelier ends: a second look at a state needs no second copy of 30 MB)
	if app.bundle != nil && !app.demo {
		for p in app.bundle.programs { scratch_remove(p) }
		scratch_end()
	}
	delete(app.rows)
	bundle_destroy(app.bundle)
	return 0
}

// atelier's theme: graphite surfaces, warm text, the orange of the site and of the bench's wood as its accent.
THEME_ATELIER :: ui.Theme_Def{"atelier",
	{{0x0f0f11ff, 0x141416ff, 0x1a1a1dff, 0x1c1c1fff, 0x252529ff, 0x2e2e33ff}, {0x5d5953ff, 0x9a958dff, 0xece8e1ff, 0xfffaf2ff},
		{0xec7a43ff, 0x8fa9c9ff, 0xa99bc4ff, 0x46a758ff, 0xf5a524ff, 0xe5484dff, 0x95c3c8ff, 0xc9a0b4ff}},
	{{0xebe8e3ff, 0xf6f4f0ff, 0xffffffff, 0xffffffff, 0xeeebe5ff, 0xe1ddd5ff}, {0xa39e95ff, 0x6f6a63ff, 0x1b1b1fff, 0x000000ff},
		{0xc4532aff, 0x3d6a9eff, 0x6b56a3ff, 0x2f8f46ff, 0xc98a10ff, 0xd93d42ff, 0x2f7c86ff, 0xa64a72ff}},
	.Both, nil, false, 0}

// What each build of the window is given: the theme (the system's light or dark, the machined finish of the site's
// buttons and wells), the base style.
@(private = "file")
app_params :: proc(h: ^host.Host, bp: ^ui.Build_Params) {
	app := (^App)(h.user)
	@(static) themes := [1]ui.Theme_Def{THEME_ATELIER}
	if ui.theme_show(&app.shared.theme, themes[:], {name = "atelier", mode = app.look, finish = .Machined}, &app.theme_shown, render.blend_space(&app.shared.r)) {
		platform.set_dark_title(h.win, !app.theme_shown.light)
		h.background = ui.theme_lookup(&app.shared.theme, {}, "background")
	}
	bp.inactive = !h.win.active
	bp.base = ui.Style{pref = {.X = ui.text_size(), .Y = ui.px(28)}, font = app.shared.font, font_size = 14, text_pad = 6, cursor = .Arrow}
}

// Moves the window to the step after `event`, and starts what that step needs.
app_step :: proc(app: ^App, event: Step_Event) {
	next := step_next(app.step, event)
	if next == app.step { return }
	app.step = next
	app.copied = -1
	#partial switch next {
	case .Licences:   licences_ask(app)
	case .Installing:
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

////////////////////////////////
// 1. The start: the logos, NixOS

@(private = "file")
Start_Job :: struct {
	bundle: ^Bundle,
	logos:  []Pixels,   // one per program (rgba nil: none)
	nixos:  bool,
	demo:   bool,
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
	for p, i in j.bundle.programs {
		if p.logo == "" { continue }
		file, err := bundle_read(j.bundle, p.logo)
		if err { continue }
		rgba, w, h, ok := png.decode(file)
		delete(file)
		if ok { j.logos[i] = {rgba, w, h} }
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
	row_status(r, j.status, tick = app.step <= .Programs)
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
// 3. The licences of the programs chosen

@(private = "file")
Licences_Job :: struct {
	bundle: ^Bundle,
	wanted: []int,        // the rows whose licences are read
	texts:  [][]string,   // for each, its licences' texts
}

@(private = "file")
licences_ask :: proc(app: ^App) {
	if app.licences_asked || app.bundle == nil { return }
	wanted := make([dynamic]int)
	for r, i in app.rows { if r.ticked && r.licences == nil { append(&wanted, i) } }
	if len(wanted) == 0 { delete(wanted); return }
	app.licences_asked = true
	j := new(Licences_Job)
	j.bundle, j.wanted = app.bundle, wanted[:]
	ui.task(&app.main.state, licences_work, licences_done, j, licences_lost)
}

@(private = "file")
licences_work :: proc(data: rawptr) {
	j := (^Licences_Job)(data)
	j.texts = make([][]string, len(j.wanted))
	for row, k in j.wanted {
		p := j.bundle.programs[row]
		texts := make([]string, len(p.licences))
		for l, i in p.licences {
			file, failed := bundle_read(j.bundle, l.file)
			// (a licence that cannot be read is said in its place: the person is never shown an empty licence as read)
			texts[i] = failed ? strings.clone(i18n.tr("This licence cannot be read from the bundle.")) : string(file)
		}
		j.texts[k] = texts
	}
}

@(private = "file")
licences_done :: proc(data: rawptr, _: u64) {
	j := (^Licences_Job)(data)
	app := the_app
	if app != nil && !app.closing {
		for row, k in j.wanted {
			r := &app.rows[row]
			if r.licences != nil { continue }
			r.licences, j.texts[k] = j.texts[k], nil
		}
		app.licences_asked = false
		// (a box ticked meanwhile: its licences too)
		if app.step == .Licences { licences_ask(app) }
	}
	licences_lost(j)
}

@(private = "file")
licences_lost :: proc(data: rawptr) {
	j := (^Licences_Job)(data)
	for t in j.texts {
		for s in t { delete(s) }
		delete(t)
	}
	delete(j.texts)
	delete(j.wanted)
	free(j)
}

// Whether every licence of the programs chosen is read: "Accept and install" waits for it.
licences_ready :: proc(app: ^App) -> bool {
	for r in app.rows { if r.ticked && r.licences == nil { return false } }
	return true
}

////////////////////////////////
// 4. The installs, side by side

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
