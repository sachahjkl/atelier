# atelier: the intent

atelier is the suite of Froment Software's desktop programs as one download. A person downloads one file, chooses the
programs, reads their licences, and the programs install at once. This folder records why atelier is made the way it is.
The user's documentation is the [README](../../README.md); the developer's how-to is [docs/development.md](../../docs/development.md).

## The irreducible constraints

1. One file per system (Linux x64, Windows x64) holds every program of the suite, at the versions of their own releases.
2. The person chooses what to install. A program that is already there at the same version is not installed again.
3. The person sees the licence of each program chosen, and of what each one includes, before anything is written.
4. Each program already knows how to install itself (gui_toolkit's `gt:setup`: `<program> --install`). atelier never
   installs a program in its own way: the install of the suite is the install of each program, made by that program.
5. atelier looks and behaves like the programs it installs: gui_toolkit's window, theme and widgets. It is a program of
   the suite itself: its title bar, its settings, its command palette, its install and its updates are the toolkit's,
   made the way papier makes them (below, "A program like the others").

## The bundle: a zip after the program

The release of atelier is the atelier program with a zip written after its own bytes
([gt:archive](https://github.com/sachahjkl/gui_toolkit/blob/master/docs/archive.md), `zip_begin(after = ...)`). The zip's
offsets are the whole file's, so the program opens its own executable as a zip (`archive.open_as(exe, .Zip)`).

Refused alternatives:

- **`#load` of every program into the source.** The compiler holds the bytes in memory and in the object file: a build of
  100 MB of data is slow and needs gigabytes. Each new version of a program would need a new compile of atelier.
- **A download at install time.** The person wants one file that works offline, and the version that is offered must be
  the version that is installed. Each program updates itself after its install anyway (`gt:update`).
- **A format of our own after the program.** A zip is read by the toolkit already, and `unzip -l atelier-…` shows what a
  release carries.

The zip holds `atelier/bundle.json` (the manifest, below) and, per program, a folder `<slug>/` with the program's single
file of its release (the same file that its updater downloads), its logo, and its licence files.

```json
{"schema": 1, "platform": "linux-x64", "made": "2026-11-15",
 "programs": [{"slug": "papier", "name": "Papier", "tagline": "A fast clipboard history, searched as you type.",
   "version": "0.23.2", "repository": "https://github.com/sachahjkl/papier", "site": "https://papier.froment.software/",
   "file": "papier/papier", "size": 27685760, "sha256": "…", "logo": "papier/logo.png",
   "licences": [{"title": "MIT License", "file": "papier/LICENSE"}, {"title": "Lucide icons", "file": "papier/LUCIDE-LICENSE.txt"}]}]}
```

`tools/ateliertool bundle` makes it: for each program of `tools/ateliertool/programs.odin`, the latest release's update
manifest (`update-<platform>.json`, or `update-<platform>-stable.json`) names the file and its SHA-256; the tool downloads
the file and checks the SHA-256. The licence files come from the release's archive (`.tar.gz` or `.zip`): every file of
it but the program, the README and the changelog. A program without a file for a platform is not in that platform's
bundle (inspecteur is Linux only).

## Never behind a program

A release of atelier publishes, beside each file, its manifest (`atelier-<version>-<platform>.json`) and the signed
update manifest of that file (`update-<platform>.json` and `.sig`: the installed ateliers read it). Every day the
workflow `refresh.yml` runs `ateliertool behind`: it compares the versions that the latest Linux manifest names with each
program's latest release. When a program is newer, the tool writes the changelog's fragment ("atelier now carries
Papier 0.24.1"), and the workflow ships a patch release and calls the release workflow. A tag pushed with a workflow's
token starts no workflow, so the call is explicit.

Refused: a release of atelier from each program's own release workflow. Each program would need a token for atelier's
repository, and two programs released the same day would race for the same version number.

## The install of one program

Every program the person chose installs at the same time, each on a worker of its own. One program's install shares
nothing with another's: its own file, its own folder, its own process. Each install has three phases, which its
stepper shows (gui_toolkit's `ui.stepper`):

1. **Unpack**: its file is taken out of the bundle into atelier's scratch folder (`<cache>/atelier/<slug>-<version>/`),
   mode 755 on Linux, and its SHA-256 is checked against the manifest (a file taken out at the start is checked again);
2. **Install**: atelier runs `<file> --install`: the program copies itself into its install folder, writes its menu
   entry, its system record and its own parts (the start with the session, the PATH), as its own Install button does.
   The exit code says the result (0 installed); the output is kept to show when it failed;
3. **Check**: `<file> --status` again: the carried version must now be the installed one.

The scratch file is deleted at the end. A global bar counts the programs done.

Two processes started at the same moment can inherit each other's handles. Only the start is serialised (a lock), and
each program writes its output to a file of its own, not to a pipe: a pipe's reader waits for every process that holds
its write end, so a pipe inherited by a second install would hold up the first one's end.

The state of a program before the choice is `<file> --status` of the carried file: its exit code (0 installed, 2 to
repair, 1 not installed) and its line `version: …` (the installed copy's version). The status is read for every program
at the start, on a worker; the files are taken out once and kept in the scratch folder until atelier ends.

Why the carried file answers `--status` and not a guess from the disk: the place, the manifest and the record of an install
are the program's identity (`desktop.Identity`), which only the program knows. A copy of that identity in atelier would
drift from the program's.

## The states of a program in atelier

| State | When | Its box |
|---|---|---|
| `Reading` | the status is not known yet | disabled |
| `Absent` | not installed | ticked |
| `Older` | installed, an older version | ticked: "Update from 0.23.1" |
| `Current` | installed, the same version | not ticked: "Installed" |
| `Newer` | installed, a newer version (it updated itself) | not ticked, disabled: "0.24.0 installed" |
| `Repair` | the install is incomplete | ticked: "Repair" |
| `Unknown` | the status could not be read (the file does not run here) | not ticked, the reason under it |

On NixOS, Nix is the better install: it updates the programs with the system. atelier says so above the programs, with
each program's `nix profile add github:sachahjkl/<repository>`, which the person copies. The boxes stay: a carried file
runs where `/lib64` has an interpreter (nix-ld), and `gt:setup` makes the installed copy run by itself on NixOS. A file
that does not run there reads as `Unknown`, as on any system.

## The steps of the window

One window, one step at a time. The steps are an explicit state machine (`Step` in `src/wizard.odin`):

```
Welcome -> Programs -> Licences -> Installing -> Done
             ^  |         |
             +--+---------+  (Back)
```

- **Welcome**: what atelier is, by Froment Software, and the number of programs it carries. One button: Choose the programs.
- **Programs**: one row per program: its box, logo, name, tagline, version, state. "Select all" and "Select none".
  Next is enabled when a box is ticked.
- **Licences**: the licences of the chosen programs, one section each, its text in a scroll view. Next is "Accept and
  install".
- **Installing**: one line per chosen program, all installing at once, each with its stepper (Unpack, Install, Check)
  and a bar for the whole. No Back: an install that started ends.
- **Done**: what was installed, where it is, and a button per installed program that starts it. A failed install shows
  its output.

Closing the window during Installing waits for the programs that are installing, then ends (the worker never leaves a half
copy: each program's own install writes atomically).

## A program like the others

atelier is a meta program, but the person meets it as one more program of the suite. Each part below is the toolkit's,
wired as papier wires it (`src/settings.odin`, `settings_view.odin`, `actions.odin`, `setup_view.odin`, `updates.odin`).
A part that atelier made in its own way would drift from the programs it installs.

- **The window**: its own title bar (`integrated_title`), with atelier's mark and name, the steps, the update's badge,
  the palette's and the settings' buttons and the window's buttons. The standard setting `window.system_title` gives the
  system's title bar instead, at once. The window's place is kept (`prefs_page.Placement_Keeper`).
- **One atelier at a time** (`gt:instance`): a second start hands its launcher's activation token to the first, whose
  window comes to the front, and ends. Two ateliers would race to install the same programs. `--demo` owns nothing: it
  is for the pictures.
- **The settings** (Ctrl+, or the gear): `prefs_page.Page` in place of the steps, with the standard settings (theme,
  atelier's own `atelier` first, language, text, window, updates, installation, diagnostics) and atelier's own
  (`programs.ticked`). The file is `<config>/atelier/prefs`; `docs/configuration.md` lists every preference, and a test
  checks it.
- **The command palette** (Ctrl+K): `ui.Command_Palette` over atelier's actions (the steps, the boxes, the settings, the
  updates, the install of atelier, "Open <program>" once a program is installed) and the settings (`:`).
- **Its own install** (`gt:setup` through `prefs_page.Install`): `--install`, `--uninstall`, `--status`, `--setup`, the
  Installation page, and on Windows the offer at a start. The person opens atelier again from the menu to add a program
  later. The install copies the running file, which is the program and its bundle: the installed copy carries its
  programs. Its identity names no NixOS libraries: the toolkit would patch the file with patchelf, and the bundle after the
  ELF must stay byte for byte.
- **Its updates** (`gt:update`): the release's file *is* the update. The signed manifest (`update-<platform>.json` and
  `.sig`) names `atelier-<version>-<platform>[.exe]`, the program with its bundle after it, which is exactly the name
  `update.expected_file_name` expects. An installed atelier that updates itself gets the new programs too. The product's
  `max_binary` is 1 GiB: the toolkit's 256 MiB bound is for a program alone, and a bundle grows with the suite.

Refused: an update file of atelier without the bundle (the toolkit's `release.package_` writes the program alone). The
installed copy would then carry no programs, or the programs of its first install for ever.

### Everything is read from the bundle at the start

The bundle is read by its path, at the offsets of its index. The updater puts a new file at that path while atelier
runs (Linux renames over it; Windows renames the running file aside). A read after that would read the new file at the
old offsets. So the start's task reads all that atelier will need: the logos, the licences (a few kilobytes each), and
each program's file taken out to the scratch folder. After it, a run never reads the bundle again. A file taken out
again at an install (its first try failed) is checked against its SHA-256, so a new bundle under it fails clearly.

## The command line

- `atelier`: the window.
- `atelier list`: the programs carried, their version and state, no window.
- `atelier install <slug>… | all`: those programs installed without a window (what the CI's live check runs). The exit
  code is 0 when each one installed.
- `atelier --install`, `--uninstall`, `--status`, `--setup`: atelier's own install (`gt:setup`), as in every program.
- `atelier prefs`, `atelier set <name> <value>`, `--pref name=value`: the preferences.
- `atelier --bundle <file>`: read the programs from another file (a bundle built by `ateliertool bundle` without the
  program: development).
- `atelier --look=dark|light`: `--pref appearance.mode=dark|light` for this run (the pictures).
- `atelier --version`, `atelier --help`.

## Subtle points

- The scratch folder is atelier's, under the user's cache folder, never `/tmp`: on many systems `/tmp` is in memory, and
  the bundle is more than 100 MB.
- A Windows program of the GUI subsystem writes its `--status` text to the pipe atelier gives it
  (`process.console_write` writes to a usable standard handle first).
- atelier's `--status` is its own install's. The `--status` atelier runs is a carried program's, in a process of its own.
- Only the installed copy updates itself (`update.auto`), as in every program: a file run where it was downloaded is
  updated by the settings' Check now.

## File Index

This folder has no other file yet.
