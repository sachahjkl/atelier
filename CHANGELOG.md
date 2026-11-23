# Changelog

All notable changes to atelier are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.4] - 2026-11-23 05:21

### Changed
- **The programs' latest versions**: atelier now carries Classeur 0.45.1, feuille 0.10.1.

## [0.9.3] - 2026-11-22 05:19

### Changed
- **The programs' latest versions**: atelier now carries Papier 0.43.0, Inspecteur 0.27.0, opencode native 0.83.0.

## [0.9.2] - 2026-11-21 18:14

### Changed
- **Wheel controls in settings and clearer selected rows**: in Settings, the mouse wheel steps through closed menus, switches, font pickers and numeric fields; selected rows keep readable contrast on secondary text and underline matched letters (gui_toolkit 0.341.1).

## [0.9.1] - 2026-11-21 10:12

### Changed
- **The update badge shows its download**: when a new atelier is on offer, its badge in the title bar turns from Install to a bar that fills as the download goes, then to Restart.

## [0.9.0] - 2026-11-21 08:30

### Added
- **feuille in the suite**: atelier now carries feuille 0.8.0, on Linux and Windows. It opens a PDF at once, arranges its pages and puts text on them.

## [0.8.4] - 2026-11-21 05:19

### Changed
- **The programs' latest versions**: atelier now carries Papier 0.41.0, Classeur 0.42.0, cliche 0.27.0, Inspecteur 0.25.1, opencode native 0.82.0.

## [0.8.3] - 2026-11-20 05:19

### Changed
- **The programs' latest versions**: atelier now carries Papier 0.40.1, Classeur 0.41.1, cliche 0.26.1, Inspecteur 0.24.1, opencode native 0.79.1.

## [0.8.2] - 2026-11-19 05:20

### Changed
- **The programs' latest versions**: atelier now carries Papier 0.39.0, Classeur 0.39.0, cliche 0.25.1, Inspecteur 0.23.1, opencode native 0.78.0.

## [0.8.1] - 2026-11-18 13:45

### Changed
- **Corners and selections follow the theme**: the wells, the cards and a chosen row take the shape and the colours of the theme in use; the toolkit adds the theme Old Head (gui_toolkit 0.316.0).

## [0.8.0] - 2026-11-18 09:37

### Changed
- **A new tagline: high power tools for your desktop**: the window and the site say it in place of "the working man's tools"; the site's footer credits htmx, whose words it borrows.

## [0.7.5] - 2026-11-18 05:20

### Changed
- **The programs' latest versions**: atelier now carries Papier 0.36.0, opencode native 0.74.1.

## [0.7.4] - 2026-11-17 23:54

### Changed
- **Atelier opens without Vulkan on Linux**: on a machine whose Vulkan driver is missing, its window draws with OpenGL instead of saying it cannot draw (gui_toolkit 0.307.0).

## [0.7.3] - 2026-11-17 12:53

### Changed
- **gui_toolkit 0.299.0**: a wide tool bar of the settings no longer pushes the panels beside it out of the window; sizes read with a space that never breaks from the number ("12 MB").

## [0.7.2] - 2026-11-17 11:39

### Changed
- **The suite's newest toolkit**:
  - Buttons, fields and lists to choose from have one height, so the controls side by side line up.
  - In a narrow window, the title bar cuts its steps and keeps the window's buttons, and a long program name is cut before the program's state at the end of its row.
  - The sheet of the keys (F1) and the other dialogs called by a key appear at once, at their size.

## [0.7.1] - 2026-11-17 05:19

### Changed
- **The programs' latest versions**: atelier now carries Papier 0.32.1, Classeur 0.32.2, cliche 0.17.1, Inspecteur 0.16.1, opencode native 0.69.1.

## [0.7.0] - 2026-11-16 13:32

### Changed
- **The settings, the palette and the setup of the suite's newest toolkit**:
  - In the command palette, Enter on a setting that is no switch opens its control under its row; Shift+Enter shows the setting in the settings page.
  - The setup page (`atelier --setup`, Settings > Installation) shows Atelier's logo, its state beside its version, and its options as switches.
  - A logout or a shutdown while Atelier runs no longer shows a crash report at the next start.
- **The suite's spacing, cards and wells**: Atelier's pages use the same spacing, cards and lists as the other programs of the suite. The cards have the suite's rounder corners, and a failed install's output is a well carved in its row, as the licences' texts are.
- **Atelier installs itself in Froment Software's folder**, as every program of the suite: `%LOCALAPPDATA%\Programs\FromentSoftware\Atelier` on Windows, `~/.local/opt/FromentSoftware/Atelier` on Linux. On Windows an install made before stays where it is. On Linux, Atelier 0.6.1 or earlier installed in `~/.local/share/atelier`: after this update its row reads "Repair" and is ticked. Install it once more and the menu opens the new copy; then you can delete the folder `~/.local/share/atelier`.

## [0.6.1] - 2026-11-16 05:21

### Changed
- **The programs' latest versions**: atelier now carries Papier 0.29.0, Classeur 0.29.0, cliche 0.13.0, Inspecteur 0.13.0, opencode native 0.64.0.

## [0.6.0] - 2026-11-15 20:37

### Added
- **By Froment Software in the setup**: the install's dialog and the settings' Installation page say who makes Atelier, with its mark; the name opens froment.software.
- **Your own keys and aliases for any command**: in the command palette (Ctrl+K), Ctrl+Enter on a command records a key for it, one key or two in a row (Ctrl+M, then T). Alt+Enter makes the letters typed an alias of the command: typed whole, the alias puts the command first. A program's "Open" line takes a key too. The tooltips and the sheet of the keys (F1) show your keys. Settings > Keys holds them, where a reset removes them.

### Changed
- **Each thing said once**: the lines that repeated what a step, a button or a mark already shows are gone: the welcome's paragraphs, the Programs and Licences instructions, "Failed" under a red step, "in the applications menu" on Atelier's own row.
- **When the copy was made, in words**: the first step says when the carried programs were put together, with the hour, as one says it ("made today 21:30", "made Nov 10, 18:42").
- **Atelier's name capitalised, and its files in the vendor's folder**: the window, the palette, the setup and the settings say "Atelier". The settings, the state, the logs and the scratch folder are now in `FromentSoftware/Atelier` (`~/.config/FromentSoftware/Atelier`, `~/.local/state/FromentSoftware/Atelier`...). The settings start fresh there once (the theme, the window's place), and the palette forgets once which commands you chose most often.

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

[0.9.4]: https://github.com/sachahjkl/atelier/releases/tag/v0.9.4
[0.9.3]: https://github.com/sachahjkl/atelier/releases/tag/v0.9.3
[0.9.2]: https://github.com/sachahjkl/atelier/releases/tag/v0.9.2
[0.9.1]: https://github.com/sachahjkl/atelier/releases/tag/v0.9.1
[0.9.0]: https://github.com/sachahjkl/atelier/releases/tag/v0.9.0
[0.8.4]: https://github.com/sachahjkl/atelier/releases/tag/v0.8.4
[0.8.3]: https://github.com/sachahjkl/atelier/releases/tag/v0.8.3
[0.8.2]: https://github.com/sachahjkl/atelier/releases/tag/v0.8.2
[0.8.1]: https://github.com/sachahjkl/atelier/releases/tag/v0.8.1
[0.8.0]: https://github.com/sachahjkl/atelier/releases/tag/v0.8.0
[0.7.5]: https://github.com/sachahjkl/atelier/releases/tag/v0.7.5
[0.7.4]: https://github.com/sachahjkl/atelier/releases/tag/v0.7.4
[0.7.3]: https://github.com/sachahjkl/atelier/releases/tag/v0.7.3
[0.7.2]: https://github.com/sachahjkl/atelier/releases/tag/v0.7.2
[0.7.1]: https://github.com/sachahjkl/atelier/releases/tag/v0.7.1
[0.7.0]: https://github.com/sachahjkl/atelier/releases/tag/v0.7.0
[0.6.1]: https://github.com/sachahjkl/atelier/releases/tag/v0.6.1
[0.6.0]: https://github.com/sachahjkl/atelier/releases/tag/v0.6.0
[0.5.1]: https://github.com/sachahjkl/atelier/releases/tag/v0.5.1
[0.5.0]: https://github.com/sachahjkl/atelier/releases/tag/v0.5.0
[0.4.0]: https://github.com/sachahjkl/atelier/releases/tag/v0.4.0
[0.3.1]: https://github.com/sachahjkl/atelier/releases/tag/v0.3.1
[0.3.0]: https://github.com/sachahjkl/atelier/releases/tag/v0.3.0
[0.2.0]: https://github.com/sachahjkl/atelier/releases/tag/v0.2.0
[0.1.2]: https://github.com/sachahjkl/atelier/releases/tag/v0.1.2
[0.1.1]: https://github.com/sachahjkl/atelier/releases/tag/v0.1.1
[0.1.0]: https://github.com/sachahjkl/atelier/releases/tag/v0.1.0
