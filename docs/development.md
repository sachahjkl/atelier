# Development

## The tools

- Linux: `nix develop` gives Odin (pinned), Rust (the toolkit's text library), sway (the pictures), `gh` and `curl`.
- Windows: Odin `dev-2026-11a`, Visual Studio's C++ tools, Rust, `gh` and `curl` on the PATH.

Every step is a command of `tools/ateliertool`:

    odin run tools/ateliertool -collection:gt=ext/gui_toolkit/src -out:build/ateliertool -keep-executable -- <command>

`GT=<folder>` builds against another checkout of gui_toolkit (its root).

## The program and the bundle

`ateliertool build` makes `build/atelier`, which carries no programs. `ateliertool bundle` makes
`build/bundle-<platform>.zip` from the programs' latest releases (`gh` reads them; set `GH_TOKEN` in a CI). Run the
program on it:

    build/atelier --bundle build/bundle-linux-x64.zip
    build/atelier --bundle build/bundle-linux-x64.zip --demo --step licences    # made-up states, nothing runs

`ateliertool package` writes the release's file: `build/dist/atelier-<version>-<platform>`, the release build with the
bundle after it, and its `.sha256`. A Windows file is made on Windows.

## A program in the suite

A program joins the suite with one line in `tools/ateliertool/programs.odin`. Its release must have:

- the single file that its updater downloads, named by `update-<platform>.json` (or `update-<platform>-stable.json`);
- a Linux archive `<slug>-<version>-linux-x64.tar.gz` whose files beside the program are its licences;
- `assets/logo_64.png` in its repository at the release's tag;
- `--install` and `--status` from gui_toolkit's `gt:setup`.

## A release

`ateliertool ship patch` (or `minor`, `major`) assembles the changelog's fragments, commits, tags and pushes. The tag
starts `.github/workflows/release.yml`: on Linux and on Windows, `ateliertool package <tag>`, then the GitHub release
with both files.

## The pictures

`ateliertool shots` starts atelier with `--demo` on each step in a sway nobody sees, and writes `docs/screenshots/` and
`site/img/`.
