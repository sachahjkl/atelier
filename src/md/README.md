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
bundle.

### What goes beside a program

A Windows release puts files beside the program: the toolkit's `gt_webp.dll` (gui_toolkit's `desktop.TOOLKIT_FILES`,
which the program loads from its folder) and the console launcher `<slug>.com`. Its install copies them from beside the
running file when they are there, and does not fail when they are not. So a bundle that carried the `.exe` alone
installed programs without them: no WebP images, no `<slug>` command in a terminal. The bundle now carries them in
`<slug>/beside/`, each named in the manifest's `beside` list with its size and SHA-256, taken from the release's zip
(itself checked against its `.sha256`). Taking a program out puts them beside its file, each checked.

Refused: the release's zip as the only source of the program. Tower publishes no Windows zip, and the
update manifest stays the single signed name of the program's file.

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
nothing with another's: its own file, its own folder, its own process. Each install has four phases, which its
stepper shows (gui_toolkit's `ui.stepper`):

0. **Close**: the copy of the program that runs is closed (below, "A program that runs"). The phase is `Skipped` when
   no copy ran, so every stepper has the same nodes;
1. **Unpack**: its file is taken out of the bundle into atelier's scratch folder (`<cache>/FromentSoftware/Atelier/<slug>-<version>/`),
   mode 755 on Linux, and its SHA-256 is checked against the manifest (a file taken out at the start is checked again);
2. **Install**: atelier runs `<file> --install`: the program copies itself into its install folder, writes its menu
   entry, its system record and its own parts (the start with the session, the PATH), as its own Install button does.
   The exit code says the result (0 installed); the output is kept to show when it failed;
3. **Check**: `<file> --status` again: the carried version must now be the installed one.

The scratch file is deleted once the program is installed. After a failure it stays: a retry checks it again and uses
it. A global bar counts the programs done.

## A program that runs

On Windows, a program's file cannot be replaced while the program runs: its `--install` fails. On Linux the file is
replaced, but the copy that runs keeps the old version until it ends. So on both systems atelier closes a running
program before it installs it, once the person agrees. (Intent of the toolkit's part:
[gui_toolkit's src/md/features/quit.md](https://github.com/sachahjkl/gui_toolkit/blob/master/src/md/features/quit.md).)

1. **The look.** Right before the installs start ("Accept and install", or a retry), a worker reads `--status` of each
   program again: the state may have changed while the person read the licences. `running: true` says that a copy runs;
   `program:` is the installed copy. When a copy runs, the worker also reads the installed copy's own `--status`: its
   `quit: yes` says that the copy that runs understands `--quit`.
2. **The question.** When at least one copy runs, a confirmation (`ui.confirm_open`) names them: "These programs are
   open: Papier, Classeur. atelier closes them before it installs them. They keep your data." The buttons are "Close
   them and install" and "Back". Back returns to the licences (or, for a retry, leaves the row failed). No question when
   none runs.
3. **The close** (the Close phase, on the program's worker):
   - with `quit: yes`, atelier runs `<installed copy> --quit`: the copy that runs ends as its own Quit does;
   - then the processes whose executable is the installed copy's file (`process.processes_of`, by the full path, never
     by the name) are ended (`process.signal_process`: Terminate, then Kill), each wait bounded;
   - then atelier waits, bounded, until the file can be opened for writing: on Windows a process that is ending still
     holds it.

   A program built before the toolkit's `--quit` says no `quit:` line. Its `--quit` would open its window or fail, so
   atelier never runs it: it ends the program's process.
4. **atelier itself** never runs beside this atelier: one atelier at a time (`gt:instance`), and a second start hands
   itself over to the first. Its own row has no look, and its Close is `Skipped`.

Refused: an install that skips a running program without a word, and a close without a question. The person may have
unsaved work in it.

## A failed install, again

A failed row says why on its own line, under its stepper: the reason (below), in the danger tone with the icon
`ALERT_CIRCLE`, and at the line's end a "Details" toggle that shows the whole output under it, monospace, in a tinted
area with a Copy button in its corner. Its "Retry" (the icon `ROTATE_CCW`) is at the row's end, right of the stepper,
above Details. Once the installs are over, the status card at the top also
has "Retry the failed ones". A retry runs the row's whole way again: the look, the question when the program runs, then
Close, Unpack, Install and Check. Its stepper starts again in place: the row neither moves nor leaves the step. One look
at a time: the Retry buttons wait while a look or its question is under way.

The reason is the first line of the output that says something (`failure_reason`): the program's `--install` output, or
atelier's own why for the other phases. Lines that are advice and not a cause ("on NixOS a Nix package is the better
install") are skipped. When the program said nothing, the reason names the phase and the exit code: "The install did not
finish: the program gave no reason. Its exit code: 3". The row keeps the exit code for it, and Details shows it too.
A Windows exit code above 255 is an NTSTATUS: it is shown in hex, with its meaning when atelier knows it
(`0xC0000135`: a DLL that it needs is missing; `0xC0000005`: it crashed). A decimal 3221225781 says nothing to anyone.

Every failed phase is also written to atelier's log (gt:log): the program, the phase, the exit code and the whole output.
The window's lines go when atelier ends; the log stays, so a failure can be found again and sent. `atelier install`
prints the exit code beside "failed".

Refused: the reason in the Retry button's tooltip only (0.4.0). A person on Windows saw the failure and no cause.

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

## Uninstall from Atelier

A program that is installed (`Older`, `Current`, `Newer` or `Repair`, and not installed by Nix) has a quiet Uninstall
button at the end of its row on the Programs step. Atelier never deletes a program's files itself: it runs the program's
own `--uninstall` (for a carried program, from the carried file in the scratch folder so that Windows does not try to
delete a running file; for Atelier itself, `setup.uninstall` with `setup.remove_later` when files stay until exit).

1. **The look.** When the person clicks Uninstall on a carried program, a worker checks whether a copy runs (`open_read`,
   as before an install). Atelier's own row skips this look.
2. **The confirmation.** One modal confirmation (`ui.confirm_open`, danger intent) asks before anything is removed.
   When a copy runs, the confirmation names that it is open and offers "Close and uninstall"; otherwise it offers
   "Uninstall". Both say that settings and data stay.
3. **The uninstall** (on a worker): if a copy runs, `close_program` closes it first (`--quit`, then `processes_end`,
   then wait for the file to be free); then `<scratch> --uninstall` runs, and `--status` is read again. Meanwhile the
   row shows a spinner ("Uninstalling…"), its box is disabled, and the Programs step waits before advancing to Licences.
4. **Afterward.** Once uninstalled, the row's state becomes `Absent` and its box stays unticked: a person who just
   removed a program does not want Atelier to tick it for reinstall at once. A toast announces the result; a failure logs
   the full output.

Refused: a second uninstall step or a batch-uninstall checkbox mode. Programs are uninstalled one by one from their row,
with confirmation.

## atelier's own row

atelier is the first row of the Programs step, as one program of the suite: its logo, its name, the line "This installer,
kept on your computer: it updates the suite and adds programs later.", its version and its state, with the same badges
and the same box rules (`state_ticked`, `programs.ticked`). The person installs atelier as they install the others, in
the same list, after the same licences, with the same stepper. Nothing asks it at the start.

Refused: the toolkit's setup dialog at the start of a copy that is not installed (`prefs_page.install_offer` with an
offer, on Windows). It was an installer in front of the installer: a second window over the first step, with its own
words and buttons, which asked a question that the list asks anyway. `--setup`, the settings' Installation page and
Settings > Apps' Uninstall still open the toolkit's page or dialog, as in every program: those are about atelier alone.

Its row differs from a carried program's in what runs, not in what it shows:

- **Its state** is `gt:setup`'s facts (`setup.facts(setup_options())`, on a worker), not a `--status` of a file:
  atelier is the running process. `prefs_page.Install` keeps only whether this is the installed copy, so the row reads
  the facts itself; the read is a few `stat`s. The facts map onto the states:

  | `setup.State` | State |
  |---|---|
  | `Not_Installed`, `Removal_Scheduled` | `Absent` |
  | `This_Copy` | `Current` |
  | `Other_Copy` | the installed version against `APP_VERSION`: `Older`, `Current` or `Newer` |
  | `Repair` | `Repair` |
  | `Nix_Package` | `Current`, without a box: the Nix configuration installs it |

- **Its licences** are in atelier itself (`#load`): its `LICENSE` (MIT) and the toolkit's Lucide licence. The bundle
  does not carry atelier.
- **Its install** has the same three phases. Unpack is `Skipped`: the source is the running file, which holds nothing to
  take out, and a stepper that marks it done would claim work that never ran. Install is "Copy":
  `setup.install(setup_options(), desktop_shortcut = false)` copies the running file (the program and its bundle) into
  its folder, writes its menu entry and its record. Check reads the facts again: the installed copy's version must be
  `APP_VERSION`.
- **Installed**, its row offers no Open: atelier is open. Its row says that it is in the applications menu.
- The NixOS notice lists the carried programs only: atelier from Nix carries no bundle.

## The steps of the window

One window, one step at a time. The steps are an explicit state machine (`Step` in `src/wizard.odin`):

```
Welcome -> Programs -> Licences -> Checking -> Installing
             ^  |         |  ^         |
             +--+---------+  +---------+ (Back)
```

Installing is the last step: the install's progress and its result are one screen. Its own stage (`Install_Stage`,
`stage_next`) says whether the installs are under way:

```
Running -> Finished -> Retrying
              ^           |
              +-----------+ (all ended)
```

- **Running**: the first installs; some row is Waiting or Installing.
- **Finished**: no row is busy. The status card is the summary.
- **Retrying**: a retry is under way. The status card stays the summary, its "Retry the failed ones" busy, its counts
  live: going back to the progress would move the whole screen for one row.

Refused: a Done step after Installing (until 0.4.0). Every row's stepper disappeared at once for another list, a failed
row's Retry took the person back to the other screen, and the reason of a failure was one tooltip away. One row per
program, from its first phase to its result, keeps each program where the person watched it.

Each chosen program has its own result (`Result`, `result_next`):

```
None -> Waiting -> Installing -> Installed
          |            |
          v (Back)     v
        None         Failed -> Retrying -> Installing
                                   |
                                   v (Back)
                                 Failed
```

The look for running copies (`Look`, `look_next`) is one at a time:

```
Idle -> Reading -> To_Ask -> Asking -> Idle (the answer)
           |
           +-> Idle (none runs)
```

`To_Ask` exists because a dialog opens in a build: the worker's answer sets it, the next build opens the question.

- **Welcome**: what atelier is, by Froment Software, and the number of programs it carries. One button: Choose the programs.
- **Programs**: one row per program, atelier's own first: its box, logo, name, tagline, version, state. "Select all"
  and "Select none". Next is enabled when a box is ticked.
- **Licences**: the licences of the chosen programs, one section each (atelier's first), its text in a scroll view.
  Next is "Accept and install".
- **Checking**: the Licences step while the look for running copies reads, and while its question is open. Its button
  turns. The title bar shows Licences.
- **Installing**: one row per chosen program, all installing at once, each with its stepper (Close, Unpack, Install,
  Check) from the first phase to the end, in one list. Above them, the status card: while Running, the count and a bar for the whole; once
  Finished, in place, the summary ("5 programs are installed", or "4 installed, 1 failed"), the menu's note and "Retry
  the failed ones". The only button under it is Close: an install that started ends, so no Back.

  A row keeps its stepper the whole time; what changes is in place. Its end is an area of a fixed width, reserved from
  the start, so that no stepper shifts when a button appears there:
  - installed: "Open" at the end (atelier's own: none), and under the stepper the installed path, weak, with `FOLDER`;
  - failed: "Retry" at the end, and under the stepper the reason, "Details" and the output (above);
  - retried: the reason goes, its stepper starts again.

  The lines under the stepper grow the row's height. The toolkit has no size animation: they appear plainly.

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
  is for the pictures. Its handler takes the toolkit's `instance.MESSAGE_PING` and `instance.MESSAGE_QUIT`:
  `atelier --quit` closes the atelier that runs, as it closes every program of the suite.
- **The settings** (Ctrl+, or the gear): `prefs_page.Page` in place of the steps, with the standard settings (theme,
  atelier's own `atelier` first, language, text, window, updates, installation, diagnostics) and atelier's own
  (`programs.ticked`). The file is `<config>/FromentSoftware/Atelier/prefs`: atelier's folders are its vendor's, then
  its title (`APP_FOLDER`). An older atelier's folders (`<config>/atelier`...) are not moved: they hold only
  preferences, and on Linux `~/.local/share/atelier` is the install of atelier 0.6.1 and before (below).
  The runtime folder keeps `atelier`: an old and a new copy still meet on the instance's socket. `docs/configuration.md` lists every preference, and a test checks it.
- **The command palette** (Ctrl+K): `ui.Command_Palette` over atelier's actions (the steps, the boxes, the settings, the
  updates, the install of atelier, "Open <program>" once a program is installed) and the settings (`:`). Each command
  has an id, the person's keys and aliases are stored by (`ui.Keymap`, the settings `keys.custom` and `keys.aliases`).
  An "Open" line's id is `open.<slug>`: the bundle's slug stays from one version to the next, its name and the language
  do not. Its keys are read with the steps' actions, from the table the palette is given (made once per language).
- **Its own install** (`gt:setup` through `prefs_page.Install`): `--install`, `--uninstall`, `--status`, `--setup` and
  the Installation page. No offer at a start: atelier's own row of the Programs step installs it (above, "atelier's own
  row"). The person opens atelier again from the menu to add a program later. The install copies the running file, which is the program and its bundle: the installed copy carries its
  programs. Its identity names no NixOS libraries: the toolkit would patch the file with patchelf, and the bundle after the
  ELF must stay byte for byte. It is the person's only (`scopes = {.User}`), never for everyone: the programs it
  installs are each in the person's profile, and a copy for everyone is updated by an administrator alone, so the suite's
  update (its own file, then the programs) could not run from it.
- **Its updates** (`gt:update`): the release's file *is* the update. The signed manifest (`update-<platform>.json` and
  `.sig`) names `atelier-<version>-<platform>[.exe]`, the program with its bundle after it, which is exactly the name
  `update.expected_file_name` expects. An installed atelier that updates itself gets the new programs too. The product's
  `max_binary` is 1 GiB: the toolkit's 256 MiB bound is for a program alone, and a bundle grows with the suite.
- **Its install folder** is the toolkit's default, the vendor's folder as for every program:
  `%LOCALAPPDATA%\Programs\FromentSoftware\Atelier`, `~/.local/opt/FromentSoftware/Atelier`. atelier gives no folder of
  its own (until 0.6.1 it gave `atelier`, beside the default).

  On Windows an older install stays where it is: the system's record names its folder. Linux has no record, so after the
  update an atelier of 0.6.1 or before, which runs from `~/.local/share/atelier`, finds no install in the new folder.
  Its own row reads `Repair` (the menu entry and the icons are there, but they run another file) and is ticked; until it
  is installed again, the copy is not the installed copy and does not update itself. Its install writes the new folder
  and points the menu entry there. The old folder (the program and its bundle) stays on the disk: the person deletes it.
  Refused: a move of the old install, or its removal by atelier. The project keeps no compatibility layer, and the
  row already says what to do.

  The carried programs install into the folder of their own release's toolkit: a release built before gui_toolkit
  0.282.0 goes to `$XDG_DATA_HOME/<slug>`, a newer one to the vendor's folder. atelier reads `--status`, never a path, so
  both work; `ateliertool live` looks for both.

Refused: an update file of atelier without the bundle (the toolkit's `release.package_` writes the program alone). The
installed copy would then carry no programs, or the programs of its first install for ever.

### The suite's updates, from atelier

The person updates the programs from atelier in two moves: atelier updates itself, then installs what its new bundle
carries. The only trusted channel is atelier's own signed update: a new atelier release carries the programs' latest
versions (the daily `refresh.yml` makes sure of it), and its file is signed and checked (signature, SHA-256) by
`gt:update`.

1. **Check.** "Check for updates" (a button in the Programs step's head, the palette's command) asks the updater now.
   Its button turns while the updater checks. The check runs on the updater's thread, never in a frame.
2. **What is newer.** When a newer atelier is on offer, a worker downloads the small manifest published beside that
   release, `atelier-<version>-<platform>.json` (the new bundle's `bundle.json`). It is not signed: it decides only what
   is *shown*, never what is installed. A banner above the list says "A newer suite is available (atelier 0.4.0): Papier
   0.25.0, cliche 0.9.0 are newer than what this copy carries", and each such row has a note "0.25.0 available". When
   the manifest cannot be read, the banner names atelier's version alone.
3. **Update.** "Update atelier and the programs" asks the updater to download, check and put the new file in place
   (`update.install_now`; the updater's rules decide where: the running file, installed or not). Once it is in place,
   atelier starts its new copy with `--after-update` and ends (`host.restart_after_exit`: gui_toolkit's `program_end` starts it after the single instance is let go,
   as for a Restart). When the updater already put it in place by itself, the button restarts at once.
4. **After the update.** `--after-update` opens on the Programs step with the line "atelier is up to date: choose what to
   update.". The rows whose installed version is older than the new bundle's are ticked by the usual rule (`Older`).
   The person installs as always, with the question about the programs that run.

When atelier is already the latest, the answer to the check is "Everything is up to date" (a toast), and the rows that
are `Older` already offer "Update from …". When the check fails (offline), the toast says "The updates cannot be
checked:" and the reason. Nothing waits for it.

The pure parts are in `src/suite.odin` (what is newer, the banner's words), tested by `suite_test.odin`.

Refused: reading each program's own update manifest from atelier and installing those files. That is a second way to
install a program, beside the bundle, with as many keys as programs; the bundle's file is already signed as a whole.

### Everything is read from the bundle at the start

The bundle is read by its path, at the offsets of its index. The updater puts a new file at that path while atelier
runs (Linux renames over it; Windows renames the running file aside). A read after that would read the new file at the
old offsets. So the start's task reads all that atelier will need: the logos, the licences (a few kilobytes each), and
each program's file taken out to the scratch folder. After it, a run never reads the bundle again. A file taken out
again at an install (its first try failed) is checked against its SHA-256, so a new bundle under it fails clearly.

### The debug panels

A build with the devtools has four panels (`gt:debug`, Ctrl+Alt+Shift+D), registered at the window's start
(`debug_panels.odin`):

- **Steps**: the step, the install stage, the look and its batch. The acts are the step buttons' own (Next, Back, Select
  all, Select none, Retry failed), with the same guards (`action_enabled`).
- **Programs**: one section per row: its state, its result, its phase, its file taken out, its output. "Read status"
  asks its `--status` again, as at the start. The state can be set by hand, to see a row in a state that no run gives.
- **Bundle**: what the manifest says. "Delete the files taken out" empties the scratch folder while no row is busy: the
  next install then takes its file out again and checks it, the path of a retry after the bundle changed.
- **Updates**: the updater's phase and the newer suite on offer. "Check now" is the Programs step's button; "Read this
  suite" reads the manifest of the version typed, as an offer of the updater does.

A failure on demand goes through the real path: with "Fail the next install" on, the next install job ends before its
Unpack with a reason that says so, and the row shows its Retry. A failure faked by setting the row's result would skip
the job and its answer, which are what Retry starts again. No panel reads the disk or the network on the window's
thread: each act that does is a task, as the buttons' are.

## The command line

- `atelier`: the window.
- `atelier list`: atelier, then the programs carried, their version and state, no window.
- `atelier install <slug>… | all [--close]`: those programs installed without a window (what the CI's live check runs).
  The slug `atelier` is atelier itself; `all` includes it. The exit code is 0 when each one installed. A command line
  asks no question: a program that runs is reported and left as it is (exit 1), unless `--close` allows atelier to close
  it first, as the window's "Close them and install" does.
- `atelier uninstall <slug>… | all [--close]`: those programs uninstalled without a window (exit 0 when each one
  uninstalled or was not installed). The slug `atelier` is Atelier itself; `all` includes it. A program managed by Nix
  is left as it is. A program that runs is left as it is (exit 1), unless `--close` allows Atelier to close it first.
- `atelier --install`, `--uninstall`, `--status`, `--quit`, `--setup`: Atelier's own install (`gt:setup`), as in every
  program.
- `atelier prefs`, `atelier set <name> <value>`, `--pref name=value`: the preferences.
- `atelier --bundle <file>`: read the programs from another file (a bundle built by `ateliertool bundle` without the
  program: development).
- `atelier --look=dark|light`: `--pref appearance.mode=dark|light` for this run (the pictures).
- `atelier --after-update`: the window on the Programs step after atelier updated itself (the suite's updates, above).
- `atelier --demo --demo-case failure|update`: the demo with a failed install, or with a newer suite on offer (the
  pictures).
- `atelier --version`, `atelier --help`.

## The layout

Every gap and inset of atelier's views is a step of the toolkit's spacing scale (`ui.SPACE_1` 0.25 to `ui.SPACE_6` 1.5
font sizes), through the toolkit's role for it (`ui.space(ui.CARD_PAD)`): the page's margin, a card's inset (the same on
its four sides), a list row's inset, the gap between groups, between lines, between an icon and its words, between
buttons. The scale is the suite's ([gui_toolkit's src/md/features/spacing.md](https://github.com/sachahjkl/gui_toolkit/blob/master/src/md/features/spacing.md)):
atelier keeps no scale of its own, so its pages and the programs' line up. The scale was atelier's until 0.6.1; the
toolkit took it, with the card, the list card and the well. Until 0.5.0 each place had its own value (0.3, 0.45, 0.6,
0.9): no two places lined up, and a button touched its panel's edge.

Three gaps are no role and stay a bare step or a hand-made gap: the page's top under the title bar (`SPACE_4`, as the
toolkit's settings), the title bar's insets, and the body's right margin, which is `PAGE_MARGIN` less the scroll bar's
room. The page's margins are set once, around the step's column: the cards and the lines inside it fill it.

One level of framing:

- a group (a notice, the install's status) is one card (`ui.card`); its button sits inside its inset, centred on its
  line;
- a list (the programs, the installs, the welcome's programs) is one list card (`ui.list_card`, `ui.card_row`) whose
  rows are split by hairlines, never a stack of framed rows;
- nothing framed goes in a card: a failed install's output is a well without its edge (`ui.well(edge = false)`), on
  the row's text column;
- what is not a group stays on the page, unframed: the welcome's head, the list's head, the licences' sections. A
  licence's text is a well on the page, not in a card.

The cards end on the page's margin, where the bottom buttons end. The body's scroll bar sits in that margin: the right
margin of the body's lines is the page's margin less the bar's room, so nothing moves when the body starts to scroll.

Refused until 0.6.1: the toolkit's `ui.card`, whose inset differed above (0.9) and at the sides (1.1) and which added
a gap after it. Since gui_toolkit 0.282.0 its card has one inset on four sides and no gap after it, so atelier uses it.

The well's text keeps its inset above and below inside its scroll view, not as the well's `pad`: the text then scrolls
to the well's edge instead of being cut at the inset. In the machined finish a well without its edge still shows its
carved lip; that is the toolkit's well, the same as the licences'.

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
