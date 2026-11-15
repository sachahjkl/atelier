# Configuration

Every setting of atelier is a preference: a name, a type, a default value and limits. Read them all with their values:

```sh
atelier prefs
```

Change one. atelier saves it in `$XDG_CONFIG_HOME/atelier/prefs` (`%APPDATA%\atelier\prefs` on Windows), and reads it
at its next start:

```sh
atelier set appearance.mode light
atelier set programs.ticked false
```

Set one for a single run: `atelier --pref appearance.font_size=16`. `--look=dark` and `--look=light` are
`--pref appearance.mode=dark` and `--pref appearance.mode=light`.

The settings page (Ctrl+, or the gear of the title bar) shows them all and applies each change at once. It exports them
to JSON, TOML or INI, or to atelier's own format, which it imports back. The command palette (Ctrl+K) finds them too,
after a `:`.

## The common settings

The look (`appearance.*`: the theme, light or dark, the finish, the glow, the text size, the zoom, the density...), the
text and fonts (`appearance.text.*`), the window (`window.system_title`, `window.placement`, `window.toast_position`),
the scrolling (`scrolling.*`), the input (`input.*`), the delays and menus (`timing.*`), the rendering (`rendering.*`),
the updates (`update.auto`, `update.base_url`) and the messages (`general.messages`, `general.language`) are the settings
that every program of gui_toolkit has. Its
[docs/settings.md](https://github.com/sachahjkl/gui_toolkit/blob/main/docs/settings.md) lists each with its default.
atelier's defaults: the theme `atelier`, the text size 14 px, its own title bar (`window.system_title` off).

`appearance.theme` is `atelier`, a theme of gui_toolkit by its name (Midnight, Graphite, Nord, Dracula, Gruvbox, Tokyo
Night, Catppuccin, Rosé Pine, Kanagawa, One Dark, Solarized…), or one of your own: Settings > Appearance links to
`$XDG_CONFIG_HOME/atelier/themes.txt`, made with a commented guide at the first click and read again each time it is
saved.

`update.auto` applies to the installed atelier only: it downloads the new release, with the new versions of the programs
it carries. `general.menu` and `general.autostart` are the install's (its dialog, the Installation page,
`atelier --install`).

## atelier's own

| Name | Type | Default | What it does |
|---|---|---|---|
| `programs.ticked` | boolean | true | Tick the programs that are not installed, older or to repair as soon as their state is read. Off: every box starts empty. |
