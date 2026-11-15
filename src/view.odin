package atelier

// The window's build: a header (atelier's logo, its name, the steps), the step's view in a scroll view, the step's
// buttons under it. The look is the setup dialog's (gt:setup): framed panels inside margins, buttons with a Lucide
// glyph and an intent (Primary goes on, Success installs, Neutral closes), so atelier looks like the programs it
// installs. A build reads the App and nothing else: what it shows was read by a worker.

import "core:fmt"
import "core:math"
import "core:strings"
import crash_bar "gt:crash_bar"
import "gt:draw"
import prefs_page "gt:prefs_page"
import "gt:host"
import i18n "gt:i18n"
import lucide "gt:lucide"
import "gt:platform"
import "gt:render"
import "gt:ui"

// The space on each side of the panels, in font sizes (the setup dialog's).
MARGIN_EM :: 1.5

// The height of a licence's text, of a failed install's output, in font sizes: what does not fit scrolls.
TEXT_VIEW_EM :: 12

view_build :: proc(h: ^host.Host, size: host.Vec2) {
	app := (^App)(h.user)
	em := ui.font_size()
	// (the user's themes file: a task looks at it now and then, and reads it when it changed; app_params shows it)
	if prefs_page.themes_file_poll(&app.themes_file, &h.state) { h.settle = max(h.settle, FRAMES_AFTER_INPUT) }
	// (the dialogs, the floating views, the docked ones: around the page, and over it)
	if ui.views_frame(&app.views) {
		view_keys(app)
		ui.next({width = ui.fill(), height = ui.fill(), axis = .Y})
		page := ui.build_box({.Draw_Background}, "###page")
		if ui.parent(page) { build_page(app, em) }
		actions_build(app)
		setup_build(app)
		ask_build(app)
	}
}

// The keys of the window: its actions first (the settings, the palette, the sheet, quit: in every page and over a
// dialog), then the settings' or the steps'.
@(private = "file")
view_keys :: proc(app: ^App) {
	window_keys(app)
	if ui.views_hold_keys(&app.views) { return }   // (a dialog has the keyboard)
	if app.settings_open { settings_keys(app); return }
	actions_keys(app)
}

@(private = "file")
build_page :: proc(app: ^App, em: f32) {
	title_bar(app, em)
	ui.hline(ui.fill())
	crash_bar.bar(&app.crash_bar, {name = "atelier", version = APP_VERSION, repository = "sachahjkl/atelier"})
	if app.settings_open {
		settings_build(app)
		return
	}
	ui.spacer(ui.px(em * 0.9))
	ui.next({width = ui.fill(), height = ui.fill()})
	if ui.scroll_y("###body") {
		if app.bundle == nil {
			no_bundle_view(app, em)
		} else {
			switch app.step {
			case .Welcome:    welcome_view(app, em)
			case .Programs:   programs_view(app, em)
			case .Licences, .Checking: licences_view(app, em)
			case .Installing: installing_view(app, em)
			case .Done:       done_view(app, em)
			}
		}
		ui.spacer(ui.px(em))
	}
	ui.spacer(ui.px(em * 0.5))
	buttons(app, em)
	ui.spacer(ui.px(em * 1.1))
}

////////////////////////////////
// The title bar

// The window's own title bar (the system's when window.system_title: then the system draws its buttons): atelier's mark
// and name, the steps (the one shown lit), then the update's badge, the palette, the settings and the window's
// buttons. Its empty parts move the window. In the settings, the steps give way to the way back.
@(private = "file")
title_bar :: proc(app: ^App, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(math.round(em * 2.6))})
	if ui.title_bar("###titlebar") {
		ui.spacer(ui.px(em * 0.7))
		if app.logo_size != {} {
			image(app.logo, app.logo_size, math.round(em * 1.6), "###logo")
			ui.spacer(ui.px(em * 0.5))
		}
		ui.next({width = ui.text_size(), height = ui.pct(1), text_pad = 0, font_size = math.round(em * 1.1)})
		ui.label("atelier###name")
		ui.spacer(ui.fill())
		if app.settings_open {
			if ui.tags("weak") {
				ui.next({width = ui.text_size(), height = ui.pct(1), text_pad = 0})
				ui.label(fmt.tprintf("%s###settings_title", i18n.tr("Settings")))
			}
		} else if app.bundle != nil {
			steps(app, em)
		}
		ui.spacer(ui.fill())
		// (an update to install, coming, or in place: a button before the others; nothing otherwise)
		if app.updater != nil {
			ui.next({height = ui.px(math.round(em * 1.9))})
			if prefs_page.update_badge(app.updater, proc(user: rawptr) { app_restart((^App)(user)) }, app) != nil { ui.spacer(ui.px(em * 0.4)) }
		}
		if app.settings_open {
			if bar_button("###back", lucide.ARROW_LEFT, ui.key_tip(i18n.tr("Back to the steps"), {.Escape, {}}), em) { app.settings_open = false }
		} else {
			if bar_button("###palette", lucide.COMMAND, ui.command_tip(ui.palette_command()), em) { palette_show(app) }
			ui.spacer(ui.px(em * 0.2))
			if bar_button("###settings", lucide.SETTINGS, action_tip(.Settings), em) { settings_toggle(app) }
		}
		ui.spacer(ui.px(em * 0.5))
		// (nothing when the system draws the title bar: it has its own buttons)
		if !platform.is_integrated_title(app.main.win) { ui.spacer(ui.px(em * 0.2)) }
		ui.window_buttons()
	}
}

// A small button of the title bar: a Lucide icon, its tooltip says what it does.
@(private = "file")
bar_button :: proc(id, glyph, tip: string, em: f32) -> bool {
	side := math.round(em * 2)
	ui.next({width = ui.px(side), height = ui.px(side), radius = math.round(em * 0.4)})
	return ui.button(id, icon = glyph, o = {tip = tip, icon_font = ui.lucide_icons(), quiet = true}).clicked
}

// Programs · Licences · Install: where the person is, each with its icon.
@(private = "file")
steps :: proc(app: ^App, em: f32) {
	Shown :: struct { words, glyph: string, steps: bit_set[Step] }
	shown := [3]Shown{
		{i18n.tr("Programs"), lucide.PACKAGE, {.Programs}},
		{i18n.tr("Licences"), lucide.SCALE, {.Licences, .Checking}},
		{i18n.tr("Install"), lucide.DOWNLOAD, {.Installing, .Done}},
	}
	ui.next({width = ui.children_sum(), height = ui.pct(1), axis = .X, cross = .Center})
	if ui.row(.Center, id = "###steps") {
		for s, i in shown {
			if i > 0 {
				if ui.tags("weak") {
					ui.next({width = ui.text_size(), height = ui.pct(1), text_pad = math.round(em * 0.55)})
					ui.label(fmt.tprintf("·###dot%d", i))
				}
			}
			lit := app.step in s.steps
			if ui.tags(lit ? "" : "weak") {
				tone := lit ? ui.color("accent") : ui.color("text")
				small_icon(em, s.glyph, tone)
				ui.spacer(ui.px(math.round(em * 0.3)))
				ui.next({width = ui.text_size(), height = ui.pct(1), text_pad = 0, fg = tone})
				ui.label(fmt.tprintf("%s###step%d", s.words, i))
			}
		}
	}
}

// A Lucide icon of the text's size, in `fg` (a tone's colour: ui.color("text") under a tag is that tag's text), as tall
// as a line of text: beside a paragraph it sits on its first line.
small_icon :: proc(em: f32, glyph: string, fg: ui.Color) {
	ui.next({width = ui.px(math.round(em * 1.2)), height = ui.px(math.round(em * ICON_LINE_EM)), font = ui.lucide_icons(), text_align = .Center, fg = fg, text_pad = 0})
	ui.build_box({.Draw_Text, .No_Text_Trunc}, fmt.tprintf("%s###ico%d", glyph, ui.parent_box().child_count))
}

// The height of a line of text, in font sizes: the icons beside the words have it.
ICON_LINE_EM :: 1.45

// A paragraph with an icon before its words, in the tone `tone` ("": the text's), inside a panel's margins.
@(private = "file")
icon_paragraph :: proc(em: f32, id, glyph, text, tone: string) {
	line_next()
	if ui.row(id = fmt.tprintf("%s_row", id)) {
		ui.spacer(ui.px(em * 0.9))
		if ui.tags(tone) {
			small_icon(em, glyph, ui.color("text"))
			ui.spacer(ui.px(math.round(em * 0.45)))
			ui.next({width = ui.fill(), text_pad = 0})
			ui.paragraph(fmt.tprintf("%s%s", text, id))
		}
		ui.spacer(ui.px(em * 0.9))
	}
}

////////////////////////////////
// The steps

@(private = "file")
no_bundle_view :: proc(app: ^App, em: f32) {
	if panel(em, "###nobundle") {
		ui.spacer(ui.px(em * 0.7))
		text := app.bundle_error == .Bad_Manifest ? i18n.tr("The list of programs this copy of atelier carries cannot be read: download atelier again.") : i18n.tr("This copy of atelier carries no programs: build it with ateliertool package.")
		icon_paragraph(em, "###nobundle_text", lucide.ALERT_TRIANGLE, text, "bad")
		ui.spacer(ui.px(em * 0.7))
	}
}

@(private = "file")
welcome_view :: proc(app: ^App, em: f32) {
	if panel(em, "###welcome") {
		ui.spacer(ui.px(em * 0.9))
		// atelier's mark, its name and its line: what this window is
		line_next()
		if ui.row(.Center, id = "###head") {
			ui.spacer(ui.px(em * 0.9))
			if app.logo_size != {} {
				image(app.logo, app.logo_size, math.round(em * 3), "###logo")
				ui.spacer(ui.px(em * 0.8))
			}
			ui.next({width = ui.fill(), height = ui.children_sum(), axis = .Y})
			if ui.column(id = "###words") {
				ui.next({width = ui.fill(), height = ui.px(math.round(em * 1.9)), font_size = math.round(em * 1.45), text_pad = 0})
				ui.label("atelier###name")
				if ui.tags("weak") {
					ui.next({width = ui.fill(), height = ui.px(math.round(em * 1.4)), font_size = math.round(em * 0.9), text_pad = 0})
					ui.label(fmt.tprintf("%s###line", i18n.tr("The working man's tools · by Froment Software")))
				}
			}
			ui.spacer(ui.px(em * 0.9))
		}
		ui.spacer(ui.px(em * 0.8))
		icon_paragraph(em, "###what", lucide.TOOLBOX, i18n.tr("atelier installs Froment Software's programs in one go. Choose the programs, read their licences, and each one installs itself, for you alone: no administrator is needed."), "")
		ui.spacer(ui.px(em * 0.4))
		n := len(app.bundle.programs)
		icon_paragraph(em, "###count", lucide.PACKAGE, fmt.tprintf(i18n.tr(n, "This copy carries %d program, made on %s.", "This copy carries %d programs, made on %s."), n, app.bundle.made), "weak")
		ui.spacer(ui.px(em * 0.4))
		icon_paragraph(em, "###after", lucide.REFRESH_CW, i18n.tr("Each program updates itself once it is installed."), "weak")
		ui.spacer(ui.px(em * 0.9))
	}
	ui.spacer(ui.px(em * 0.7))
	// (the programs carried: atelier is this window)
	for p, i in app.programs {
		if p.own { continue }
		r := &app.rows[i]
		line_next()
		if ui.row(.Center, id = fmt.tprintf("###welcome_%s", p.slug)) {
			ui.spacer(ui.px(em * (MARGIN_EM + 0.9)))
			program_mark(r, em * 1.6, "###mark")
			ui.spacer(ui.px(em * 0.6))
			ui.next({width = ui.text_size(), height = ui.px(math.round(em * 2)), text_pad = 0})
			ui.label(fmt.tprintf("%s###name", p.name))
			if ui.tags("weak") {
				ui.next({width = ui.fill(), height = ui.px(math.round(em * 2)), text_pad = math.round(em * 0.6)})
				ui.label(fmt.tprintf("%s###tagline", p.tagline))
			}
			ui.spacer(ui.px(em * MARGIN_EM))
		}
	}
}

@(private = "file")
programs_view :: proc(app: ^App, em: f32) {
	if app.nixos { nixos_notice(app, em) }
	if app.after_update {
		if panel(em, "###after_update") {
			ui.spacer(ui.px(em * 0.6))
			icon_paragraph(em, "###after_update_text", lucide.CHECK_CIRCLE, i18n.tr("atelier is up to date: choose what to update."), "good")
			ui.spacer(ui.px(em * 0.6))
		}
		ui.spacer(ui.px(em * 0.7))
	}
	if app.suite_version != "" { suite_banner_view(app, em) }
	line_next()
	if ui.row(.Center, id = "###select") {
		ui.spacer(ui.px(em * MARGIN_EM))
		if ui.tags("weak") {
			small_icon(em, lucide.LIST_CHECKS, ui.color("text"))
			ui.spacer(ui.px(math.round(em * 0.45)))
			ui.next({width = ui.fill(), height = ui.px(math.round(em * 2)), text_pad = 0})
			ui.label(fmt.tprintf("%s###choose", i18n.tr("Choose the programs to install.")))
		}
		// (the updater checks on its own thread: the button turns meanwhile)
		checking := app.update_phase == .Checking
		if ui.button("###check", i18n.tr("Check for updates"), lucide.REFRESH_CW, {icon_font = ui.lucide_icons(), quiet = true, disabled = !action_enabled(app, .Check_Updates) && !checking, busy = checking}).clicked { update_check_asked(app) }
		ui.spacer(ui.px(em * 0.4))
		can := app.known
		if ui.button("###all", i18n.tr("Select all"), lucide.CHECK, {icon_font = ui.lucide_icons(), quiet = true, disabled = !can}).clicked { select_all(app, true) }
		ui.spacer(ui.px(em * 0.4))
		if ui.button("###none", i18n.tr("Select none"), lucide.X, {icon_font = ui.lucide_icons(), quiet = true, disabled = !can}).clicked { select_all(app, false) }
		ui.spacer(ui.px(em * MARGIN_EM))
	}
	for p, i in app.programs {
		ui.spacer(ui.px(em * 0.45))
		program_row(app, p, &app.rows[i], em)
	}
}

// A newer suite on offer (src/md/README.md, "The suite's updates, from atelier"): what its atelier carries that is newer,
// and the button that updates atelier, then opens the new copy on this step.
@(private = "file")
suite_banner_view :: proc(app: ^App, em: f32) {
	if panel(em, "###suite") {
		ui.spacer(ui.px(em * 0.6))
		icon_paragraph(em, "###suite_text", lucide.ARROW_UP_CIRCLE, suite_banner(app.suite_version, app.suite_newer), "accent")
		ui.spacer(ui.px(em * 0.3))
		line_next()
		if ui.row(.Center, id = "###suite_buttons") {
			ui.spacer(ui.fill())
			// (the demo has no updater: its button is shown as it would be, and does nothing)
			downloading := app.update_phase == .Downloading
			disabled := !app.demo && !suite_update_possible(app) && !downloading
			if button("###suite_update", i18n.tr("Update atelier and the programs"), lucide.DOWNLOAD, .Primary, disabled, busy = downloading) { suite_update(app) }
			ui.spacer(ui.px(em * 0.9))
		}
		ui.spacer(ui.px(em * 0.6))
	}
	ui.spacer(ui.px(em * 0.7))
}

// On NixOS, Nix is the better install (it updates the programs with the system): said once, with each program's line
// for Nix and a copy button. The boxes stay: an install from here runs too.
@(private = "file")
nixos_notice :: proc(app: ^App, em: f32) {
	if panel(em, "###nixos") {
		ui.spacer(ui.px(em * 0.6))
		icon_paragraph(em, "###nixos_text", lucide.SNOWFLAKE, i18n.tr("This system is NixOS: Nix is the better install, it updates the programs with the system. Add each one with Nix, or install them from here:"), "warn")
		ui.spacer(ui.px(em * 0.3))
		for p, i in app.programs {
			// (atelier from Nix carries no programs: the line would install an empty installer)
			if p.own { continue }
			line := nix_line(p)
			if line == "" { continue }
			line_next()
			if ui.row(.Center, id = fmt.tprintf("###nix_%s", p.slug)) {
				ui.spacer(ui.px(em * 0.9))
				ui.next({width = ui.fill(), height = ui.px(math.round(em * 1.8)), text_pad = 0, font = ui.mono_font(), font_size = math.round(em * 0.9)})
				ui.label(fmt.tprintf("%s###line", line))
				copied := app.copied == i
				sig := ui.button("###copy", icon = copied ? lucide.CHECK : lucide.COPY, o = {icon_font = ui.lucide_icons(), tip = copied ? i18n.tr("Copied") : i18n.tr("Copy")})
				if sig.clicked {
					ui.window_clipboard_set(line)
					app.copied = i
				} else if copied && !sig.hovering {
					app.copied = -1   // (the check goes when the pointer leaves)
				}
				ui.spacer(ui.px(em * 0.9))
			}
		}
		ui.spacer(ui.px(em * 0.6))
	}
	ui.spacer(ui.px(em * 0.7))
}

// A program's row: its box, its logo, its name and version, its line, its state.
@(private = "file")
program_row :: proc(app: ^App, p: Program, r: ^Row, em: f32) {
	if panel(em, fmt.tprintf("###program_%s", p.slug), .X) {
		ui.spacer(ui.px(em * 0.8))
		ui.next({width = ui.px(math.round(em * 1.6)), height = ui.px(math.round(em * 2))})
		if ui.disabled(!row_choosable(app, r^)) { ui.checkbox("###box", "", &r.ticked) }
		ui.spacer(ui.px(em * 0.5))
		program_mark(r, em * 2.4, "###mark")
		ui.spacer(ui.px(em * 0.8))
		ui.next({width = ui.fill(), height = ui.children_sum(), axis = .Y})
		if ui.column(id = "###words") {
			ui.spacer(ui.px(em * 0.5))
			line_next()
			if ui.row(.Center, id = "###title") {
				ui.next({width = ui.text_size(), height = ui.px(math.round(em * 1.6)), font_size = math.round(em * 1.1), text_pad = 0})
				ui.label(fmt.tprintf("%s###name", p.name))
				if ui.tags("weak") {
					ui.next({width = ui.text_size(), height = ui.px(math.round(em * 1.6)), text_pad = math.round(em * 0.5)})
					ui.label(fmt.tprintf("%s###version", p.version))
				}
				// (the newer suite carries it at a newer version: after atelier's update)
				if available := suite_available(app.suite_newer, p.slug); available != "" {
					if ui.tags("accent") {
						small_icon(em, lucide.ARROW_UP_CIRCLE, ui.color("text"))
						ui.next({width = ui.text_size(), height = ui.px(math.round(em * 1.6)), text_pad = math.round(em * 0.2), font_size = math.round(em * 0.86)})
						ui.label(fmt.tprintf("%s###available", fmt.tprintf(i18n.tr("%s available"), available)))
					}
				}
			}
			if ui.tags("weak") {
				ui.next({width = ui.fill(), text_pad = 0})
				ui.paragraph(fmt.tprintf("%s###tagline", program_tagline(p)), selectable = false)
			}
			if r.status.state == .Unknown && r.status.reason != "" {
				if ui.tags("bad") {
					ui.next({width = ui.fill(), text_pad = 0, font_size = math.round(em * 0.86)})
					ui.paragraph(fmt.tprintf("%s###reason", r.status.reason))
				}
			}
			ui.spacer(ui.px(em * 0.5))
		}
		ui.spacer(ui.px(em * 0.6))
		state_badge(app, r^, em)
		ui.spacer(ui.px(em * 0.9))
	}
}

// The state of a program in a few words, coloured by what it means.
@(private = "file")
state_badge :: proc(app: ^App, r: Row, em: f32) {
	reading := !app.known || r.status.state == .Reading
	if reading {
		ui.spinner("###reading", math.round(em * 1.1))
		ui.spacer(ui.px(em * 0.4))
	}
	if ui.tags(state_tone(r.status.state)) {
		if !reading {
			small_icon(em, state_glyph(r.status.state), ui.color("text"))
			ui.spacer(ui.px(math.round(em * 0.3)))
		}
		ui.next({width = ui.text_size(), height = ui.px(math.round(em * 2)), text_pad = 0})
		// (the reason of Unknown is under the tagline, where it has room)
		words := r.status.state == .Unknown ? i18n.tr("Cannot be read here") : state_words(r.status)
		ui.label(fmt.tprintf("%s###state", words))
	}
}

@(private = "file")
licences_view :: proc(app: ^App, em: f32) {
	line_next()
	if ui.row(.Center, id = "###licences_intro") {
		ui.spacer(ui.px(em * MARGIN_EM))
		if ui.tags("weak") {
			small_icon(em, lucide.SCALE, ui.color("text"))
			ui.spacer(ui.px(math.round(em * 0.45)))
			ui.next({width = ui.fill(), text_pad = 0})
			ui.paragraph(fmt.tprintf("%s###text", i18n.tr("Read the licence of each program chosen, and of what it includes. Accept them to install the programs.")), selectable = false)
		}
		ui.spacer(ui.px(em * MARGIN_EM))
	}
	for p, i in app.programs {
		r := &app.rows[i]
		if !r.ticked { continue }
		ui.spacer(ui.px(em * 0.9))
		section_head(em, fmt.tprintf("###licences_%s", p.slug), fmt.tprintf("%s %s", p.name, p.version))
		if r.licences == nil {
			line_next()
			if ui.row(.Center, id = fmt.tprintf("###licences_reading_%s", p.slug)) {
				ui.spacer(ui.px(em * MARGIN_EM))
				ui.spinner("###spin")
				ui.spacer(ui.px(em * 0.5))
				if ui.tags("weak") {
					ui.next({width = ui.fill(), height = ui.px(math.round(em * 2)), text_pad = 0})
					ui.label(fmt.tprintf("%s###text", i18n.tr("Reading the licences…")))
				}
			}
			continue
		}
		if len(p.licences) == 0 {
			ui.spacer(ui.px(em * 0.4))
			line_next()
			if ui.row(id = fmt.tprintf("###licences_none_%s", p.slug)) {
				ui.spacer(ui.px(em * MARGIN_EM))
				icon_paragraph(em, "###text", lucide.ALERT_TRIANGLE, i18n.tr("This program carries no licence file."), "warn")
			}
			continue
		}
		for l, k in p.licences {
			if k >= len(r.licences) { break }
			ui.spacer(ui.px(em * 0.4))
			line_next()
			if ui.row(.Center, id = fmt.tprintf("###licence_title_%s_%d", p.slug, k)) {
				ui.spacer(ui.px(em * MARGIN_EM))
				if ui.tags("weak") {
					small_icon(em, lucide.FILE_TEXT, ui.color("text"))
					ui.spacer(ui.px(math.round(em * 0.35)))
					ui.next({width = ui.fill(), height = ui.px(math.round(em * 1.6)), text_pad = 0})
					ui.label(fmt.tprintf("%s###title", l.title))
				}
			}
			text_view(em, fmt.tprintf("###licence_%s_%d", p.slug, k), r.licences[k])
		}
	}
}

@(private = "file")
installing_view :: proc(app: ^App, em: f32) {
	done, of := installed_count(app)
	if panel(em, "###progress") {
		ui.spacer(ui.px(em * 0.7))
		line_next()
		if ui.row(.Center, id = "###count_row") {
			ui.spacer(ui.px(em * 0.9))
			small_icon(em, lucide.DOWNLOAD, ui.color("text"))
			ui.spacer(ui.px(math.round(em * 0.45)))
			ui.next({width = ui.fill(), height = ui.px(math.round(em * 1.8)), text_pad = 0})
			ui.label(fmt.tprintf("%s###count", fmt.tprintf(i18n.tr("Installing: %d of %d done"), done, of)))
			ui.spacer(ui.px(em * 0.9))
		}
		line_next()
		if ui.row(.Center, id = "###bar_row") {
			ui.spacer(ui.px(em * 0.9))
			ui.next({width = ui.fill(), height = ui.px(math.round(em * 0.5))})
			ui.progress("###bar", install_fraction(app))
			ui.spacer(ui.px(em * 0.9))
		}
		ui.spacer(ui.px(em * 0.5))
		icon_paragraph(em, "###note", lucide.INFO, i18n.tr("The programs install themselves side by side. If you close the window, those under way end their install first."), "weak")
		ui.spacer(ui.px(em * 0.7))
	}
	for p, i in app.programs {
		r := &app.rows[i]
		if r.result == .None { continue }
		ui.spacer(ui.px(em * 0.45))
		if panel(em, fmt.tprintf("###installing_%s", p.slug), .X) {
			ui.spacer(ui.px(em * 0.9))
			program_mark(r, em * 2, "###mark")
			ui.spacer(ui.px(em * 0.7))
			ui.next({width = ui.px(math.round(em * 12)), height = ui.px(math.round(em * 3.6)), text_pad = 0})
			ui.label(fmt.tprintf("%s %s###name", p.name, p.version))
			steps := install_steps(r^, p.own)
			ui.next({width = ui.fill()})
			ui.stepper("###phases", steps[:])
			if r.result == .Failed {
				ui.spacer(ui.px(em * 0.6))
				retry_button(app, i, r^, em)
			}
			ui.spacer(ui.px(em * 0.9))
		}
	}
}

// A failed row's Retry: its whole way again. Its tooltip says why it failed (the Done step shows the whole output).
@(private = "file")
retry_button :: proc(app: ^App, index: int, r: Row, em: f32) {
	tip := r.output
	if nl := strings.index_byte(tip, '\n'); nl >= 0 { tip = tip[:nl] }
	o := ui.Button_Options{icon_font = ui.lucide_icons(), tip = tip, disabled = app.look != .Idle}
	if ui.button("###retry", i18n.tr("Retry"), lucide.ROTATE_CCW, o).clicked { retry(app, {index}) }
}

// The phases of a program's install as its stepper shows them: those before the phase under way done, that one turning
// (or failed), those after it pending. Close is skipped when no copy ran (`Row.close`). atelier's own (`own`) takes
// nothing out and never runs beside itself: its Close and Unpack are skipped, not done, and its Install is a copy of
// the running file.
install_steps :: proc(r: Row, own := false) -> [len(Install_Phase)]ui.Stepper_Step {
	steps: [len(Install_Phase)]ui.Stepper_Step
	started := r.result == .Installing || r.result == .Installed || r.result == .Failed
	for phase in Install_Phase {
		s := &steps[int(phase)]
		switch phase {
		case .Close:   s.label = i18n.tr("Close")
		case .Unpack:  s.label = i18n.tr("Unpack")
		case .Install: s.label = own ? i18n.tr("Copy") : i18n.tr("Install")
		case .Check:   s.label = i18n.tr("Check")
		}
		// (known once the install started: before, the look has not said whether a copy runs)
		skipped := (phase == .Close && (own || !r.close)) || (own && phase == .Unpack)
		if skipped && started {
			s.state = .Skipped
			continue
		}
		switch r.result {
		case .None, .Waiting, .Retrying: s.state = .Pending
		case .Installed:      s.state = .Done
		case .Installing, .Failed:
			switch {
			case phase < r.phase:  s.state = .Done
			case phase > r.phase:  s.state = r.result == .Failed ? .Skipped : .Pending
			case r.result == .Failed: s.state, s.detail = .Failed, i18n.tr("Failed")
			case:                  s.state = .Active
			}
		}
	}
	return steps
}

// How far the installs are, phase by phase: a program done or failed counts whole.
@(private = "file")
install_fraction :: proc(app: ^App) -> f32 {
	sum, of := 0, 0
	for r in app.rows {
		if r.result == .None { continue }
		of += len(Install_Phase)
		switch r.result {
		case .None, .Waiting, .Retrying:
		case .Installing:             sum += int(r.phase)
		case .Installed, .Failed:     sum += len(Install_Phase)
		}
	}
	return of > 0 ? f32(sum) / f32(of) : 0
}

// Waiting, installing (a spinner), installed (a check), failed (a cross), and its words.
@(private = "file")
result_mark :: proc(result: Result, em: f32) {
	words, tone, glyph: string
	switch result {
	case .None, .Waiting, .Retrying: words, tone = i18n.tr("Waiting"), "weak"
	case .Installing:     words, tone = i18n.tr("Installing…"), ""
	case .Installed:      words, tone, glyph = i18n.tr("Installed"), "good", lucide.CHECK
	case .Failed:         words, tone, glyph = i18n.tr("Failed"), "bad", lucide.X
	}
	ui.next({width = ui.children_sum(), height = ui.px(math.round(em * 2)), axis = .X, cross = .Center})
	if ui.row(.Center, id = "###result") {
		if ui.tags(tone) {
			if result == .Installing {
				ui.spinner("###spin", math.round(em * 1.1))
				ui.spacer(ui.px(em * 0.4))
			} else if glyph != "" {
				ui.icon(glyph, math.round(em * 1.4), ui.color("text"), ui.lucide_icons())
			}
			ui.next({width = ui.text_size(), height = ui.pct(1), text_pad = 0})
			ui.label(fmt.tprintf("%s###words", words))
		}
	}
}

// atelier's own row of the Done step, in place of Open: where the person finds it again.
@(private = "file")
own_installed_mark :: proc(em: f32) {
	ui.next({width = ui.children_sum(), height = ui.px(math.round(em * 2)), axis = .X, cross = .Center})
	if ui.row(.Center, id = "###own_result") {
		if ui.tags("good") {
			ui.icon(lucide.CHECK, math.round(em * 1.4), ui.color("text"), ui.lucide_icons())
			ui.spacer(ui.px(math.round(em * 0.3)))
			ui.next({width = ui.text_size(), height = ui.pct(1), text_pad = 0})
			ui.label(fmt.tprintf("%s###words", i18n.tr("Installed: it is in the applications menu")))
		}
	}
}

// A program's line: atelier's own is translated (its words are the program's), a carried program's is its bundle's.
program_tagline :: proc(p: Program) -> string {
	return p.own ? i18n.tr(p.tagline) : p.tagline
}

@(private = "file")
done_view :: proc(app: ^App, em: f32) {
	installed, failed := 0, 0
	for r in app.rows {
		if r.result == .Installed { installed += 1 }
		if r.result == .Failed { failed += 1 }
	}
	if panel(em, "###summary") {
		ui.spacer(ui.px(em * 0.7))
		text := failed == 0 ? fmt.tprintf(i18n.tr(installed, "Done: %d program is installed.", "Done: %d programs are installed."), installed) : fmt.tprintf(i18n.tr("%d installed, %d failed."), installed, failed)
		icon_paragraph(em, "###summary_text", failed == 0 ? lucide.CHECK_CIRCLE : lucide.ALERT_CIRCLE, text, failed == 0 ? "good" : "bad")
		ui.spacer(ui.px(em * 0.3))
		icon_paragraph(em, "###menu", lucide.INFO, i18n.tr("Each one is in the applications menu, and updates itself."), "weak")
		ui.spacer(ui.px(em * 0.7))
	}
	for p, i in app.programs {
		r := &app.rows[i]
		if r.result != .Installed && r.result != .Failed { continue }
		ui.spacer(ui.px(em * 0.45))
		if panel(em, fmt.tprintf("###done_%s", p.slug)) {
			line_next()
			if ui.row(.Center, id = "###head") {
				ui.spacer(ui.px(em * 0.9))
				program_mark(r, em * 2, "###mark")
				ui.spacer(ui.px(em * 0.7))
				ui.next({width = ui.fill(), height = ui.children_sum(), axis = .Y})
				if ui.column(id = "###words") {
					ui.spacer(ui.px(em * 0.5))
					ui.next({width = ui.fill(), height = ui.px(math.round(em * 1.6)), text_pad = 0})
					ui.label(fmt.tprintf("%s %s###name", p.name, p.version))
					if r.result == .Installed && r.status.program != "" {
						if ui.tags("weak") {
							ui.next({width = ui.fill(), height = ui.px(math.round(em * 1.4)), axis = .X, cross = .Center})
							if ui.row(.Center, id = "###where_row") {
								ui.next({width = ui.px(math.round(em * 1.1)), height = ui.pct(1), font = ui.lucide_icons(), text_align = .Center, font_size = math.round(em * 0.86), text_pad = 0})
								ui.build_box({.Draw_Text, .No_Text_Trunc}, fmt.tprintf("%s###where_icon", lucide.FOLDER))
								ui.spacer(ui.px(math.round(em * 0.3)))
								ui.next({width = ui.fill(), height = ui.pct(1), text_pad = 0, font = ui.mono_font(), font_size = math.round(em * 0.86)})
								ui.label(fmt.tprintf("%s###where", r.status.program))
							}
						}
					}
					ui.spacer(ui.px(em * 0.5))
				}
				if r.result == .Installed && p.own {
					// (atelier is open: an Open would start a second one, which hands itself over to this window)
					own_installed_mark(em)
				} else if r.result == .Installed {
					if ui.button("###open", i18n.tr("Open"), lucide.PLAY, {icon_font = ui.lucide_icons(), intent = .Success, disabled = r.status.program == ""}).clicked {
						open_program(app, r.status.program)
					}
				} else {
					result_mark(r.result, em)
					ui.spacer(ui.px(em * 0.6))
					retry_button(app, i, r^, em)
				}
				ui.spacer(ui.px(em * 0.9))
			}
			if r.result == .Failed && r.output != "" {
				ui.spacer(ui.px(em * 0.2))
				line_next()
				if ui.row(id = "###output_row") {
					ui.spacer(ui.px(em * 0.9))
					ui.next({width = ui.fill(), height = ui.children_sum(), axis = .Y})
					if ui.column(id = "###output_column") { text_view(em, "###output", r.output, margins = false) }
					ui.spacer(ui.px(em * 0.9))
				}
				ui.spacer(ui.px(em * 0.7))
			}
		}
	}
}

////////////////////////////////
// The buttons

// Back on the left; on the right, Close and what goes on. Installing has none: an install that started ends.
@(private = "file")
buttons :: proc(app: ^App, em: f32) {
	if app.step == .Installing && app.bundle != nil { return }
	ui.next({width = ui.fill(), height = ui.children_sum(), axis = .X, cross = .Center})
	if ui.row(.Center, id = "###buttons") {
		ui.spacer(ui.px(em * MARGIN_EM))
		if app.bundle != nil && (app.step == .Programs || app.step == .Licences) {
			if button("###back", i18n.tr("Back"), lucide.ARROW_LEFT, .Neutral) { app_step(app, .Back) }
		}
		ui.spacer(ui.fill())
		if button("###close", i18n.tr("Close"), lucide.X, .Neutral) { platform.request_close(app.main.win) }
		if app.bundle != nil {
			#partial switch app.step {
			case .Welcome:
				ui.spacer(ui.px(em * 0.5))
				if button("###next", i18n.tr("Choose the programs"), lucide.ARROW_RIGHT, .Primary, len(app.rows) == 0) { app_step(app, .Next) }
			case .Programs:
				ui.spacer(ui.px(em * 0.5))
				if button("###next", i18n.tr("Next"), lucide.ARROW_RIGHT, .Primary, chosen_count(app) == 0) { app_step(app, .Next) }
			case .Licences:
				ui.spacer(ui.px(em * 0.5))
				if button("###install", i18n.tr("Accept and install"), lucide.DOWNLOAD, .Success, !licences_ready(app) || chosen_count(app) == 0) { app_step(app, .Next) }
			case .Checking:
				// (the look for the programs that run, then its question: the button itself waits)
				ui.spacer(ui.px(em * 0.5))
				button("###install", i18n.tr("Accept and install"), lucide.DOWNLOAD, .Success, busy = true)
			case .Done:
				if action_enabled(app, .Retry_Failed) {
					ui.spacer(ui.px(em * 0.5))
					if button("###retry_failed", i18n.tr("Retry the failed ones"), lucide.ROTATE_CCW, .Primary) { retry_failed(app) }
				}
			}
		}
		ui.spacer(ui.px(em * MARGIN_EM))
	}
}

// A button of the steps. `busy`: its act is under way, the spinner in its glyph's place (the toolkit's busy button).
@(private = "file")
button :: proc(id, label, glyph: string, intent: ui.Intent, disabled := false, busy := false) -> bool {
	return ui.button(id, label, glyph, {icon_font = ui.lucide_icons(), intent = intent, disabled = disabled, busy = busy}).clicked
}

////////////////////////////////
// Building blocks

// A framed panel across the window, inside its margins: `if panel(...) { ... }` (the setup dialog's).
@(private = "file", deferred_none = panel_end)
panel :: proc(em: f32, id: string, axis := ui.Axis.Y) -> bool {
	ui.next({width = ui.fill(), height = ui.children_sum(), axis = .X})
	ui.push_parent(ui.build_box({}, fmt.tprintf("%s_line", id)))
	ui.spacer(ui.px(em * MARGIN_EM))
	ui.next({width = ui.fill(), height = ui.children_sum(), axis = axis, cross = .Center, radius = math.round(em * 0.4)})
	box: ^ui.Box
	if ui.tags("input") { box = ui.build_box({.Draw_Background, .Draw_Border}, id) }
	ui.push_parent(box)
	return true
}

@(private = "file")
panel_end :: proc() {
	ui.pop_parent()
	ui.spacer(ui.px(ui.font_size() * MARGIN_EM))
	ui.pop_parent()
}

// A line of the window: as wide as it, as tall as what it holds.
@(private = "file")
line_next :: proc() {
	ui.next({width = ui.fill(), height = ui.children_sum(), axis = .X, cross = .Center})
}

// A paragraph inside a panel, with the panel's inner margins, in the tone `tone` ("": the text's).
@(private = "file")
padded_paragraph :: proc(em: f32, id, text, tone: string) {
	line_next()
	if ui.row(id = fmt.tprintf("%s_row", id)) {
		ui.spacer(ui.px(em * 0.9))
		if ui.tags(tone) {
			ui.next({width = ui.fill(), text_pad = 0})
			ui.paragraph(fmt.tprintf("%s%s", text, id))
		}
		ui.spacer(ui.px(em * 0.9))
	}
}

// A section's head: the accent's bar, then its title.
@(private = "file")
section_head :: proc(em: f32, id, title: string) {
	line_next()
	if ui.row(.Center, id = id) {
		ui.spacer(ui.px(em * MARGIN_EM))
		ui.next({width = ui.px(max(math.round(em * 0.22), 2)), height = ui.px(math.round(em * 1.7)), bg = ui.color("accent")})
		ui.build_box({.Draw_Background}, "###bar")
		ui.spacer(ui.px(em * 0.7))
		ui.next({width = ui.fill(), height = ui.px(math.round(em * 1.7)), text_pad = 0, font_size = math.round(em * 1.1)})
		ui.label(fmt.tprintf("%s###title", title))
		ui.spacer(ui.px(em * MARGIN_EM))
	}
}

// A long text (a licence, an install's output) in a framed view of its own, monospace: what does not fit scrolls.
@(private = "file")
text_view :: proc(em: f32, id, text: string, margins := true) {
	line_next()
	if ui.row(id = fmt.tprintf("%s_line", id)) {
		if margins { ui.spacer(ui.px(em * MARGIN_EM)) }
		ui.next({width = ui.fill(), height = ui.px(math.round(em * TEXT_VIEW_EM)), axis = .X, radius = math.round(em * 0.3)})
		well: ^ui.Box
		if ui.tags("input") { well = ui.build_box({.Draw_Background, .Draw_Border}, fmt.tprintf("%s_well", id)) }
		if ui.parent(well) {
			ui.spacer(ui.px(em * 0.6))
			ui.next({width = ui.fill(), height = ui.pct(1)})
			if ui.scroll_y(fmt.tprintf("%s_scroll", id)) {
				ui.spacer(ui.px(em * 0.4))
				ui.next({width = ui.fill(), text_pad = 0, font = ui.mono_font(), font_size = math.round(em * 0.86)})
				ui.paragraph(fmt.tprintf("%s###text", text))
				ui.spacer(ui.px(em * 0.4))
			}
			ui.spacer(ui.px(em * 0.6))
		}
		if margins { ui.spacer(ui.px(em * MARGIN_EM)) }
	}
}

// A program's logo `side` across (an empty square while it is not made yet, or when the bundle has none).
@(private = "file")
program_mark :: proc(r: ^Row, side: f32, id: string) {
	if r.logo_size == {} {
		ui.spacer(ui.px(math.round(side)))
		return
	}
	image(r.logo, r.logo_size, math.round(side), id)
}

@(private = "file")
Image :: struct {
	texture: render.Texture,
	size:    [2]f32,
}

// A picture `side` across, its proportions kept.
@(private = "file")
image :: proc(texture: render.Texture, size: [2]f32, side: f32, id: string) {
	ui.next({width = ui.px(side), height = ui.px(side)})
	b := ui.build_box({}, id)
	p := ui.frame_new(Image)
	p^ = {texture, size}
	b.custom, b.custom_user = image_draw, p
}

@(private = "file")
image_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	img := (^Image)(user)
	r := b.rect
	room := r.max - r.min
	if img.size.x <= 0 || img.size.y <= 0 || room.x <= 0 { return }
	scale := min(room.x / img.size.x, room.y / img.size.y)
	sz := img.size * scale
	at := r.min + (room - sz) * 0.5
	draw.image(dc, img.texture, {at, at + sz})
}

////////////////////////////////
// The words of a state

// The state of a program in a few words (the window's badge, `atelier list`).
state_words :: proc(s: Status) -> string {
	switch s.state {
	case .Reading: return i18n.tr("Reading…")
	case .Absent:  return i18n.tr("Not installed")
	case .Older:   return fmt.tprintf(i18n.tr("Update from %s"), s.installed)
	case .Current: return i18n.tr("Installed")
	case .Newer:   return fmt.tprintf(i18n.tr("%s installed"), s.installed)
	case .Repair:  return i18n.tr("Repair")
	case .Unknown: return s.reason != "" ? fmt.tprintf(i18n.tr("Cannot be read here: %s"), s.reason) : i18n.tr("Cannot be read here")
	}
	return ""
}

// The icon before a state's words.
@(private = "file")
state_glyph :: proc(s: State) -> string {
	switch s {
	case .Reading: return lucide.LOADER
	case .Absent:  return lucide.CIRCLE_DASHED
	case .Older:   return lucide.ARROW_UP_CIRCLE
	case .Current: return lucide.CHECK_CIRCLE
	case .Newer:   return lucide.CHECK
	case .Repair:  return lucide.WRENCH
	case .Unknown: return lucide.ALERT_TRIANGLE
	}
	return ""
}

// The theme's tag of a state's words.
@(private = "file")
state_tone :: proc(s: State) -> string {
	switch s {
	case .Reading, .Absent, .Newer: return "weak"
	case .Older:                    return ""
	case .Current:                  return "good"
	case .Repair:                   return "warn"
	case .Unknown:                  return "bad"
	}
	return ""
}
