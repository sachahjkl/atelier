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
	{slug = "papier", repository = "papier", name = "Papier", tagline = "Clipboard manager", site = "https://papier.froment.software/"},
	{slug = "classeur", repository = "classeur", name = "Classeur", tagline = "File manager", site = "https://classeur.froment.software/"},
	{slug = "cliche", repository = "cliche", name = "Cliche", tagline = "Screenshots and screen recorder", site = "https://cliche.froment.software/"},
	{slug = "inspecteur", repository = "inspecteur", name = "Inspecteur", tagline = "System monitor", site = "https://inspecteur.froment.software/"},
	{slug = "feuille", repository = "feuille", name = "Feuille", tagline = "PDF viewer and editor", site = "https://feuille.froment.software/"},
	{slug = "plume", repository = "plume", name = "Plume", tagline = "Text editor", site = "https://plume.froment.software/"},
	{slug = "galerie", repository = "galerie", name = "Galerie", tagline = "Image viewer", site = "https://galerie.froment.software/"},
	{slug = "ardoise", repository = "ardoise", name = "Ardoise", tagline = "Terminal", site = "https://ardoise.froment.software/"},
	{slug = "tower", repository = "tower", name = "Tower", tagline = "OpenCode client", site = "https://tower.froment.software/"},
}

// The platforms a bundle is made for, as the releases name them.
PLATFORMS :: [?]string{"linux-x64", "windows-x64"}

when ODIN_OS == .Windows {
	THIS_PLATFORM :: "windows-x64"
} else {
	THIS_PLATFORM :: "linux-x64"
}
