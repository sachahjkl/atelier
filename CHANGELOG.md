# Changelog

All notable changes to atelier are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.1] - 2026-11-15 18:00

### Changed
- **A cleaner layout**: one spacing scale, no frame inside a frame, buttons inside their panels. The programs and the
installs are one list each, their rows split by thin lines; a failed install's details show in a tinted area under its
reason.

### Fixed
- **A program to repair shows "Repair"**: the programs built on the newest gui_toolkit say "to repair" with the same exit code as "not installed"; atelier reads the words, and offers the repair as before.

## [0.5.0] - 2026-11-15 17:21

### Changed
- **The install's progress and its result are one screen**: a failed program shows why, and its Retry, on its own line. Its "Details" show the program's whole output and its exit code (a Windows code in hex, such as 0xC0000135 for a missing DLL), with a Copy button. Each failure is also written to atelier's log, and `atelier install` prints the exit code of a failed install.

### Fixed
- **Windows programs installed whole**: atelier now carries and installs what each Windows release puts beside its program (the toolkit's gt_webp.dll, the `<program>.com` console launcher), so WebP images load and the program's command works in a terminal.

## [0.4.0] - 2026-11-15 15:44

### Added
- **Update the suite from atelier**: "Check for updates" on the programs' step looks for a newer atelier. When there is
one, a banner names the programs it carries at a newer version, each such program shows the version available, and
"Update atelier and the programs" updates atelier, then opens it again on the programs with those to update ticked.
- **`atelier --quit`** closes the atelier that runs and waits for it to end.
- **Retry a failed install**: a program whose install failed has a Retry button, and the last step has "Retry the failed
ones". A retry runs the program's whole install again, from the look for a copy that runs.

### Fixed
- **A program that runs no longer makes its install fail**: before it installs, atelier looks for the programs chosen
that are open, names them, and closes them once you agree ("Close them and install"). On the command line,
`atelier install --close` closes them; without it, a program that runs is left as it is.

## [0.3.1] - 2026-11-15 14:35

### Changed
- **Rounded rows**: the selected and hovered rows (the settings' pages, the menus, the palette) are rounded faces that follow the rounding setting (gui_toolkit 0.273.0).

## [0.3.0] - 2026-11-15

### Changed
- **atelier is the first line of the programs**: no dialog asks to install it at its start. Its row has its state, its box,
its licences and its install, as each program of the suite; the Done step says that it is in the applications menu.
`atelier list` shows it, and `atelier install atelier` or `install all` installs it.

### Fixed
- **No more see-through window on Windows, states drawn in each control**: an opaque theme no longer shows the desktop through atelier; the boxes and buttons show hover and press in their own design (gui_toolkit 0.271.0).

## [0.2.0] - 2026-11-15

### Added
- **atelier installs itself**: atelier goes in your profile with its menu entry and its uninstaller, with the programs it carries, so you open it again from the menu to add a program later. Use the settings' Installation page, `atelier --install` (also `--uninstall`, `--status`, `--setup`), or on Windows the offer at its first start.
- **atelier updates itself**: the installed atelier downloads its new release, checked against its signed manifest, with the new versions of the programs it carries. The settings' Updates page checks at once on request.
- **Its own title bar, settings and command palette, as in the suite's other programs**: the window has atelier's own title bar with the steps and their icons (the system's on request), Ctrl+, opens the settings (theme, language, text, window and the rest of the suite's common settings, and whether the programs start ticked), and Ctrl+K opens the command palette over the steps, the boxes, the settings and the programs just installed. Only one atelier runs at a time: a second start brings the first to the front.

### Changed
- **A sharper mark**: atelier's logo is a workbench and its vise in steel, with a square of orange stock held in it.

## [0.1.2] - 2026-11-15

### Changed
- **The programs' latest versions**: atelier now carries Classeur 0.24.0.

### Fixed
- **A program installs even when atelier runs with a library path of its own**: the programs atelier installs start without its LD_LIBRARY_PATH and LD_PRELOAD (Linux), which loaded foreign libraries into them.

## [0.1.1] - 2026-11-15

### Fixed
- **The Windows download**: the release has its Windows file again (atelier-<version>-windows-x64.exe).

## [0.1.0] - 2026-11-15

### Added
- **atelier, the working man's tools**: one download carries papier, classeur, cliche, inspecteur (Linux) and opencode native. Choose the programs, read their licences, and each one installs itself at once; a program already installed at the same version stays as it is, an older one is updated. `atelier list` and `atelier install <program>… | all` do the same without a window. A new atelier is published on the day a program publishes a new version.

[0.5.1]: https://github.com/sachahjkl/atelier/releases/tag/v0.5.1
[0.5.0]: https://github.com/sachahjkl/atelier/releases/tag/v0.5.0
[0.4.0]: https://github.com/sachahjkl/atelier/releases/tag/v0.4.0
[0.3.1]: https://github.com/sachahjkl/atelier/releases/tag/v0.3.1
[0.3.0]: https://github.com/sachahjkl/atelier/releases/tag/v0.3.0
[0.2.0]: https://github.com/sachahjkl/atelier/releases/tag/v0.2.0
[0.1.2]: https://github.com/sachahjkl/atelier/releases/tag/v0.1.2
[0.1.1]: https://github.com/sachahjkl/atelier/releases/tag/v0.1.1
[0.1.0]: https://github.com/sachahjkl/atelier/releases/tag/v0.1.0
