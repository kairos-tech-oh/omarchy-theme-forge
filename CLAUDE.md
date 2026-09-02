# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Theme Forge is an Omarchy (Quickshell / `omarchy-shell`) `panel` plugin for
designing an Omarchy theme — 26 hex values in a `colors.toml` — in a tiled
window, with a live mock-desktop preview. `README.md` is the user manual and
`SUBMISSION-NOTES.md` documents the security posture in depth; read those for
detail beyond the architecture below.

## Commands

```sh
tools/run-checks.sh          # every check; nothing touches the desktop or writes a theme
node tools/check-palette.js  # just the JS suite (Palette.js + Sanitise.js + BarStyle.js under Node, 4600+ assertions)
tools/check-probe.sh         # helper/reader.py refusal tests (needs python3 + ImageMagick)
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml tools/check-qml-engine.qml   # the JS suite under Qt's V4 engine
```

`check-qml-engine.qml` communicates only through its exit code (Qt's `qml`
runner swallows `console` output on some builds): exit 0 = pass, any other
number = the check that failed, numbered by the comments in that file.

There is no `package.json`, no build step, and no linter config — `node` and
`qmllint` are development-only. `qmllint` runs inside `run-checks.sh`, which
builds a temporary import root with a `qs` symlink into
`/usr/share/omarchy/shell` (the repo itself must contain no symlink — the
marketplace rejects git mode 120000).

### Iterating against a live shell

Editing files in the repo does not affect the installed plugin. After a change:

```sh
rsync -a --delete --exclude .git ./ ~/.config/omarchy/plugins/kairos.theme-forge/
rm -rf ~/.cache/quickshell/qmlcache   # a stale QML cache silently runs the old code
omarchy restart shell
```

`theme-forge doctor` checks the install; `cli/theme-forge` is the user-facing
CLI (a thin front end for `omarchy-shell` IPC — it deliberately cannot roll or
save headlessly).

## Architecture

### Layer separation is the design

Each concern lives in exactly one file, and the layers do not trust each other's
output:

| File | Language | Responsibility | Never does |
|---|---|---|---|
| `Palette.js` | QML `.js` (`.pragma library`) | All colour maths — harmony, the contrast solver, hex/HSL | Any I/O, `Process`, or QML type |
| `Sanitise.js` | QML `.js` (`.pragma library`) | Boundary guards: theme names, filesystem paths, plain-text for `Text` | Any I/O |
| `BarStyle.js` | QML `.js` (`.pragma library`) | Turns the shell's injected `barConfig` (position, transparency, Rice Bar preset, widget layout) into a bounded description the preview draws from | Any I/O; trusting the config's shape |
| `helper/theme-forge` | bash | **Every** filesystem write, subprocess, and desktop change | Any colour maths |
| `helper/reader.py` | python3 | Bounded, `O_NOFOLLOW`/`O_NONBLOCK` reads; image-header probe before any decoder sees a file | — |
| `Panel.qml` … `*.qml` | QML | The window, state, and wiring | Touch the disk except through the helper |

- `Palette.js`, `Sanitise.js` and `BarStyle.js` are pure functions over strings
  and numbers so they run unchanged under both Node and Qt's V4 engine. **V4 is not V8** (its
  own regex engine, number formatting, ES feature set) — every property is
  asserted in *both* `tools/check-palette.js` and `tools/check-qml-engine.qml`,
  and a change to either `.js` file must keep both green.
- The helper is invoked as an argv array via Quickshell's `Process` (no shell
  parses its arguments), with any long or hostile payload arriving on **stdin**,
  not argv. Exit codes are its interface; stderr is a human-readable reason.
- Values crossing a boundary are re-validated there rather than trusted from the
  map that produced them: a theme name is re-checked in `Sanitise.js`, in
  `cli/theme-forge`, and again in `helper/theme-forge`.

### Panel.qml is the controller

`Panel.qml`'s root (`id: root`) is the "forge": it holds the palette state
(`colors`, `spec`, pins), the lifecycle (`open`/`close`/`opened` bound to window
visibility — a panel plugin must never hold a private open flag), every
`Process` node that calls the helper, and functions like `roll()`, `setColor()`,
`save()`. Child components — `Editor.qml`, `PreviewPane.qml`, `Settings.qml`,
`Tutorial.qml`, `ColorWheel.qml` — each take `required property var forge` and
are handed `forge: root`.

`Editor.qml` is the left column (name, roll, per-swatch tuning);
`PreviewPane.qml` is the right column (the mock desktop, drawn from the same 26
values `omarchy-theme-set` would write). Its bar follows `forge.previewBar`,
which is `BarStyle.resolve(shell.barConfig)` or the stock bar when the
`mirrorBar` pref is off. Every painted element holds a `Hotspot.qml` (a
`MouseArea` that reports its key via `forge.previewHover` / `pickFromPreview`);
the pane draws one hover outline for all of them, and clicking selects the key
and opens the wheel. `Rice*.qml` (`RiceButton`,
`RiceSurface`, `RiceField`) are the glow-styled control wrappers over the
shell's own `Button` — see the Credits section of the README.

QML imports `qs.Commons` and `qs.Ui` (the `Style` singleton, etc.) from the
installed Omarchy shell.

### Two invariants

1. **Nothing changes until a button.** Rolling, tuning, seeding from an image —
   all only move numbers in memory; the preview repaints from them. `Save`
   writes files; `Save and apply` also runs `omarchy-theme-set`. Neither is ever
   a side effect of a slider, and Apply has a Revert to the theme that was
   current when the window opened.
2. **The contrast solver is deterministic and ordered.** Every managed colour is
   solved to an explicit target WCAG ratio (see `TARGET` in `Palette.js`), not
   nudged into a band — so a seed always reproduces a palette, and
   `light < normal < bright` holds by construction. The bands (`FG_BAND`,
   `ANSI_BAND`) are gates with both floors and ceilings; a roll that cannot hit
   them is discarded and re-rolled. `derive()` adds seeded variety to the ANSI
   ramp (pull toward the accent, per-anchor hue jitter, a per-pair target
   offset shared by base and bright) — seeded from `spec.seed`, so still
   deterministic. `chaosSpec()` is the one deliberate bypass: the "True random
   roll" pref puts all 26 keys in `overrides` with no solving. Locks are
   `root.handPins` in `Panel.qml`, separate from `spec.overrides` (an override
   is an exact value to show; a lock is what a roll steps around).

### Output and state

- A theme is `~/.config/omarchy/themes/<name>/colors.toml` +
  `backgrounds/0-<name>.jpg`. `omarchy-theme-set` regenerates Alacritty, foot,
  Ghostty, kitty, btop, Neovim, Helix, Hyprland, Chromium, VS Code, Obsidian and
  the shell palette from that one file.
- In-progress themes live at `~/.local/state/kairos.theme-forge/wip/<name>/` —
  real theme directories that Omarchy's theme list simply never scans.
- `~/.local/state/kairos.theme-forge/draft.json` (auto-saved palette) and
  `prefs.json` (kept separate so clearing a draft never loses "tour seen").
- Scratch/thumbnails: `$XDG_RUNTIME_DIR/kairos-theme-forge/`, falling back to
  `~/.cache` — never `/tmp`; fails closed if neither is available.
- Saving is refused for a name that is a stock Omarchy theme, a theme installed
  from a git repo, or a symlinked theme directory.
