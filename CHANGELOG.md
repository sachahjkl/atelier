# Changelog

All notable changes to atelier are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.2]: https://github.com/sachahjkl/atelier/releases/tag/v0.1.2
[0.1.1]: https://github.com/sachahjkl/atelier/releases/tag/v0.1.1
[0.1.0]: https://github.com/sachahjkl/atelier/releases/tag/v0.1.0
