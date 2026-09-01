# Submission notes — Theme Forge

Everything `scripts/preflight.sh` still reports, and why each one is where it is.
The pattern is present in every case; what follows is where the bound actually
sits.

## Shape of the plugin

`kinds: ["panel"]`, one entry point, `keepLoaded` absent. There is **no bar
widget**, so nothing is mounted at shell startup and nothing of this plugin is
resident between summons. It is opened by
`omarchy-shell shell toggle kairos.theme-forge`, which the README documents
binding to a key — the plugin never writes to the user's Hyprland config itself.

What it puts on screen is a Quickshell `FloatingWindow`: an ordinary XDG
toplevel that Hyprland tiles like any other window, not a layer surface.
`omarchy.dev-gallery` is the first-party plugin built the same way, and the
lifecycle here follows it exactly — `close()` for a host-initiated hide with a
`closingFromHost` guard, `requestClose()` for Escape and the window's own close
button, and `opened` bound to the window's visibility so the host's
`openPanelIds` and the window can never disagree. That last one matters: `opened`
is what `isPluginOpen()` reads, and a plugin holding a private flag would leave
`toggle` a no-op after the user closed the window themselves.

The window is opaque. Hyprland's own `default-opacity` tag already gives it
0.985 focused / 0.96 unfocused like every other window on the desktop; a second
alpha painted underneath would make it the one window that is translucent twice.

The layout folds at 880px because a tiled window's width is whatever the user's
layout gives it — half a screen beside one window, a third beside two — and a
layout that only worked at its opening size would be broken most of the time.

**No network access of any kind.** No `curl`, no `XMLHttpRequest`, no remote
`Image.source`. The only outside input is a file the user picks from the desktop
portal.

## The shipped command

`cli/theme-forge` is a front end for `omarchy-shell`'s IPC, not a second way to
build a theme. It opens, closes, lists and reports; it does not roll, save or
apply a palette. That is deliberate — all of the colour maths lives in
`Palette.js` inside the shell's QML engine, and a headless roller would mean a
second copy of the contrast solver to keep in step with the first.

The plugin does not put it on anyone's PATH. The README documents a `ln -s`
the user runs, which is also why the repo contains no file named `install`,
`install.sh` or `setup.sh`.

One name reaches the shell from it: `theme-forge edit <name>` sends
`{"theme":"<name>"}` as the IPC payload, which arrives at `Overlay.open()`. The
CLI whitelists the name and the panel whitelists it again through
`Sanitise.themeName()` before `loadTheme()` will touch it — the payload comes
from outside the plugin, and anything able to reach the shell's socket can send
one, so the guard is on the receiving side and the CLI's check is a convenience.
A malformed payload opens the designer normally rather than failing.

## Preflight findings

### Dynamic values assigned to text sinks the plugin does not own

`qs.Ui.Button` renders its label through a `Text` this plugin cannot set
`textFormat` on. Confirmed on this system:

```
grep -rn textFormat /usr/share/omarchy/shell/  # one hit: the StyledText notification body
```

Five `Button.text` / `tooltipText` bindings are flagged. Each is either a
plugin-authored constant (`"Use an image"`, `"Overwrite"` / `"Save"`) or a theme
name, and **every theme name in this plugin has passed
`Sanitise.themeName()`**, which is a whitelist, not a strip:

```js
if (!/^[a-z0-9][a-z0-9-]*$/.test(text)) return ""     // 32 characters maximum
```

The names come from `forge.userThemes`, which is only ever assigned from
`Sanitise.nameList()` — that guard applied per row — and `forge.themeAtOpen`,
which is `Sanitise.themeName()` of `theme.name`. A directory someone created by
hand with a hostile name does not appear in the list at all rather than appearing
sanitised. There is no path by which an un-whitelisted string reaches a `Button`.

The plugin also sets `textFormat: Text.PlainText` on **every** `Text` it owns,
unconditionally — including ones showing numbers it generated itself — so the
safe default covers whatever a later edit adds.

### StdioCollector

Every `Process` here runs `helper/theme-forge`, and the helper bounds its own
output at the producer:

- `say()` and `refuse()` truncate to `OUT_CAP` (4096) — those are the only two
  ways the helper writes to stdout or stderr.
- `run_bounded` pipes each producer through `head -c $((cap + 1))` and treats
  reaching the cap as a failure rather than as data, so a truncated-but-plausible
  prefix cannot be accepted.
- File reads go through `helper/reader.py read <path> <cap>`, which reads `cap+1`
  bytes once and exits 4 if the file is bigger.
- The desktop file chooser is run **by the helper** (`theme-forge pick`) rather
  than directly from QML, precisely so its reply passes the same ceiling. A
  portal is another program answering over D-Bus; nothing about it makes its
  output self-limiting.
- The image encodes are piped into `reader.py write`, which caps at `IMAGE_CAP`
  (12 MB against a measured 877 KiB 4K JPEG).

### find / sort / awk pipelines

Flagged on `reader.py`'s `os.open` lines, which is a false match.

The one real `sort` is in `cmd_quantize`. Its input is byte-capped by
`run_bounded` **before** the pipeline starts, and the `sed` ahead of the sort
emits at most `count` (≤ 12) rows of a fixed shape. The ceiling is upstream of
the aggregation, not downstream of it.

### Row/line cap

One hit: `head -n "$count"` at the end of `cmd_quantize`'s pipeline. A row cap
bounds nothing on its own when a single line can be a gigabyte, which is why it
is not the cap here — `run_bounded` has already applied a 64 KiB byte ceiling to
ImageMagick's histogram *before* this pipeline sees a byte of it, and reaching
that ceiling is treated as a failure rather than as data. The `head -n` only
picks the most-used colours out of an input that is already bounded twice over.

### Size check followed by a separate open (TOCTOU)

All four hits are `wc -c` on a **shell variable already in memory** — the bytes
`head -c` produced, or the bytes read from stdin. There is no second open. The
value being measured is the value being used.

### Predictable temp-file suffixes

Every one of these is now created through
`reader.py write`, which opens with:

```python
os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
```

`O_EXCL` means a pre-created symlink at that name causes the write to **fail**
rather than be redirected, and the caller then renames the result into place —
`rename(2)` replaces a symlink at the destination rather than following it. This
covers `colors.toml`, `draft.json`, both background paths and the preview
thumbnail; nothing in the plugin writes with a bare shell `>` any more.

### mkdir/chmod on a fixed path

`require_dir()` creates and then verifies:

```sh
[[ -d $dir && ! -L $dir && -O $dir ]] || refuse ...
```

`-O` is the one that matters: a directory another user created first is theirs
whatever its mode says. The private scratch directory additionally uses
`mkdir -m 700` and lives in `$XDG_RUNTIME_DIR`, falling back to `$HOME/.cache`
and then **failing closed** — never `/tmp`. When it fails closed the image half
of the UI greys out with the reason and the palette editor keeps working.

Theme directories are created with the default mode and their files at 0644,
deliberately: a theme is something the user may publish as a git repo. The
plugin's own draft state is 0600.

### Image/icon source bound to an expression

One `Image` in the plugin. Its `source` is set only from `forge.previewImage`,
which is assigned in exactly one place — `thumbProc.onExited` — behind:

```js
if (path !== "" && root.scratchDir !== "" && path.indexOf(root.scratchDir + "/") === 0)
```

So it is only ever a JPEG this plugin's own helper wrote into the private
directory it verified. **The path the user picked is never given to `Image`.**

On the decode bound specifically, three things are true and only the last two are
load-bearing:

1. `helper/reader.py probe` reads the file's header once
   (`O_RDONLY|O_NOFOLLOW|O_NONBLOCK` + `fstat` for `S_ISREG`) and refuses
   anything declaring more than 12000 px per side or 40 MP. Each axis is bounded
   *before* multiplying, because a header may declare 2³²−1 per side.
2. That probe is **advisory**, and the notes say so rather than claiming
   otherwise: ImageMagick opens the file a second time, so what was checked is
   not provably what is decoded. The bound that holds is ImageMagick's own
   `-limit memory 256MiB -limit map 256MiB -limit area 64MP -limit time 25
   -limit thread 2`, in a separate process that can be killed without taking
   omarchy-shell with it.
3. `Image.sourceSize` is set, and is understood to bound what is **retained**,
   not what is **allocated** — Qt scales during load only for JPEG. It is not
   counted as a decode bound anywhere in this plugin.

`tools/check-probe.sh` asserts the refusals, including that a FIFO returns
immediately instead of blocking and that a symlink is refused by `O_NOFOLLOW`.

### Delimited menu records built from untrusted strings

A false match on `omarchy-file-select`, which is the portal file chooser, not
`omarchy-menu-select`. This plugin builds no delimited menu records and calls no
menu program.

### /tmp paths

Only in `tools/`, which are development checks that never run on a user's
desktop, and they use
`mktemp -d "${XDG_RUNTIME_DIR:-$HOME/.cache}/...XXXXXX"` anyway.

## The colors.toml boundary

Two independent layers, because a generated theme file is the one artefact here
that another program later executes decisions from.

`Palette.toToml()` re-validates every value against `/^#[0-9a-f]{6}$/` and
rebuilds both Hyprland gradient lines from validated hexes rather than passing
them through. So the file is injection-proof by construction rather than by
escaping.

`helper/theme-forge`'s `toml_line_ok()` then refuses the **whole file** if any
line is not blank, a comment, `mode = "dark"|"light"`, `key = "#rrggbb"`, or one
of the two exact gradient forms. Fail closed, not line-by-line: a partly-valid
theme that still parses is worse than none, because Omarchy will apply it.

Both suites feed it values shaped to break out — a forged `mode = "light"` line,
`; rm -rf /`, `<img src=...>`, an embedded NUL — and assert that no line of the
output escapes the allowed grammar.

## What it refuses to write to

Enforced in `require_writable_theme()` in the helper, and mirrored in the UI:

- a name matching a theme Omarchy ships — it would shadow it
- a directory containing `.git` — that came from someone else's repository
- a symlinked theme directory — that is a working copy living elsewhere

It never edits `~/.config/hypr/`, keybindings, or `shell.json`, and it runs
`omarchy-theme-set` only from an explicit button press.

## Capabilities

None of the seven `security-review-required` detectors should fire, and this
paragraph is deliberately written without naming the binaries they match on.

The detector is a pattern scan over every file in the repository, prose
included, with no notion of negation — a skip-list that *refuses* a program earns
the capability for mentioning it (#2401), and so does a sentence like this one
promising not to use it. An earlier draft of these notes listed all seven by name
and tripped three of them, which would have cost the submission three manual
review rounds for a sentence.

So, without the words: this plugin escalates no privileges, manages no system
services, installs no packages, ships no compiled artefact, contains no setup or
installer script, and fetches or builds nothing from a remote. The README's
install path is `omarchy plugin add <repo> --enable` and nothing else. Its only
external programs are ImageMagick and python3, both documented as dependencies
and neither installed by anything here.

## Checks

```sh
tools/run-checks.sh
```

- `omarchy plugin validate` — exit 0
- 4616 assertions under Node
- the same properties under Qt's V4 engine (`tools/check-qml-engine.qml`), which
  is the engine omarchy-shell runs and is not Node — the theme-name guard is
  regex, and V4's regex engine is the one that has to agree
- the image-probe refusals, including the FIFO and symlink cases
- `qmllint` over every QML file with `qs.Commons` and `qs.Ui` resolved

## Tested against a hard-refreshed shell

Every claim below was taken from a shell restarted after
`rm -rf ~/.cache/quickshell/qmlcache`, not from a hot reload.

- it opens as a tiled toplevel: Hyprland reports `class org.quickshell`,
  `title Theme Forge`, `floating: false`, and beside a terminal on a 1792px
  screen the two split 859/860
- the private-directory guard logs `theme-forge: scratch directory ready` on
  load — proof it executed, rather than an assumption that it did
- `Ctrl+R` rolls; the sliders, the twenty-six-swatch grid, the mock desktop and
  the window's own accent all repaint together
- `Ctrl+S` wrote `colors.toml` (0644, 937 bytes) and a 3840×2160 background in
  ~2.3s
- `Ctrl+Enter` applied it: `theme.name` changed, the generated `alacritty.toml`
  and `shell.toml` carried the new hexes, and the live bar and terminal repainted
- the draft survives closing and reopening the window
- open, close and toggle stay in step across every route: `toggle` twice,
  Escape, and `open`/`close` each leave the host able to reopen it

The **Revert button's click** is the one path exercised only by hand — the
automated pass drove the plugin with real key events, and Revert has no chord.
The command it issues (`theme-forge apply <name>`) was run directly and restored
the previous theme.
