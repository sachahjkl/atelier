package atelier

// The window's build: a header (atelier's logo, its name, the steps), the step's view in a scroll view, the step's
// buttons under it. One level of framing (src/md/README.md, "The layout"): a group is one card, a list is one card of
// rows split by hairlines, and nothing framed sits in a card. Every gap and inset is a step of the toolkit's spacing
// scale, through its role (ui.space(ui.CARD_PAD)...); the cards, the list cards and the wells are the toolkit's.
// Buttons have a Lucide glyph and an intent (Primary goes on, Success installs, Neutral closes), as in the programs
// atelier installs. A build reads the App and nothing else: what it shows was read by a worker.

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
import timefmt "gt:timefmt"
import "gt:ui"

// The roundness of a well, in font sizes: the toolkit's cards' (ui.card), so a well on the page matches them.
WELL_RADIUS_EM :: f32(0.6)

// The side of a program's mark in a row, in font sizes.
MARK_EM :: f32(2)

// The height of a licence's text, in font sizes: what does not fit scrolls.
TEXT_VIEW_EM :: 12

view_build :: proc(h: ^host.Host, size: host.Vec2) {
	app := (^App)(h.user)
	em := ui.font_size()
	// (the user's themes file: a task looks at it now and then, and reads it when it changed; app_params shows it)
	if prefs_page.themes_file_poll(&app.themes_file, &h.state) { host.host_settle(h) }
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
	crash_bar.bar(&app.crash_bar, {name = APP_TITLE, version = APP_VERSION, repository = "sachahjkl/atelier"})
	if app.settings_open {
		settings_build(app)
		return
	}
	ui.next({width = ui.fill(), height = ui.fill()})
	if ui.scroll_y("###body") {
		body := ui.parent_box()
		bar_room := ui.scrollbar_room(body, .X)
		// (the page's top inset is in the scroll view: at rest it is empty, so the fade at the edges where content hides
		// covers nothing until the body scrolls. Under the window's bar it is no role: the toolkit's bare step)
		ui.scroll_fades(body, .Y, math.round(em * ui.SPACE_4))
		ui.space(ui.SPACE_4)
		line_next()
		if ui.row(id = "###margins") {
			ui.space(ui.PAGE_MARGIN)
			ui.next({width = ui.fill(), height = ui.children_sum(), axis = .Y})
			if ui.column(id = "###step") {
				if app.bundle == nil {
					no_bundle_view(app, em)
				} else {
					switch app.step {
					case .Welcome:    welcome_view(app, em)
					case .Programs:   programs_view(app, em)
					case .Licences, .Checking: licences_view(app, em)
					case .Installing: installing_view(app, em)
					}
				}
			}
			// (the scroll bar sits in the right margin, so the cards end where the bottom buttons end whether the body
			// scrolls or not; a hand-made gap, as it is the margin less the bar)
			ui.spacer(ui.px(max(0, math.round(em * ui.PAGE_MARGIN) - bar_room)))
		}
		// (the last card's edge never touches the scroll view's)
		ui.space(ui.SPACE_4)
	}
	buttons(app)
	ui.space(ui.PAGE_MARGIN)
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
		ui.space(ui.SPACE_3)
		if app.logo_size != {} {
			image(app.logo, app.logo_size, math.round(em * 1.6), "###logo")
			ui.space(ui.ICON_GAP)
		}
		ui.next({width = ui.text_size(), height = ui.pct(1), text_pad = 0, font_size = math.round(em * 1.1)})
		ui.label(APP_TITLE + "###name")
		// (the middle, centred in what the name and the buttons leave: a share that asks for no width (.Fits_Width), so
		// a narrow window cuts the steps and keeps the window's buttons in it)
		ui.next({width = ui.fill(), height = ui.pct(1)})
		if ui.row(.Center, {.Clip, .Fits_Width}, "###middle") {
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
		}
		// (an update to install, coming, or in place: a button before the others; nothing otherwise)
		if app.updates.updater != nil {
			ui.next({height = ui.px(math.round(em * 1.9))})
			if prefs_page.update_badge(app.updates.updater, proc(user: rawptr) { app_restart((^App)(user)) }, app) != nil { ui.space(ui.CONTROL_GAP) }
		}
		if app.settings_open {
			if bar_button("###back", lucide.ARROW_LEFT, ui.key_tip(i18n.tr("Back to the steps"), {.Escape, {}}), em) { app.settings_open = false }
		} else {
			if bar_button("###palette", lucide.COMMAND, ui.command_tip(ui.palette_command()), em) { palette_show(app) }
			ui.space(ui.TOOL_GAP)
			if bar_button("###settings", lucide.SETTINGS, action_tip(.Settings), em) { settings_toggle(app) }
		}
		// (the window's buttons: their own gap; nothing when the system draws the title bar, with its own buttons)
		ui.space(platform.is_integrated_title(app.main.win) ? ui.CONTROL_GAP : ui.SPACE_3)
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
		{i18n.tr("Install"), lucide.DOWNLOAD, {.Installing}},
	}
	ui.next({width = ui.children_sum(), height = ui.pct(1), axis = .X, cross = .Center})
	if ui.row(.Center, id = "###steps") {
		for s, i in shown {
			if i > 0 {
				if ui.tags("weak") {
					ui.next({width = ui.text_size(), height = ui.pct(1), text_pad = math.round(em * ui.SPACE_3)})
					ui.label(fmt.tprintf("·###dot%d", i))
				}
			}
			lit := app.step in s.steps
			if ui.tags(lit ? "" : "weak") {
				tone := lit ? ui.color("accent") : ui.color("text")
				small_icon(em, s.glyph, tone)
				ui.space(ui.SPACE_1)
				ui.next({width = ui.text_size(), height = ui.pct(1), text_pad = 0, fg = tone})
				ui.label(fmt.tprintf("%s###step%d", s.words, i))
			}
		}
	}
}

// A Lucide icon of the text's size, in `fg` (a tone's colour: ui.color("text") under a tag is that tag's text), as tall
// as a line of text: beside a paragraph it sits on its first line.
small_icon :: proc(em: f32, glyph: string, fg: ui.Color) {
	ui.next({width = ui.px(math.round(em * ICON_EM)), height = ui.px(math.round(em * ICON_LINE_EM)), font = ui.lucide_icons(), text_align = .Center, fg = fg, text_pad = 0})
	ui.build_box({.Draw_Text, .No_Text_Trunc}, fmt.tprintf("%s###ico%d", glyph, ui.parent_box().child_count))
}

// The width of an icon's cell, and the height of a line of text, in font sizes: the icons beside the words have it.
ICON_EM :: 1.2
ICON_LINE_EM :: 1.45

// A paragraph with an icon before its words, in the tone `tone` ("": the text's), its icon on its first line.
@(private = "file")
icon_paragraph :: proc(em: f32, id, glyph, text, tone: string) {
	line_next()
	if ui.row(id = fmt.tprintf("%s_row", id)) {
		if ui.tags(tone) {
			small_icon(em, glyph, ui.color("text"))
			ui.space(ui.ICON_GAP)
			ui.next({width = ui.fill(), text_pad = 0})
			ui.paragraph(fmt.tprintf("%s%s", text, id))
		}
	}
}

////////////////////////////////
// The steps

@(private = "file")
no_bundle_view :: proc(app: ^App, em: f32) {
	if ui.card("", id = "###nobundle") {
		text := app.bundle_error == .Bad_Manifest ? i18n.tr("The list of programs this copy of Atelier carries cannot be read: download Atelier again.") : i18n.tr("This copy of Atelier carries no programs: build it with ateliertool package.")
		icon_paragraph(em, "###nobundle_text", lucide.ALERT_TRIANGLE, text, "bad")
	}
}

// "By <mark> Froment Software", as the setup's dialog and the foot of the site say it: the vendor's name opens its site.
// (the setup's own line is the toolkit's and private: this one keeps its sizes)
@(private = "file")
by_line :: proc(app: ^App, em: f32) {
	line := math.round(em * 1.35)
	size := math.round(em * 0.9)
	ui.next({width = ui.fill(), height = ui.px(line), axis = .X, cross = .Center})
	if ui.row(id = "###by") {
		if ui.tags("weak") {
			ui.next({width = ui.text_size(), height = ui.px(line), font_size = size, text_pad = 0})
			ui.label(fmt.tprintf("%s###by_word", i18n.tr("By")))
		}
		ui.space(ui.SPACE_1)
		if mark, has := app.install.vendor_mark.?; has {
			image(mark.texture, mark.size, math.round(em * 0.95), "###by_mark")
			ui.space(ui.SPACE_1)
		}
		ui.next({font_size = size})
		if ui.button("###by_name", VENDOR, o = {face = .Link, height = line, tip = VENDOR_URL}).clicked { ui.open(VENDOR_URL, .Url) }
	}
}

// What atelier is, on the page itself (no frame: it is the page's head), then the programs it carries in one list.
@(private = "file")
welcome_view :: proc(app: ^App, em: f32) {
	// atelier's mark, its name and its line: what this window is
	line_next()
	if ui.row(.Center, id = "###head") {
		if app.logo_size != {} {
			image(app.logo, app.logo_size, math.round(em * 3), "###logo")
			ui.space(ui.SPACE_4)
		}
		ui.next({width = ui.fill(), height = ui.children_sum(), axis = .Y})
		if ui.column(id = "###words") {
			ui.next({width = ui.fill(), height = ui.px(math.round(em * 1.9)), font_size = math.round(em * 1.45), text_pad = 0})
			ui.label(APP_TITLE + "###name")
			if ui.tags("weak") {
				ui.next({width = ui.fill(), height = ui.px(math.round(em * 1.4)), font_size = math.round(em * 0.9), text_pad = 0})
				ui.label(fmt.tprintf("%s###line", i18n.tr("The working man's tools")))
			}
			by_line(app, em)
		}
	}
	// (the head says what atelier is and who makes it; the steps show the rest: no paragraph says it again)
	ui.space(ui.GROUP_GAP)
	// (the programs carried, under their count: atelier is this window)
	n := len(app.bundle.programs)
	// (when it was made, as a person says it, in local time: "today 18:42", "Nov 10, 18:42". The clock's offset is the
	// toolkit's watch, read without a system call; "now" is atelier's start)
	count: string
	if app.bundle.made_ms > 0 {
		made := timefmt.moment(f64(app.bundle.made_ms), f64(app.started_ms), timefmt.local_offset_minutes(), {})
		count = fmt.tprintf(i18n.tr(n, "This copy carries %d program, made %s.", "This copy carries %d programs, made %s."), n, made)
	} else {
		count = fmt.tprintf(i18n.tr(n, "This copy carries %d program.", "This copy carries %d programs."), n)
	}
	icon_paragraph(em, "###count", lucide.PACKAGE, count, "weak")
	ui.space(ui.LINE_GAP)
	if ui.list_card("###welcome_list") {
		for p, i in app.programs {
			if p.own { continue }
			if ui.card_row(fmt.tprintf("###welcome_%s", p.slug)) {
				program_mark(&app.rows[i], em * MARK_EM, "###mark")
				ui.space(ui.SPACE_3)
				ui.next({width = ui.text_size(), height = ui.px(math.round(em * MARK_EM)), text_pad = 0})
				ui.label(fmt.tprintf("%s###name", p.name))
				ui.space(ui.SPACE_3)
				if ui.tags("weak") {
					ui.next({width = ui.fill(), height = ui.px(math.round(em * MARK_EM)), text_pad = 0})
					ui.label(fmt.tprintf("%s###tagline", p.tagline))
				}
			}
		}
	}
}

@(private = "file")
programs_view :: proc(app: ^App, em: f32) {
	if app.nixos { nixos_notice(app, em) }
	if app.after_update {
		if ui.card("", id = "###after_update") {
			icon_paragraph(em, "###after_update_text", lucide.CHECK_CIRCLE, i18n.tr("Atelier is up to date: choose what to update."), "good")
		}
		ui.space(ui.GROUP_GAP)
	}
	if app.suite_version != "" { suite_banner_view(app, em) }
	// the list's head: what to do, and the buttons that act on the whole list
	line_next()
	if ui.row(.Center, id = "###select") {
		// (no words before the buttons: the step and the boxes say what to do)
		ui.spacer(ui.fill())
		// (the updater checks on its own thread: the button turns meanwhile)
		checking := app.update_phase == .Checking
		if ui.button("###check", i18n.tr("Check for updates"), lucide.REFRESH_CW, {icon_font = ui.lucide_icons(), quiet = true, disabled = !action_enabled(app, .Check_Updates) && !checking, busy = checking}).clicked { update_check_asked(app) }
		ui.space(ui.CONTROL_GAP)
		can := app.known
		if ui.button("###all", i18n.tr("Select all"), lucide.CHECK, {icon_font = ui.lucide_icons(), quiet = true, disabled = !can}).clicked { select_all(app, true) }
		ui.space(ui.CONTROL_GAP)
		if ui.button("###none", i18n.tr("Select none"), lucide.X, {icon_font = ui.lucide_icons(), quiet = true, disabled = !can}).clicked { select_all(app, false) }
	}
	ui.space(ui.LINE_GAP)
	if ui.list_card("###programs") {
		for p, i in app.programs {
			program_row(app, p, &app.rows[i], em)
		}
	}
}

// A newer suite on offer (src/md/README.md, "The suite's updates, from atelier"): what its atelier carries that is newer,
// and at its end the button that updates atelier, then opens the new copy on this step.
@(private = "file")
suite_banner_view :: proc(app: ^App, em: f32) {
	if ui.card("", id = "###suite") {
		line_next()
		if ui.row(.Center, id = "###suite_row") {
			ui.next({width = ui.fill(), height = ui.children_sum(), axis = .Y})
			if ui.column(id = "###suite_words") {
				icon_paragraph(em, "###suite_text", lucide.ARROW_UP_CIRCLE, suite_banner(app.suite_version, app.suite_newer), "accent")
			}
			ui.space(ui.CONTROL_GAP)
			// (the demo has no updater: its button is shown as it would be, and does nothing)
			downloading := app.update_phase == .Downloading
			disabled := !app.demo && !suite_update_possible(app) && !downloading
			if button("###suite_update", i18n.tr("Update Atelier and the programs"), lucide.DOWNLOAD, .Primary, disabled, busy = downloading) { suite_update(app) }
		}
	}
	ui.space(ui.GROUP_GAP)
}

// On NixOS, Nix is the better install (it updates the programs with the system): said once, with each program's line
// for Nix and a copy button, under the words and aligned with them. The boxes stay: an install from here runs too.
@(private = "file")
nixos_notice :: proc(app: ^App, em: f32) {
	if ui.card("", id = "###nixos") {
		icon_paragraph(em, "###nixos_text", lucide.SNOWFLAKE, i18n.tr("This system is NixOS: Nix is the better install, it updates the programs with the system. Add each one with Nix, or install them from here:"), "warn")
		ui.space(ui.LINE_GAP)
		for p, i in app.programs {
			// (atelier from Nix carries no programs: the line would install an empty installer)
			if p.own { continue }
			line := nix_line(p)
			if line == "" { continue }
			line_next()
			if ui.row(.Center, id = fmt.tprintf("###nix_%s", p.slug)) {
				ui.spacer(ui.px(math.round(em * ICON_EM) + math.round(em * ui.ICON_GAP)))
				ui.next({width = ui.fill(), height = ui.px(math.round(em * 1.8)), text_pad = 0, font = ui.mono_font(), font_size = math.round(em * 0.9)})
				ui.label(fmt.tprintf("%s###line", line))
				ui.space(ui.CONTROL_GAP)
				copied := app.copied == i
				sig := ui.button("###copy", icon = copied ? lucide.CHECK : lucide.COPY, o = {icon_font = ui.lucide_icons(), tip = copied ? i18n.tr("Copied") : i18n.tr("Copy")})
				if sig.clicked {
					ui.window_clipboard_set(line)
					app.copied = i
				} else if copied && !sig.hovering {
					app.copied = -1   // (the check goes when the pointer leaves)
				}
			}
		}
	}
	ui.space(ui.GROUP_GAP)
}

// A program's row of the list: its box, its mark, its name and version, its line, its state at the end.
@(private = "file")
program_row :: proc(app: ^App, p: Program, r: ^Row, em: f32) {
	if ui.card_row(fmt.tprintf("###program_%s", p.slug)) {
		ui.next({width = ui.px(math.round(em * 1.6)), height = ui.px(math.round(em * 2))})
		if ui.disabled(!row_choosable(app, r^)) { ui.checkbox("###box", "", &r.ticked) }
		ui.space(ui.ICON_GAP)
		program_mark(r, em * MARK_EM, "###mark")
		ui.space(ui.SPACE_3)
		// (a share that asks for no width: a name and its version wider than it are cut, the state at the end stays in
		// the card)
		ui.next({width = ui.fill(), height = ui.children_sum(), axis = .Y})
		if ui.column(flags = {.Clip, .Fits_Width}, id = "###words") {
			line_next()
			if ui.row(.Center, id = "###title") {
				ui.next({width = ui.text_size(), height = ui.px(math.round(em * 1.5)), font_size = math.round(em * 1.1), text_pad = 0})
				ui.label(fmt.tprintf("%s###name", p.name))
				ui.space(ui.SPACE_2)
				if ui.tags("weak") {
					ui.next({width = ui.text_size(), height = ui.px(math.round(em * 1.5)), text_pad = 0})
					ui.label(fmt.tprintf("%s###version", p.version))
				}
				// (the newer suite carries it at a newer version: after atelier's update)
				if available := suite_available(app.suite_newer, p.slug); available != "" {
					ui.space(ui.SPACE_3)
					if ui.tags("accent") {
						small_icon(em, lucide.ARROW_UP_CIRCLE, ui.color("text"))
						ui.space(ui.SPACE_1)
						ui.next({width = ui.text_size(), height = ui.px(math.round(em * 1.5)), text_pad = 0, font_size = math.round(em * 0.86)})
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
		}
		ui.space(ui.SPACE_4)
		state_badge(app, r^, em)
	}
}

// The state of a program in a few words, coloured by what it means.
@(private = "file")
state_badge :: proc(app: ^App, r: Row, em: f32) {
	reading := !app.known || r.status.state == .Reading
	if reading {
		ui.spinner("###reading", math.round(em * 1.1))
		ui.space(ui.ICON_GAP)
	}
	if ui.tags(state_tone(r.status.state)) {
		if !reading {
			small_icon(em, state_glyph(r.status.state), ui.color("text"))
			ui.space(ui.SPACE_1)
		}
		ui.next({width = ui.text_size(), height = ui.px(math.round(em * 2)), text_pad = 0})
		// (the reason of Unknown is under the tagline, where it has room)
		words := r.status.state == .Unknown ? i18n.tr("Cannot be read here") : state_words(r.status)
		ui.label(fmt.tprintf("%s###state", words))
	}
}

// The licences: a section per program chosen, each licence its title and its text in a well. The wells are on the page:
// a card around them would frame a frame.
@(private = "file")
licences_view :: proc(app: ^App, em: f32) {
	// (no sentence above them: the step and the "Accept and install" button say what to do)
	first := true
	for p, i in app.programs {
		r := &app.rows[i]
		if !r.ticked { continue }
		if !first { ui.space(ui.GROUP_GAP) }
		first = false
		section_head(em, fmt.tprintf("###licences_%s", p.slug), fmt.tprintf("%s %s", p.name, p.version))
		ui.space(ui.LINE_GAP)
		if r.licences == nil {
			line_next()
			if ui.row(.Center, id = fmt.tprintf("###licences_reading_%s", p.slug)) {
				ui.spinner("###spin")
				ui.space(ui.ICON_GAP)
				if ui.tags("weak") {
					ui.next({width = ui.fill(), height = ui.px(math.round(em * 2)), text_pad = 0})
					ui.label(fmt.tprintf("%s###text", i18n.tr("Reading the licences…")))
				}
			}
			continue
		}
		if len(p.licences) == 0 {
			icon_paragraph(em, fmt.tprintf("###licences_none_%s", p.slug), lucide.ALERT_TRIANGLE, i18n.tr("This program carries no licence file."), "warn")
			continue
		}
		for l, k in p.licences {
			if k >= len(r.licences) { break }
			if k > 0 { ui.space(ui.ITEM_GAP) }
			line_next()
			if ui.row(.Center, id = fmt.tprintf("###licence_title_%s_%d", p.slug, k)) {
				if ui.tags("weak") {
					small_icon(em, lucide.FILE_TEXT, ui.color("text"))
					ui.space(ui.ICON_GAP)
					ui.next({width = ui.fill(), height = ui.px(math.round(em * ICON_LINE_EM)), text_pad = 0})
					ui.label(fmt.tprintf("%s###title", l.title))
				}
			}
			ui.space(ui.SPACE_1)
			ui.next({width = ui.fill(), height = ui.px(math.round(em * TEXT_VIEW_EM)), radius = math.round(em * WELL_RADIUS_EM)})
			if ui.well(fmt.tprintf("###licence_%s_%d_well", p.slug, k), .X) { text_scroll(em, fmt.tprintf("###licence_%s_%d", p.slug, k), r.licences[k]) }
		}
	}
}

// The width of a row's end, in font sizes: reserved from the start, so that no stepper shifts when Retry or Open appears.
ROW_END_EM :: 8.5

// The width of an install row's name, in font sizes: the steppers start on one column.
NAME_EM :: 9

// The height of a failed install's output, in font sizes.
OUTPUT_VIEW_EM :: 8

// The install, from its first phase to its result, on one screen (src/md/README.md, "The steps of the window"): the
// status card at the top, then one list with a row per program chosen, each with its stepper the whole time.
@(private = "file")
installing_view :: proc(app: ^App, em: f32) {
	install_panel(app, em)
	ui.space(ui.GROUP_GAP)
	if ui.list_card("###installs") {
		for p, i in app.programs {
			r := &app.rows[i]
			if r.result == .None { continue }
			install_row(app, p, i, r, em)
		}
	}
}

// The card at the top: the count and the bar while Running; once Finished, in place, the summary, the menu's note and
// "Retry the failed ones" (busy while Retrying). Its title line is as tall as a button from the start, so the card
// keeps its height when the button appears; the button sits at the line's end, centred on it, inside the card's inset.
@(private = "file")
install_panel :: proc(app: ^App, em: f32) {
	installed, failed, busy := 0, 0, 0
	for r in app.rows {
		switch {
		case r.result == .Installed: installed += 1
		case r.result == .Failed:    failed += 1
		case result_busy(r.result):  busy += 1
		}
	}
	text, glyph, tone, note: string
	switch app.stage {
	case .Running:
		done, of := installed_count(app)
		text, glyph, tone = fmt.tprintf(i18n.tr("Installing: %d of %d done"), done, of), lucide.DOWNLOAD, ""
		// (that they install side by side, the steppers show: the note says only what a close does)
		note = i18n.tr("If you close the window, the installs under way finish first.")
	case .Retrying:
		text, glyph, tone = fmt.tprintf(i18n.tr("%d installed, %d installing again."), installed, busy), lucide.ROTATE_CCW, ""
		note = i18n.tr("Each one is in the applications menu, and updates itself.")
	case .Finished:
		if failed == 0 {
			text, glyph, tone = fmt.tprintf(i18n.tr(installed, "Done: %d program is installed.", "Done: %d programs are installed."), installed), lucide.CHECK_CIRCLE, "good"
		} else {
			text, glyph, tone = fmt.tprintf(i18n.tr("%d installed, %d failed."), installed, failed), lucide.ALERT_TRIANGLE, "bad"
		}
		note = i18n.tr("Each one is in the applications menu, and updates itself.")
	}
	if ui.card("", id = "###progress") {
		line_next()
		if ui.row(.Center, id = "###count_row") {
			if ui.tags(tone) {
				small_icon(em, glyph, ui.color("text"))
				ui.space(ui.ICON_GAP)
				ui.next({width = ui.fill(), height = ui.px(ui.dense(em * CONTROL_EM)), text_pad = 0, font_size = math.round(em * 1.1)})
				ui.label(fmt.tprintf("%s###count", text))
			}
			retrying := app.stage == .Retrying
			if app.stage != .Running && (failed > 0 || retrying) {
				ui.space(ui.CONTROL_GAP)
				disabled := !action_enabled(app, .Retry_Failed) && !retrying
				if button("###retry_failed", i18n.tr("Retry the failed ones"), lucide.ROTATE_CCW, .Primary, disabled, busy = retrying) { retry_failed(app) }
			}
		}
		ui.space(ui.LINE_GAP)
		ui.next({width = ui.fill(), height = ui.px(math.round(em * ui.SPACE_2))})
		ui.progress("###bar", install_fraction(app))
		ui.space(ui.SPACE_3)
		if ui.tags("weak") { icon_paragraph(em, "###note", lucide.INFO, note, "") }
	}
}

// The height of a button, in font sizes (the toolkit's controls): a line that may hold one is this tall.
CONTROL_EM :: f32(2.3)

// One program's row: its mark, its name, its stepper, its end (Retry or Open, in a reserved width, right-aligned on the
// card's inset); under them, from the name's column, what its result says: the installed path, or the reason of a
// failure and its output.
@(private = "file")
install_row :: proc(app: ^App, p: Program, index: int, r: ^Row, em: f32) {
	indent := math.round(em * MARK_EM) + math.round(em * ui.SPACE_3)
	if ui.card_row(fmt.tprintf("###installing_%s", p.slug), .Y) {
		line_next()
		if ui.row(.Center, id = "###head") {
			program_mark(r, em * MARK_EM, "###mark")
			ui.space(ui.SPACE_3)
			ui.next({width = ui.px(math.round(em * NAME_EM)), height = ui.children_sum(), axis = .Y})
			if ui.column(id = "###words") {
				ui.next({width = ui.fill(), height = ui.px(math.round(em * 1.5)), text_pad = 0})
				ui.label(fmt.tprintf("%s###name", p.name))
				if ui.tags("weak") {
					ui.next({width = ui.fill(), height = ui.px(math.round(em * 1.3)), text_pad = 0, font_size = math.round(em * 0.86)})
					ui.label(fmt.tprintf("%s###version", p.version))
				}
			}
			ui.space(ui.SPACE_3)
			steps := install_steps(r^, p.own)
			ui.next({width = ui.fill()})
			ui.stepper("###phases", steps[:])
			ui.space(ui.SPACE_4)
			ui.next({width = ui.px(math.round(em * ROW_END_EM)), height = ui.children_sum(), axis = .X, cross = .Center})
			if ui.row(.Center, id = "###end") {
				ui.spacer(ui.fill())
				#partial switch r.result {
				case .Failed:
					o := ui.Button_Options{icon_font = ui.lucide_icons(), disabled = app.look != .Idle}
					if ui.button("###retry", i18n.tr("Retry"), lucide.ROTATE_CCW, o).clicked { retry(app, {index}) }
				case .Installed:
					// (atelier is open: an Open would start a second one, which hands itself over to this window)
					if !p.own {
						if ui.button("###open", i18n.tr("Open"), lucide.PLAY, {icon_font = ui.lucide_icons(), intent = .Success, disabled = r.status.program == ""}).clicked {
							open_program(app, r.status.program)
						}
					}
				}
			}
		}
		#partial switch r.result {
		case .Installed: installed_lines(p, r^, indent, em)
		case .Failed:    failure_lines(app, index, r, indent, em)
		}
	}
}

// Under an installed program's stepper: where it is. (that it is installed, the stepper's checks say; that it is in the
// menu, the summary says once for all)
@(private = "file")
installed_lines :: proc(p: Program, r: Row, indent, em: f32) {
	if r.status.program == "" { return }
	ui.space(ui.SPACE_1)
	{
		line_next()
		if ui.row(.Center, id = "###where_row") {
			ui.spacer(ui.px(indent))
			if ui.tags("weak") {
				ui.next({width = ui.px(math.round(em * ICON_EM)), height = ui.px(math.round(em * ICON_LINE_EM)), font = ui.lucide_icons(), text_align = .Center, font_size = math.round(em * 0.86), text_pad = 0})
				ui.build_box({.Draw_Text, .No_Text_Trunc}, fmt.tprintf("%s###where_icon", lucide.FOLDER))
				ui.space(ui.ICON_GAP)
				ui.next({width = ui.fill(), height = ui.px(math.round(em * ICON_LINE_EM)), text_pad = 0, font = ui.mono_font(), font_size = math.round(em * 0.86)})
				ui.label(fmt.tprintf("%s###where", r.status.program))
			}
		}
	}
}

// Under a failed program's stepper: the reason, "Details" at the line's end (above Retry's column), and once open the
// whole output (its exit code after it) in a tinted area without a frame, with its Copy button in its corner.
@(private = "file")
failure_lines :: proc(app: ^App, index: int, r: ^Row, indent, em: f32) {
	details := failure_details(r^)
	ui.space(ui.SPACE_1)
	line_next()
	if ui.row(.Center, id = "###reason_row") {
		ui.spacer(ui.px(indent))
		if ui.tags("bad") {
			small_icon(em, lucide.ALERT_CIRCLE, ui.color("text"))
			ui.space(ui.ICON_GAP)
			ui.next({width = ui.fill(), text_pad = 0})
			ui.paragraph(fmt.tprintf("%s###reason", failure_reason(r.output, r.phase, r.exit_code)))
		}
		if details != "" {
			ui.space(ui.SPACE_4)
			ui.next({width = ui.px(math.round(em * ROW_END_EM)), height = ui.children_sum(), axis = .X, cross = .Center})
			if ui.row(.Center, id = "###details_end") {
				ui.spacer(ui.fill())
				if ui.button("###details", i18n.tr("Details"), r.details ? lucide.CHEVRON_UP : lucide.CHEVRON_DOWN, {icon_font = ui.lucide_icons(), quiet = true}).clicked {
					r.details = !r.details
				}
			}
		}
	}
	if r.details && details != "" {
		ui.space(ui.LINE_GAP)
		line_next()
		if ui.row(id = "###output_row") {
			ui.spacer(ui.px(indent))
			// (a well without its edge: it is inside a card, where a second edge is one line too many)
			ui.next({width = ui.fill(), height = ui.px(math.round(em * OUTPUT_VIEW_EM)), radius = math.round(em * WELL_RADIUS_EM)})
			if ui.well("###output_area", .X, edge = false) {
				text_scroll(em, "###output", details)
				// (the copy of the whole output, in the area's corner: it acts on what is in the area)
				ui.next({width = ui.children_sum(), height = ui.pct(1), axis = .Y})
				if ui.column(id = "###copy_column") {
					ui.space(ui.SPACE_1)
					copied := app.copied == index
					sig := ui.button("###copy_output", icon = copied ? lucide.CHECK : lucide.COPY, o = {icon_font = ui.lucide_icons(), quiet = true, tip = copied ? i18n.tr("Copied") : i18n.tr("Copy")})
					if sig.clicked {
						ui.window_clipboard_set(details)
						app.copied = index
					} else if copied && !sig.hovering {
						app.copied = -1   // (the check goes when the pointer leaves)
					}
				}
				ui.space(ui.SPACE_1)
			}
		}
	}
}

// What Details shows of a failure: the whole output, then the exit code when the install ran ("": nothing more than
// the reason). In the temporary memory.
failure_details :: proc(r: Row) -> string {
	code, ran := r.exit_code.?
	if !ran { return strings.contains(r.output, "\n") ? r.output : "" }
	exit := fmt.tprintf(i18n.tr("Exit code: %s"), exit_code_words(code))
	if r.output == "" { return exit }
	return fmt.tprintf("%s\n\n%s", r.output, exit)
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
		s.label = phase_words(phase, own)
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
			// (no word under the node: its cross says it failed, the reason under the row says why)
			case r.result == .Failed: s.state = .Failed
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

// A program's line: atelier's own is translated (its words are the program's), a carried program's is its bundle's.
program_tagline :: proc(p: Program) -> string {
	return p.own ? i18n.tr(p.tagline) : p.tagline
}

////////////////////////////////
// The buttons

// Back on the left; on the right, Close and what goes on, the last one on the page's margin. Installing has Close
// alone: an install that started ends, and its Retry buttons are on its rows.
@(private = "file")
buttons :: proc(app: ^App) {
	ui.next({width = ui.fill(), height = ui.children_sum(), axis = .X, cross = .Center})
	if ui.row(.Center, id = "###buttons") {
		ui.space(ui.PAGE_MARGIN)
		if app.bundle != nil && (app.step == .Programs || app.step == .Licences) {
			if button("###back", i18n.tr("Back"), lucide.ARROW_LEFT, .Neutral) { app_step(app, .Back) }
		}
		ui.spacer(ui.fill())
		if button("###close", i18n.tr("Close"), lucide.X, .Neutral) { platform.request_close(app.main.win) }
		if app.bundle != nil {
			#partial switch app.step {
			case .Welcome:
				ui.space(ui.CONTROL_GAP)
				if button("###next", i18n.tr("Choose the programs"), lucide.ARROW_RIGHT, .Primary, len(app.rows) == 0) { app_step(app, .Next) }
			case .Programs:
				ui.space(ui.CONTROL_GAP)
				if button("###next", i18n.tr("Next"), lucide.ARROW_RIGHT, .Primary, chosen_count(app) == 0) { app_step(app, .Next) }
			case .Licences:
				ui.space(ui.CONTROL_GAP)
				if button("###install", i18n.tr("Accept and install"), lucide.DOWNLOAD, .Success, !licences_ready(app) || chosen_count(app) == 0) { app_step(app, .Next) }
			case .Checking:
				// (the look for the programs that run, then its question: the button itself waits)
				ui.space(ui.CONTROL_GAP)
				button("###install", i18n.tr("Accept and install"), lucide.DOWNLOAD, .Success, busy = true)
			}
		}
		ui.space(ui.PAGE_MARGIN)
	}
}

// A button of the steps. `busy`: its act is under way, the spinner in its glyph's place (the toolkit's busy button).
@(private = "file")
button :: proc(id, label, glyph: string, intent: ui.Intent, disabled := false, busy := false) -> bool {
	return ui.button(id, label, glyph, {icon_font = ui.lucide_icons(), intent = intent, disabled = disabled, busy = busy}).clicked
}

////////////////////////////////
// Building blocks

// A line of the window: as wide as it, as tall as what it holds.
@(private = "file")
line_next :: proc() {
	ui.next({width = ui.fill(), height = ui.children_sum(), axis = .X, cross = .Center})
}

// A section's head on the page: the accent's bar, then its title.
@(private = "file")
section_head :: proc(em: f32, id, title: string) {
	line_next()
	if ui.row(.Center, id = id) {
		ui.next({width = ui.px(max(math.round(em * 0.22), 2)), height = ui.px(math.round(em * 1.5)), bg = ui.color("accent")})
		ui.build_box({.Draw_Background}, "###bar")
		ui.space(ui.ICON_GAP)
		ui.next({width = ui.fill(), height = ui.px(math.round(em * 1.7)), text_pad = 0, font_size = math.round(em * 1.1)})
		ui.label(fmt.tprintf("%s###title", title))
	}
}

// A long text (a licence, an install's output), monospace, INNER_PAD in from its well's edges: what does not fit
// scrolls. Its well is the caller's. (the inset above and below is in the scroll view, so the text scrolls to the well's
// edge: the well's own `pad` would cut it at the inset)
@(private = "file")
text_scroll :: proc(em: f32, id, text: string) {
	ui.space(ui.INNER_PAD)
	ui.next({width = ui.fill(), height = ui.pct(1)})
	if ui.scroll_y(fmt.tprintf("%s_scroll", id)) {
		ui.space(ui.SPACE_2)
		ui.next({width = ui.fill(), text_pad = 0, font = ui.mono_font(), font_size = math.round(em * 0.86)})
		ui.paragraph(fmt.tprintf("%s###text", text))
		ui.space(ui.SPACE_2)
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
