# atelier

The suite of Froment Software's desktop programs as one download, in Odin, on the `ext/gui_toolkit` submodule
(collection `gt`). The release is the atelier program with a zip of the programs written after it.

Read first: [README.md](README.md), [src/md/README.md](src/md/README.md), [docs/development.md](docs/development.md).

## Build and test

Every step is a command of `tools/ateliertool` (`help` lists them):

    odin run tools/ateliertool -collection:gt=ext/gui_toolkit/src -out:build/ateliertool -keep-executable -- <command>

- `build [release]` builds `build/atelier` (`build.sh` / `build.bat` are shortcuts). That build carries no programs:
  `build/atelier --bundle build/bundle-linux-x64.zip` reads them from a bundle.
- `bundle [platform]` downloads the programs' latest releases, checks them, and writes `build/bundle-<platform>.zip`.
- `package [version]` writes the release file: the release build with this system's bundle after it.
- `build`, `test` and `check` are the toolkit's (`toolbox.build_commands`). `check`: the changelog's fragments and the
  roadmap, the scopes, the French catalogue, `odin check` (this system, Windows and macOS), the tool (`-vet`), the
  tests, a release build.
- `shots` makes the pictures, `ship <patch|minor|major|x.y.z>` a release, `site build` the site, `changelog new` a fragment,
  `i18n` the catalogues, `logo` the logo's files.
- Linux: `nix develop` first (`flake.nix`).

## Rules

- A program of the suite is a line of `tools/ateliertool/programs.odin`. It must install itself with `--install` and
  answer `--status` (gui_toolkit's `gt:setup`). atelier never installs a program in its own way.
- What more than one program needs goes in gui_toolkit, generic, with its docs, test and changelog fragment; atelier then
  points to the toolkit's new tag.
- What changed is one fragment in `changelog.d/` (its README), never an edit of `CHANGELOG.md`.
- Tests never install anything for the person: they write to scratch folders only.
- Automation is a command of `tools/ateliertool`, never a shell, batch, PowerShell, Python or Node script.
- Comments and commit messages are in English. Comments say why.
- Commits: author and committer `sachahjkl <sacha@sacha.house>`, no attribution trailer, no session link.

## Changelog

- `CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and semantic versioning. It is never
  edited by hand.
- A change a user can see is one fragment in `changelog.d/`, in the same commit: `<yyyymmdd-hhmmss>-<subject>.md`, line 1
  `type: <Added|Changed|Deprecated|Removed|Fixed|Security>`, an empty line, then one entry that starts with a bold
  summary and says what changed for the user. `changelog.d/README.md` gives the format; `ateliertool changelog new`
  writes one.
- `ateliertool ship` moves the fragments into the version's section of `CHANGELOG.md` and deletes them;
  `ateliertool check` checks them.

## Roadmap

- `ROADMAP.md`, beside `CHANGELOG.md`, holds atelier's planned work: `# Roadmap`, then `## Now`, `## Next` and
  `## Later`, each a list. Each entry starts with a bold summary, then one or two sentences on what it gives the user.
  No dates, no front matter.
- When a work is done, remove its entry in the same commit as its changelog fragment.
- Work that touches several programs goes in the roadmap of gui_toolkit.
- `ateliertool check` checks its format with the changelog's.

## Intent

This project follows <https://srcmd.org>, with the Markdown in `src/md`. Read `src/md/README.md` first.

- Change the intent first, then derive the code and the tests. A change of design changes its intent file in the same
  commit.
- Keep there what the code does not show: the purpose, the decisions, the refused alternatives, the subtle points.
- `src/md/README.md` lists every other file of the folder in its `## File Index`.
- The user's documentation and the developer's how-to stay in `docs/`; `src/md` links to them.
