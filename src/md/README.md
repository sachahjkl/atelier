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
5. atelier looks and behaves like the programs it installs: gui_toolkit's window, theme and widgets.

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

A release of atelier publishes, beside each file, its manifest (`atelier-<version>-<platform>.json`). Every day the
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

## The command line

- `atelier`: the window.
- `atelier list`: the programs carried, their version and state, no window.
- `atelier install <slug>… | all`: those programs installed without a window (what the CI's live check runs). The exit
  code is 0 when each one installed.
- `atelier --bundle <file>`: read the programs from another file (a bundle built by `ateliertool bundle` without the
  program: development).
- `atelier --version`, `atelier --help`.

## Subtle points

- The scratch folder is atelier's, under the user's cache folder, never `/tmp`: on many systems `/tmp` is in memory, and
  the bundle is more than 100 MB.
- A Windows program of the GUI subsystem writes its `--status` text to the pipe atelier gives it
  (`process.console_write` writes to a usable standard handle first).
- atelier does not install itself: it is the installer. Each program it installed updates itself.

## File Index

This folder has no other file yet.
