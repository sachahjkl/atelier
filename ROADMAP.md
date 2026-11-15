# Roadmap

## Now

- **Wren in the suite**: atelier carries Wren once Wren installs itself with the toolkit's `--install` and answers
  `--status`. The person gets the browser with the other tools.
- **Programs closed by their own hand**: once each program of the suite answers the toolkit's `--quit`, atelier asks it
  to end instead of ending its process. An open program then closes as it would by its own menu.
- **The open programs, tested on Windows**: the question, the close and the install that follows run in the Windows CI
  on a real window, as they do on Linux. A regression there is caught before a release.

## Next

- **Uninstall from atelier**: a program's row offers to remove it (`<program> --uninstall`). The person manages the whole
  suite from one window.

## Later

- **A signed Windows file**: the release's executable signed, so that SmartScreen does not warn at its first start.
