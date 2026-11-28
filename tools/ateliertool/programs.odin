package ateliertool

// The programs of the suite: what atelier carries. A program is here when its release has the single file that its
// updater downloads (update-<platform>.json names it) and the file installs itself with `--install` (gui_toolkit's
// gt:setup). Its name and tagline are its README's.

Suite_Program :: struct {
	slug:       string,   // the program's file name ("feuille"), and its folder in the bundle
	repository: string,   // the GitHub repository's name under OWNER
	name:       string,   // as people read it
	tagline:    string,
	site:       string,
}

OWNER :: "sachahjkl"

@(rodata)
PROGRAMS := [?]Suite_Program{
	{slug = "papier", repository = "papier", name = "Papier", tagline = "A fast clipboard history, searched as you type.", site = "https://papier.froment.software/"},
	{slug = "classeur", repository = "classeur", name = "Classeur", tagline = "A fast file manager you drive from the keyboard.", site = "https://classeur.froment.software/"},
	{slug = "cliche", repository = "cliche", name = "Cliche", tagline = "Fast screenshots and screen recordings, shared at once.", site = "https://cliche.froment.software/"},
	{slug = "inspecteur", repository = "inspecteur", name = "Inspecteur", tagline = "What runs on your computer, at a glance.", site = "https://inspecteur.froment.software/"},
	{slug = "feuille", repository = "feuille", name = "Feuille", tagline = "Open a PDF at once, arrange its pages, put text on them.", site = "https://feuille.froment.software/"},
	{slug = "plume", repository = "plume", name = "Plume", tagline = "Write code and prose in a window that never waits.", site = "https://plume.froment.software/"},
	{slug = "galerie", repository = "galerie", name = "Galerie", tagline = "A whole folder of pictures at a glance, each one large and sharp, its details beside it.", site = "https://galerie.froment.software/"},
	{slug = "ardoise", repository = "ardoise", name = "Ardoise", tagline = "A terminal that keeps your shells alive.", site = "https://ardoise.froment.software/"},
	{slug = "tower", repository = "tower", name = "Tower", tagline = "Run and follow your opencode sessions, on this computer or on a server.", site = "https://tower.froment.software/"},
}

// The platforms a bundle is made for, as the releases name them.
PLATFORMS :: [?]string{"linux-x64", "windows-x64"}

when ODIN_OS == .Windows {
	THIS_PLATFORM :: "windows-x64"
} else {
	THIS_PLATFORM :: "linux-x64"
}
