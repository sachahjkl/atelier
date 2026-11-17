package ateliertool

// logo: atelier's mark, drawn by the toolkit's paint package (the same bytes on every system). An emblem more than a
// picture: a workbench and its vise in a strict front view, as a technical drawing shows them. Every point is on a grid
// of 16 units, every line is straight, every corner is hard; a part is 32 units thick when it carries, 16 when it does
// not. No part has an outline: a slow gradient inside it gives its face, and a light from the upper left gives its
// edges (bright along the top, fainter down the left, dark along the foot). The lit edges part the picture from a dark
// ground, where graphite alone melts; soft shadows under the bench and the vise do it on a light one.
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

// The colours of each part: the edge that catches the light, its face under that edge, its foot. Graphite is lighter
// than a real one and a little warm: the bench must stand out of a dark title bar. The work is the one saturated part.
Tone :: struct { edge, face, foot: u32 }

WORK     :: Tone{0xFFD2B4, 0xF0844A, 0xD4622C}
STEEL    :: Tone{0xFFFFFF, 0xC0C7D0, 0x7C8692}
GRAPHITE :: Tone{0xC6C9CE, 0x8D9198, 0x64676E}

// How much white the edge on the lit side (the left) gets over the face: fainter than the top edge, the light is above.
LOGO_SIDE_LIGHT :: 70

// How dark the edge away from the light (the foot of each part) gets: it gives the part its foot on a light ground.
LOGO_FOOT_SHADE :: 55

// The box of a part: where its gradients start and end.
Box :: struct { x0, y0, x1, y1: f32 }

// A shape with no outline, as machined metal under a light from the upper left: a bright line `edge` units high along
// every top edge, a fainter one down every left edge, a dark one along every foot, and between them its face, falling
// from the box's top to its foot. `sheen` is the alpha of a soft diagonal band of light over the face (0: none). Each
// edge is what the same path, moved by `edge`, does not cover: no stroke, so the silhouette keeps its size and its
// hard corners. The figures of `p` must not overlap (they can touch): the dark edge is cut with the even-odd rule.
@(private = "file")
volume :: proc(c: ^paint.Canvas, p: paint.Path, box: Box, tone: Tone, edge: f32, sheen := 0) {
	face := paint.linear({0, box.y0}, {0, box.y1}, paint.hex(tone.face), paint.hex(tone.foot))
	moved :: proc(p: paint.Path, dx, dy: f32) -> paint.Path {
		q := paint.path_clone(p)
		paint.path_transform(&q, paint.translate(paint.IDENTITY, dx, dy))
		return q
	}
	down, inner, up := moved(p, 0, edge), moved(p, edge, edge), moved(p, 0, -edge)
	defer { paint.path_destroy(&down); paint.path_destroy(&inner); paint.path_destroy(&up) }

	paint.set_clip(c, p)
	paint.fill(c, p, paint.solid(paint.hex(tone.edge)))
	paint.fill(c, down, face)
	paint.fill(c, down, paint.solid(paint.hex(0xFFFFFF, LOGO_SIDE_LIGHT)))
	paint.fill(c, inner, face)
	if sheen > 0 {
		// (across the box from its upper left corner, at 45 degrees: a band that follows no edge reads as a reflection)
		d := (box.x1 - box.x0 + box.y1 - box.y0) / 2
		band := paint.linear({box.x0, box.y0}, {box.x0 + d, box.y0 + d}, paint.hex(0xFFFFFF, 0), paint.hex(0xFFFFFF, 0))
		// (it rises slowly and falls faster, but not at once: a hard fall made the steel look like glass)
		paint.add_stop(&band, 0.15, paint.hex(0xFFFFFF, 0))
		paint.add_stop(&band, 0.40, paint.hex(0xFFFFFF, sheen))
		paint.add_stop(&band, 0.52, paint.hex(0xFFFFFF, sheen / 4))
		paint.add_stop(&band, 0.75, paint.hex(0xFFFFFF, 0))
		paint.fill(c, inner, band)
	}
	// (everything but the path moved up: inside the clip, that is the foot of each figure)
	paint.rect(&up, -LOGO_UNITS, -LOGO_UNITS, 3 * LOGO_UNITS, 3 * LOGO_UNITS)
	paint.fill(c, up, paint.solid(paint.hex(0x000000, LOGO_FOOT_SHADE)), .Even_Odd)
	paint.reset_clip(c)
}

// A soft shadow on what is behind the picture, under the line from (x0, y) to (x1, y): darkest at the line's middle,
// gone `depth` under it and at its two ends. A round gradient, flattened: a box with hard ends would be one more part.
@(private = "file")
shadow :: proc(c: ^paint.Canvas, x0, x1, y, depth: f32, alpha: int) {
	p: paint.Path
	defer paint.path_destroy(&p)
	r := (x1 - x0) / 2
	paint.rect(&p, -r, 0, 2 * r, r)
	base := c.transform
	defer c.transform = base
	c.transform = paint.scale(paint.translate(base, x0 + r, y), 1, depth / r)
	g := paint.radial({0, 0}, r, paint.hex(0x000000, alpha), paint.hex(0x000000, 0))
	paint.add_stop(&g, 0.6, paint.hex(0x000000, alpha * 2 / 3))
	paint.fill(c, p, g)
}

// 2: everything (64 px and up); 1: no stretcher, no shadow, no sheen (32 to 48); 0: every part twice as thick, no base
// under the jaws, a fainter lit edge (16 to 24).
@(private = "file")
detail_for :: proc(size: int) -> int { return size <= 24 ? 0 : size <= 48 ? 1 : 2 }

// The picture `pixels` wide, as it must look once shrunk to `size`.
@(private = "file")
logo_draw :: proc(pixels, size: int, _: rawptr) -> paint.Canvas {
	detail := detail_for(size)
	c := paint.canvas_make(pixels, pixels)
	k := f32(pixels) / LOGO_UNITS
	c.transform = paint.scale(paint.IDENTITY, k, k)

	G :: f32(LOGO_GRID)
	// (at 16 px a pixel is two grid steps: every part is then a whole number of pixels)
	thin: f32 = detail == 0 ? 2 * G : G        // (a part that does not carry)
	thick: f32 = detail == 0 ? 4 * G : 2 * G   // (a part that carries)
	// (the lit edge: one pixel of the final picture, but never more than half of a thin part, never a hairline)
	edge := clamp(LOGO_UNITS / f32(size), 3, thin / (detail == 0 ? 4 : 2))
	sheen := detail == 2 ? 1 : 0   // (under 64 px the band is a blur that only washes the steel out)

	// the bench: a long top on two slender legs, a stretcher between them
	TOP, FLOOR :: 18 * G, 28 * G
	INSET :: 2 * G   // (the top passes the legs on each side)
	x0: f32 = detail == 0 ? 2 * G : 3 * G
	x1 := LOGO_UNITS - x0
	BODY, MOUTH :: 6 * G, 4 * G
	m0 := f32(12 * G)   // (the mouth's left side: the vise, its bar included, is centred over the bench)
	m1 := m0 + MOUTH
	foot := TOP - thin

	// the shadows, under the parts: the bench's on the floor, the vise's in the gap over the bench. They show on a light
	// ground and vanish on a dark one, where the lit edges part the picture from the ground.
	if detail == 2 {
		shadow(&c, x0, x1, FLOOR, 2 * G, 110)
		shadow(&c, m0 - BODY - G, m1 + BODY + G, foot, thin, 150)
	}

	bench: paint.Path
	defer paint.path_destroy(&bench)
	leg0, leg1 := x0 + INSET, x1 - INSET - thick
	paint.rect(&bench, x0, TOP, x1 - x0, thick)
	paint.rect(&bench, leg0, TOP + thick, thick, FLOOR - TOP - thick)
	paint.rect(&bench, leg1, TOP + thick, thick, FLOOR - TOP - thick)
	if detail == 2 { paint.rect(&bench, leg0 + thick, FLOOR - 4 * G, leg1 - leg0 - thick, thin) }
	volume(&c, bench, {x0, TOP, x1, FLOOR}, GRAPHITE, edge)

	// the vise, one step over the top: two jaws that face each other, each a face over a wider body, low and wide as a
	// real one is. The steps are square: a cut corner made the pair look like a bottle, tall faces like chimneys.
	jaw_top: f32 = detail == 0 ? 8 * G : 7 * G
	step := jaw_top + 4 * G
	face: f32 = detail == 0 ? 4 * G : 3 * G
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
	volume(&c, vise, {m0 - BODY, jaw_top, m1 + BODY, foot}, STEEL, edge, 150 * sheen)

	// the work: a square of stock held at the top of the jaws, half over them; the mouth stays open under it
	work: paint.Path
	defer paint.path_destroy(&work)
	work_top := jaw_top - MOUTH / 2
	paint.rect(&work, m0, work_top, MOUTH, MOUTH)
	volume(&c, work, {m0, work_top, m1, work_top + MOUTH}, WORK, edge, 50 * sheen)
	return c
}

// The files of the logo (the `logo` command): assets/logo*.png, atelier.ico, .project/image.png and the site's logo.
// Each size is drawn at the master's width or more, then shrunk (toolbox.logo_picture).
logo :: proc() -> toolbox.Logo {
	@(static) sizes := LOGO_SIZES
	@(static) files := [?]toolbox.Logo_File{{path = "site/img/logo.png", size = 256}}
	return {
		draw = logo_draw,
		dir = LOGO_DIR, master = LOGO_MASTER, sizes = sizes[:], ico = LOGO_ICO, project_image = true, files = files[:],
	}
}
