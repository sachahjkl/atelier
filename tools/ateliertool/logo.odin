package ateliertool

// logo: atelier's mark, drawn by the toolkit's paint package (the same bytes on every system). An emblem more than a
// picture: a workbench and its vise in a strict front view, as a technical drawing shows them. Every point is on a grid
// of 16 units, every line is straight, every corner is hard; a part is 32 units thick when it carries, 16 when it does
// not. No part has an outline: a slow gradient inside it and a thin lit line under its top edge give the machined face.
// Three parts: the bench (graphite: a long top, two slender legs, a stretcher), the vise (steel: two stepped jaws on
// one base, the screw and its bar), and the work held in the jaws, a small square, the one part in the site's orange.
// Small sizes thicken every part so that it fills whole pixels, and drop the stretcher and the vise's base (detail_for).

import paint "gt:paint"
import toolbox "gt:toolbox"

LOGO_DIR    :: "assets"
LOGO_MASTER :: 1024
LOGO_SIZES  :: [?]int{16, 32, 64, 128, 256}
LOGO_ICO    :: "assets/atelier.ico"
LOGO_UNITS  :: 512.0
LOGO_GRID   :: 16.0
LOGO_SHRINK_STEP :: 4

// The colours of each part: the lit line under its top edge, its face under that line, its foot. Steel and graphite are
// both a little blue, so that the work is the one warm part.
Tone :: struct { lit, face, foot: u32 }

WORK     :: Tone{0xF6A677, 0xEC7A43, 0xD0642F}
STEEL    :: Tone{0xEDF0F3, 0xB4BCC6, 0x7B8591}
GRAPHITE :: Tone{0xA2ABB6, 0x77818D, 0x535B66}

// The height of the lit line, in units: a chamfer that catches the light, not a soft glow.
LOGO_LIT :: 4.0

// A shape with no outline: a lit line under its top edge at `y0`, then its face falling to its foot at `y1`.
@(private = "file")
volume :: proc(c: ^paint.Canvas, p: paint.Path, y0, y1: f32, tone: Tone) {
	g := paint.linear({0, y0}, {0, y1}, paint.hex(tone.lit), paint.hex(tone.foot))
	paint.add_stop(&g, LOGO_LIT / (y1 - y0), paint.hex(tone.lit))
	paint.add_stop(&g, LOGO_LIT / (y1 - y0), paint.hex(tone.face))
	paint.fill(c, p, g)
}

// 2: everything (64 px and up); 1: no stretcher (32 to 48); 0: every part twice as thick, no base under the jaws
// (16 to 24).
@(private = "file")
detail_for :: proc(size: int) -> int { return size <= 24 ? 0 : size <= 48 ? 1 : 2 }

@(private = "file")
logo_draw :: proc(size: int, detail: int) -> paint.Canvas {
	c := paint.canvas_make(size, size)
	k := f32(size) / LOGO_UNITS
	c.transform = paint.scale(paint.IDENTITY, k, k)

	G :: f32(LOGO_GRID)
	// (at 16 px a pixel is two grid steps: every part is then a whole number of pixels)
	thin: f32 = detail == 0 ? 2 * G : G        // (a part that does not carry)
	thick: f32 = detail == 0 ? 4 * G : 2 * G   // (a part that carries)

	// the bench: a long top on two slender legs, a stretcher between them
	TOP, FLOOR :: 18 * G, 28 * G
	INSET :: 2 * G   // (the top passes the legs on each side)
	x0: f32 = detail == 0 ? 2 * G : 3 * G
	x1 := LOGO_UNITS - x0
	bench: paint.Path
	defer paint.path_destroy(&bench)
	paint.rect(&bench, x0, TOP, x1 - x0, thick)
	paint.rect(&bench, x0 + INSET, TOP, thick, FLOOR - TOP)
	paint.rect(&bench, x1 - INSET - thick, TOP, thick, FLOOR - TOP)
	if detail == 2 { paint.rect(&bench, x0 + INSET, FLOOR - 4 * G, x1 - x0 - 2 * INSET, thin) }
	volume(&c, bench, TOP, FLOOR, GRAPHITE)

	// the vise, one step over the top: two jaws that face each other, each a face over a wider body, low and wide as a
	// real one is. The steps are square: a cut corner made the pair look like a bottle, tall faces like chimneys.
	BODY, MOUTH :: 6 * G, 4 * G
	jaw_top: f32 = detail == 0 ? 8 * G : 7 * G
	step := jaw_top + 4 * G
	face: f32 = detail == 0 ? 4 * G : 3 * G
	foot := TOP - thin
	m0 := f32(12 * G)   // (the mouth's left side: the vise, its bar included, is centred over the bench)
	m1 := m0 + MOUTH
	vise: paint.Path
	defer paint.path_destroy(&vise)
	paint.polygon(&vise, {{m0 - face, jaw_top}, {m0, jaw_top}, {m0, foot}, {m0 - BODY, foot}, {m0 - BODY, step}, {m0 - face, step}})
	paint.polygon(&vise, {{m1, jaw_top}, {m1 + face, jaw_top}, {m1 + face, step}, {m1 + BODY, step}, {m1 + BODY, foot}, {m1, foot}})
	// (the base that joins the jaws, no wider than them: one more step made stairs; at the small sizes it would close
	// the mouth, so the two jaws stand alone)
	if detail > 0 { paint.rect(&vise, m0, foot - thin, MOUTH, thin) }

	// (the screw out of the moving jaw, and the bar that turns it: straight, with square ends)
	screw: f32 = detail == 0 ? 2 * G : 3 * G
	bar_y0 := step - (detail == 0 ? 2 * G : 0)
	paint.rect(&vise, m1 + BODY, bar_y0 + 2 * G, screw, thin)
	paint.rect(&vise, m1 + BODY + screw, bar_y0, thin, foot - bar_y0)
	volume(&c, vise, jaw_top, foot, STEEL)

	// the work: a square of stock held at the top of the jaws, half over them; the mouth stays open under it
	work: paint.Path
	defer paint.path_destroy(&work)
	work_top := jaw_top - MOUTH / 2
	paint.rect(&work, m0, work_top, MOUTH, MOUTH)
	volume(&c, work, work_top, work_top + MOUTH, WORK)
	return c
}

// The picture at `size`: drawn large, then shrunk in steps the cubic filter keeps clean.
logo_render :: proc(size: int) -> paint.Canvas {
	n := size
	for n < LOGO_MASTER { n *= LOGO_SHRINK_STEP }
	c := logo_draw(n, detail_for(size))
	for n > size {
		next := max(n / LOGO_SHRINK_STEP, size)
		small := paint.resize(c, next, next)
		paint.canvas_destroy(&c)
		c, n = small, next
	}
	return c
}

// The files of the logo (the `logo` command): assets/logo*.png, atelier.ico, .project/image.png and the site's logo.
logo :: proc() -> toolbox.Logo {
	@(static) sizes := LOGO_SIZES
	@(static) files := [?]toolbox.Logo_File{{path = "site/img/logo.png", size = 256}}
	return {
		render = proc(size: int, _: rawptr) -> paint.Canvas { return logo_render(size) },
		dir = LOGO_DIR, master = LOGO_MASTER, sizes = sizes[:], ico = LOGO_ICO, project_image = true, files = files[:],
	}
}
