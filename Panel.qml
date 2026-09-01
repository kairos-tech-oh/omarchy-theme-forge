import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Palette.js" as Palette
import "Sanitise.js" as Sanitise

// Theme Forge — build an Omarchy theme, see it before you commit to it.
//
// Omarchy ships 34 omarchy-theme-* commands and not one of them makes a theme.
// The format is generous: a theme is one colors.toml of 26 hex values, and
// omarchy-theme-set regenerates alacritty, foot, ghostty, kitty, btop, neovim,
// helix, hyprland, chromium, vscode, obsidian and the shell's own palette from
// it. So a complete desktop theme is 26 good hex values, and this is a tool for
// arriving at 26 good hex values.
//
// Two rules shape the whole design:
//
//   Nothing changes until you say so. Rolling, tuning and uploading only move
//   numbers in memory. The mock desktop on the right repaints from those
//   numbers, so the loop is instant and free. Save writes files; Apply runs
//   omarchy-theme-set. Both are buttons, never a side effect of a slider, and
//   Apply has an undo that puts back whatever theme was current when this
//   opened.
//
//   Every value that leaves for the disk is re-validated at the boundary rather
//   than trusted from the map that produced it. Palette.js does the maths and
//   the helper does the I/O, and neither one takes the other's word for it.
//
// Opened with:  omarchy-shell shell toggle kairos.theme-forge
//
// It is a `panel` plugin with no bar widget: the shell drives it through
// open()/close()/opened, and what it puts on screen is an ordinary toplevel
// window that Hyprland tiles like any other. omarchy.dev-gallery is the
// first-party plugin built the same way.
Item {
  id: root

  // ------------------------------------------------------------- lifecycle
  //
  // The shell drives a panel plugin through open() / close() and reads `opened`
  // back, so `opened` has to track the window rather than a flag of its own --
  // otherwise closing the window with the WM would leave the host believing it
  // is still up, and the next toggle would appear to do nothing.

  readonly property bool opened: window.visible

  // Injected by the shell's panel loader. It is how a user-initiated close gets
  // back to the host, which is the only way openPanelIds stays truthful.
  property var shell: null

  readonly property string moduleId: "kairos.theme-forge"

  // Set while *we* are the ones hiding the window, so onVisibleChanged can tell
  // "the host asked" from "the user closed it" and not report a close back to a
  // host that initiated it.
  property bool closingFromHost: false

  // The shell hands `open` whatever payload the IPC caller sent:
  //
  //     omarchy-shell shell toggle kairos.theme-forge '{"theme":"tron"}'
  //
  // which is how `theme-forge edit <name>` opens the designer on an existing
  // theme. The payload arrives from outside the plugin -- anything able to
  // reach the shell's socket can send one -- so it is parsed defensively and
  // the name goes through the same whitelist a typed one does. A payload that
  // is malformed, or names a theme that does not exist, opens the designer
  // normally rather than failing.
  function open(payloadJson) {
    root.closingFromHost = false
    window.visible = true
    root.status = ""
    root.statusKind = "info"
    // Refreshed on every open rather than cached: themes can be installed,
    // removed and switched while this window is closed.
    listProc.running = true
    lockedProc.running = true
    stockProc.running = true
    currentProc.running = true

    var wanted = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload && typeof payload === "object") wanted = Sanitise.themeName(payload.theme)
    } catch (error) {
      wanted = ""
    }
    if (wanted !== "") root.loadTheme(wanted)

    // `{"page":"settings"}` opens straight onto the settings page, which is what
    // `theme-forge settings` sends. Validated the same way the theme name is:
    // it arrives from outside the plugin, so an unknown value falls back to the
    // designer rather than leaving the window on nothing.
    var wantedPage = "design"
    try {
      var pagePayload = JSON.parse(String(payloadJson || "{}"))
      if (pagePayload && pagePayload.page === "settings") wantedPage = "settings"
    } catch (error) {
      wantedPage = "design"
    }
    root.page = wantedPage

    root.maybeStartTutorial()

    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  // Host-initiated close (`omarchy-shell shell hide`). The host already knows,
  // so this does not report back to it.
  function close() {
    root.saveDraftNow()
    root.closingFromHost = true
    window.visible = false
    root.closingFromHost = false
  }

  // User-initiated close: Escape, or the window's own close button. Route it
  // through the host so its openPanelIds map -- which is what keeps the Loader
  // alive -- is cleared too. Without this the window hides while the plugin
  // stays mounted, and the next toggle hides an already-hidden window.
  function requestClose() {
    root.saveDraftNow()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.moduleId)
    else root.close()
  }

  function notifyHostClosed() {
    root.saveDraftNow()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.moduleId)
  }

  function toggle() {
    if (root.opened) root.requestClose()
    else root.open("{}")
  }

  // Where this file is, which is where the helper is. Derived rather than
  // hardcoded so the plugin works from wherever it was installed.
  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl("."))
    if (url.indexOf("file://") === 0) url = url.substring(7)
    while (url.length > 1 && url.charAt(url.length - 1) === "/") url = url.substring(0, url.length - 1)
    return url
  }
  readonly property string helperPath: pluginDir + "/helper/theme-forge"

  // ------------------------------------------------------------ the palette
  //
  // `spec` is the six values the user manipulates; `palette` is the 26 that
  // derive from them. Everything in the UI reads `palette`, so a change to any
  // input repaints the whole preview in one pass.

  property var spec: Palette.defaultSpec()
  readonly property var colors: Palette.derive(root.spec)
  readonly property var contrastRows: Palette.report(root.colors)
  readonly property int failingCount: Palette.failingKeys(root.colors).length

  property string themeName: ""
  property string selectedKey: "background"

  // Applied by the sliders and the hex fields. The three primaries move the
  // spec, which re-derives everything; any other key becomes a pin that
  // survives derivation until it is cleared.
  function setColor(key, hex) {
    var value = Palette.normHex(hex)
    if (value === "") return
    var next = cloneSpec(root.spec)
    if (key === "background" || key === "foreground" || key === "accent") {
      next[key] = value
      // A pin on a primary would shadow the value the spec just set, which
      // reads as "the slider does nothing".
      delete next.overrides[key]
    } else {
      next.overrides[key] = value
    }
    root.setSpec(next)
  }

  function clearPin(key) {
    if (!root.spec.overrides[key]) return
    var next = cloneSpec(root.spec)
    delete next.overrides[key]
    root.setSpec(next)
  }

  function isPinned(key) {
    return root.spec.overrides[key] !== undefined
  }

  function cloneSpec(source) {
    var out = Palette.normSpec(source)
    var overrides = {}
    for (var key in source.overrides) overrides[key] = source.overrides[key]
    out.overrides = overrides
    return out
  }

  function setSpec(next) {
    root.spec = Palette.normSpec(next)
    // normSpec drops unknown and malformed overrides, so re-attach the
    // validated set rather than the raw one.
    var validated = {}
    for (var key in next.overrides) {
      var hex = Palette.normHex(next.overrides[key])
      if (hex !== "" && Palette.COLOR_KEYS.indexOf(key) !== -1) validated[key] = hex
    }
    root.spec.overrides = validated
    root.dirty = true
    draftTimer.restart()
  }

  function setMode(mode) {
    var next = cloneSpec(root.spec)
    next.mode = mode === "light" ? "light" : "dark"
    // Backgrounds and text do not survive an inversion -- a dark theme's ground
    // is unreadable as a light theme's. Re-roll them around the same seed so
    // the switch lands on a usable palette of the same family, and drop the
    // pins, which were chosen against the old ground.
    var rolled = Palette.rollSpec(root.spec.seed, next.mode)
    rolled.chroma = root.spec.chroma
    root.setSpec(rolled)
  }

  function roll() {
    var seed = Palette.randomSeed()
    root.setSpec(Palette.rollSpec(seed, root.spec.mode))
    root.setStatus("Rolled seed " + seed + ".", "info")
  }

  function rollSeed(seedText) {
    var seed = parseInt(seedText, 10)
    if (!isFinite(seed) || seed < 0 || seed > 999999) {
      root.setStatus("A seed is a whole number from 0 to 999999.", "error")
      return
    }
    root.setSpec(Palette.rollSpec(seed, root.spec.mode))
    root.setStatus("Rolled seed " + seed + ".", "info")
  }

  function setChroma(value) {
    var next = cloneSpec(root.spec)
    next.chroma = Math.round(value)
    root.setSpec(next)
  }

  // ----------------------------------------------------------- preferences
  //
  // How the tool behaves, as opposed to what a theme looks like. Kept in its
  // own file rather than in the draft: a draft is work in progress and gets
  // cleared, and "I have already seen the tour" has to survive that.
  //
  // `prefsLoaded` gates the first-run decision. Reading them is a subprocess,
  // so at the first open they are simply not here yet -- and showing the tour
  // to someone who has already dismissed it, because the answer had not
  // arrived, is exactly the bug worth designing out.

  property bool prefsLoaded: false
  property bool tutorialSeen: false
  property bool showTutorialOnOpen: false
  property real surfaceAlpha: 0.90
  property bool tutorialOpen: false
  property string page: "design"     // design | settings

  function setPref(key, value) {
    if (key === "showTutorialOnOpen") root.showTutorialOnOpen = value === true
    else if (key === "tutorialSeen") root.tutorialSeen = value === true
    else if (key === "surfaceAlpha") root.surfaceAlpha = Math.max(0.60, Math.min(1.0, Number(value) || 0.90))
    else return
    root.savePrefs()
  }

  function savePrefs() {
    prefsSaveProc.payload = JSON.stringify({
      tutorialSeen: root.tutorialSeen,
      showTutorialOnOpen: root.showTutorialOnOpen,
      surfaceAlpha: root.surfaceAlpha
    })
    prefsSaveProc.stdinEnabled = true
    prefsSaveProc.running = true
  }

  function loadPrefs(text) {
    var data = null
    try {
      data = JSON.parse(text)
    } catch (error) {
      data = null
    }
    if (data && typeof data === "object") {
      root.tutorialSeen = data.tutorialSeen === true
      root.showTutorialOnOpen = data.showTutorialOnOpen === true
      var alpha = Number(data.surfaceAlpha)
      if (isFinite(alpha)) root.surfaceAlpha = Math.max(0.60, Math.min(1.0, alpha))
    }
    root.prefsLoaded = true
    root.maybeStartTutorial()
  }

  // Called both when the window opens and when the preferences arrive, because
  // either can be last. A function rather than a handler on one of them: which
  // one wins is a race, and a guard that only runs on the loser never runs.
  function maybeStartTutorial() {
    if (!root.opened || !root.prefsLoaded || root.tutorialOpen) return
    // Never over Settings: every step but the first points at something in the
    // designer, and pointing at a pane that is not on screen is worse than not
    // running at all.
    if (root.page !== "design") return
    if (root.tutorialSeen && !root.showTutorialOnOpen) return
    root.startTutorial()
  }

  function startTutorial() {
    root.page = "design"
    root.tutorialOpen = true
  }

  // `suppress` is the checkbox in the tour. Finishing it always records that it
  // has been seen; ticking the box also turns off the "show it every time"
  // preference, so the two together mean "never again unless I ask".
  function finishTutorial(suppress) {
    root.tutorialOpen = false
    root.tutorialSeen = true
    if (suppress) root.showTutorialOnOpen = false
    root.savePrefs()
  }

  // ---------------------------------------------------------------- status

  property string status: ""
  property string statusKind: "info"   // info | ok | error
  property bool busy: false
  property bool dirty: false

  function setStatus(text, kind) {
    root.status = Sanitise.plain(text)
    root.statusKind = kind || "info"
  }

  // ----------------------------------------------------------- theme names

  property var userThemes: []
  property var stockThemes: []
  // The subset of userThemes the helper will refuse to write to: cloned from a
  // repository, or a symlink to a working copy. Kept separate so the name field
  // can say so *before* Save, rather than the UI promising an overwrite the
  // helper then turns down.
  property var lockedThemes: []
  property string currentTheme: ""
  property string themeAtOpen: ""

  // What the name field says about the name typed into it. One function so the
  // field, the Save button and the helper cannot disagree about what is
  // writable -- the helper enforces the same three refusals independently,
  // because it is a program anyone can run.
  function nameProblem() {
    var raw = String(root.themeName).trim()
    if (raw === "") return "Name it before saving."
    var name = Sanitise.themeName(raw)
    if (name === "") return "Lowercase letters, numbers and dashes, up to 32 characters."
    if (root.stockThemes.indexOf(name) !== -1) return "Omarchy already ships a theme called " + name + "."
    if (root.lockedThemes.indexOf(name) !== -1)
      return name + " was installed from a repository, so it is not this plugin's to overwrite."
    return ""
  }

  function overwrites() {
    var name = Sanitise.themeName(root.themeName)
    return name !== "" && root.userThemes.indexOf(name) !== -1
      && root.lockedThemes.indexOf(name) === -1
  }

  // -------------------------------------------------------- the background
  //
  // Two ways a theme gets a wallpaper: drawn from the palette, or seeded from
  // an image the user picked. `sourceImage` being set is what decides which,
  // and it is only ever set by the file chooser.

  property string sourceImage: ""     // the picked original, absolute
  property string previewImage: ""    // our own downscale, inside the scratch dir
  property string scratchDir: ""
  property bool scratchChecked: false

  // A function, not a derived property. `scratchDir` arrives from a subprocess
  // and is empty at first evaluation; a `readonly property` computed off it
  // would be read once by a change handler, come back empty, and never be
  // recomputed -- the guard would be present, correct, and never reached.
  function imagesUsable() {
    return root.scratchChecked && root.scratchDir !== ""
  }

  function imageBlockedReason() {
    if (!root.scratchChecked) return "Checking for a private working directory..."
    if (root.scratchDir === "") return "No private directory is available, so images are off."
    return ""
  }

  function pickImage() {
    if (!root.imagesUsable()) {
      root.setStatus(root.imageBlockedReason(), "error")
      return
    }
    root.busy = true
    root.setStatus("Waiting for the file chooser...", "info")
    pickProc.running = true
  }

  function clearImage() {
    root.sourceImage = ""
    root.previewImage = ""
    root.setStatus("Back to a background drawn from the palette.", "info")
  }

  // ------------------------------------------------------------- the draft
  //
  // The shell destroys this overlay between summons (keepLoaded is false, so a
  // tool used occasionally does not sit in the shell's memory all session), so
  // the work in progress lives on disk instead.

  Timer {
    id: draftTimer
    interval: 900
    repeat: false
    onTriggered: root.saveDraftNow()
  }

  function saveDraftNow() {
    if (!root.dirty) return
    draftSaveProc.payload = JSON.stringify({
      spec: root.spec,
      themeName: Sanitise.themeName(root.themeName),
      sourceImage: root.sourceImage
    })
    draftSaveProc.stdinEnabled = true
    draftSaveProc.running = true
    root.dirty = false
  }

  function loadDraft(text) {
    var data = null
    try {
      data = JSON.parse(text)
    } catch (error) {
      return
    }
    if (!data || typeof data !== "object") return
    root.spec = Palette.normSpec(data.spec)
    var name = Sanitise.themeName(data.themeName)
    if (name !== "") root.themeName = name
    // The picked image is re-probed and re-thumbnailed rather than trusted from
    // the draft: the path is a string in a file, and the file it names may have
    // changed or gone since it was written.
    var image = Sanitise.absPath(data.sourceImage)
    if (image !== "") {
      root.sourceImage = image
      thumbProc.command = root.helperCommand("thumb", [image], 25)
      thumbProc.running = true
    }
  }

  // ----------------------------------------------------------- save / apply
  //
  // Save is a chain: colors.toml, then the background, and only then -- if this
  // was an Apply -- omarchy-theme-set. Each step waits for the one before,
  // because a theme with a half-written colors.toml is one Omarchy will
  // cheerfully apply.

  property bool applyAfterSave: false

  function save(thenApply) {
    var problem = root.nameProblem()
    if (problem !== "") {
      root.setStatus(problem, "error")
      return
    }
    if (root.busy) return
    root.applyAfterSave = thenApply === true
    root.busy = true
    root.setStatus("Writing " + Sanitise.themeName(root.themeName) + "...", "info")
    saveProc.payload = Palette.toToml(root.colors, Sanitise.themeName(root.themeName))
    saveProc.command = root.helperCommand("save", [Sanitise.themeName(root.themeName)], 20)
    saveProc.stdinEnabled = true
    saveProc.running = true
  }

  function startBackgroundStep() {
    var name = Sanitise.themeName(root.themeName)
    if (root.sourceImage !== "" && root.imagesUsable()) {
      root.setStatus("Fitting your image to the desktop...", "info")
      adoptProc.command = root.helperCommand("adopt", [name, root.sourceImage], 60)
      adoptProc.running = true
      return
    }
    root.setStatus("Drawing a background from the palette...", "info")
    wallpaperProc.payload = ["mode=" + root.colors.mode,
                             "background=" + root.colors.background,
                             "darker_background=" + root.colors.darker_background,
                             "accent=" + root.colors.accent].join("\n")
    wallpaperProc.command = root.helperCommand("wallpaper", [name], 60)
    wallpaperProc.stdinEnabled = true
    wallpaperProc.running = true
  }

  function finishSave() {
    var name = Sanitise.themeName(root.themeName)
    if (root.userThemes.indexOf(name) === -1) {
      var next = root.userThemes.slice()
      next.push(name)
      root.userThemes = next
    }
    if (root.applyAfterSave) {
      root.applyAfterSave = false
      root.setStatus("Applying " + name + "...", "info")
      applyProc.command = root.helperCommand("apply", [name], 90)
      applyProc.running = true
      return
    }
    root.busy = false
    root.setStatus("Saved " + name + ". Apply it, or keep going.", "ok")
  }

  function revert() {
    if (root.busy) return
    var name = Sanitise.themeName(root.themeAtOpen)
    if (name === "") {
      root.setStatus("There is no earlier theme to go back to.", "error")
      return
    }
    root.busy = true
    root.setStatus("Going back to " + name + "...", "info")
    applyProc.command = root.helperCommand("apply", [name], 90)
    applyProc.running = true
  }

  // Open an existing theme so it can be edited rather than rebuilt.
  function loadTheme(name) {
    var clean = Sanitise.themeName(name)
    if (clean === "") return
    root.busy = true
    root.setStatus("Opening " + clean + "...", "info")
    loadProc.themeName = clean
    loadProc.command = root.helperCommand("load", [clean], 15)
    loadProc.running = true
  }

  // ------------------------------------------------------------- processes
  //
  // Every invocation carries a whole-request budget rather than a per-step one,
  // and the helper clamps it to at least 1 second -- `timeout 0` means no limit,
  // so a budget that reaches zero would silently remove the ceiling.
  function helperCommand(subcommand, args, budgetSec) {
    var budget = Math.max(5, Math.min(180, Math.round(budgetSec || 20)))
    return [root.helperPath, "--budget", String(budget), subcommand].concat(args || [])
  }

  // Reported for every helper failure. The helper's own stderr says what went
  // wrong in words a person can act on; anything else is a bug worth seeing.
  function helperError(fallback, text) {
    var message = Sanitise.plain(text).replace(/^theme-forge:\s*/, "").trim()
    return message === "" ? fallback : message
  }

  Process {
    id: scratchProc
    command: [root.helperPath, "scratch"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: scratchProc.outText = text }
    property string outText: ""
    onExited: function (exitCode) {
      // Shape-checked before it is kept: this string is compared against every
      // path the helper later claims to have written inside it.
      var dir = Sanitise.absPath(String(scratchProc.outText).trim())
      root.scratchDir = (exitCode === 0 && dir !== "") ? dir : ""
      root.scratchChecked = true
      // Proof the guard actually ran, rather than an assumption that it did.
      console.log("theme-forge: scratch directory " + (root.scratchDir === "" ? "unavailable" : "ready"))
      draftLoadProc.running = true
    }
  }

  Process {
    id: listProc
    command: [root.helperPath, "list"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.userThemes = Sanitise.nameList(text) }
  }

  Process {
    id: lockedProc
    command: [root.helperPath, "locked"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.lockedThemes = Sanitise.nameList(text) }
  }

  Process {
    id: stockProc
    command: [root.helperPath, "stock"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.stockThemes = Sanitise.nameList(text) }
  }

  Process {
    id: currentProc
    command: [root.helperPath, "current"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var name = Sanitise.themeName(String(text).trim())
        root.currentTheme = name
        // Captured once per session, at the first open, so Revert always points
        // at what the desktop looked like before Theme Forge touched it rather
        // than at the last thing Theme Forge applied.
        if (root.themeAtOpen === "") root.themeAtOpen = name
      }
    }
  }

  Process {
    id: prefsLoadProc
    command: [root.helperPath, "prefs-load"]
    property bool sawOutput: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        prefsLoadProc.sawOutput = true
        root.loadPrefs(text)
      }
    }
    onExited: function (exitCode) {
      // Whether onExited or onStreamFinished fires first is not ordered, and
      // this used to guard on prefsLoaded -- which the *fallback itself* sets.
      // Winning the race then meant the defaults were applied and the real
      // preferences, arriving a moment later, could not undo a tour that had
      // already been started from them. Guard on whether stdout was seen, which
      // is the actual question being asked.
      if (!prefsLoadProc.sawOutput) root.loadPrefs("")
    }
  }

  Process {
    id: prefsSaveProc
    property string payload: ""
    command: [root.helperPath, "prefs-save"]
    stdinEnabled: true
    onStarted: { write(payload); payload = ""; stdinEnabled = false }
  }

  Process {
    id: draftLoadProc
    command: [root.helperPath, "draft-load"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (text) root.loadDraft(text) }
  }

  Process {
    id: draftSaveProc
    property string payload: ""
    command: [root.helperPath, "draft-save"]
    stdinEnabled: true
    // stdinEnabled is one-way per run in Quickshell: once it goes false the
    // channel is closed for that process, so it is set back to true before each
    // start (in saveDraftNow) or the next write silently does nothing and the
    // helper blocks on a stdin that never ends.
    onStarted: { write(payload); payload = ""; stdinEnabled = false }
  }

  // The desktop portal's own file chooser, reached through the helper's `pick`
  // subcommand rather than run directly.
  //
  // Two reasons for the indirection. Omarchy's omarchy-file-select is the right
  // program -- it is already installed, it holds the D-Bus connection across the
  // portal's directed-signal reply, which no shell-callable client can, and it
  // is the dialog the rest of the desktop uses. But it is another program
  // answering over IPC, and nothing about that makes its output self-limiting,
  // while StdioCollector below retains a process's complete stdout before any
  // signal fires. Putting it behind the helper gives its reply the same byte
  // ceiling every other producer here has, and keeps the argv in one place.
  //
  // Its exit codes pass through unchanged: 1 is "nothing picked", which is a
  // decision rather than a fault, and 2 is "the chooser never ran".
  Process {
    id: pickProc
    command: [root.helperPath, "pick"]
    property string outText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: pickProc.outText = text }
    onExited: function (exitCode) {
      root.busy = false
      if (exitCode === 1) { root.setStatus("Nothing picked.", "info"); return }
      if (exitCode !== 0) { root.setStatus("The file chooser did not open.", "error"); return }
      // The portal hands back file:// URIs, one per line.
      var first = String(pickProc.outText).split("\n")[0].trim()
      if (first.indexOf("file://") === 0) first = decodeURIComponent(first.substring(7))
      var path = Sanitise.absPath(first)
      if (path === "") { root.setStatus("That path is not one this can open.", "error"); return }
      root.sourceImage = path
      root.busy = true
      root.setStatus("Reading the colours out of " + Sanitise.baseName(path) + "...", "info")
      quantizeProc.command = root.helperCommand("quantize", [path, "8"], 40)
      quantizeProc.running = true
    }
  }

  Process {
    id: quantizeProc
    property string outText: ""
    property string errText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: quantizeProc.outText = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: quantizeProc.errText = text }
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.busy = false
        root.sourceImage = ""
        root.setStatus(root.helperError("That image could not be read.", quantizeProc.errText), "error")
        return
      }
      var hexes = Sanitise.hexList(quantizeProc.outText)
      var seeded = Palette.fromImage(hexes, root.spec.mode)
      if (!seeded) {
        root.busy = false
        root.setStatus("No usable colours came out of that image.", "error")
        return
      }
      root.setSpec(seeded)
      root.setStatus("Palette seeded from " + Sanitise.baseName(root.sourceImage) + ".", "ok")
      thumbProc.command = root.helperCommand("thumb", [root.sourceImage], 30)
      thumbProc.running = true
    }
  }

  Process {
    id: thumbProc
    property string outText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: thumbProc.outText = text }
    onExited: function (exitCode) {
      root.busy = false
      if (exitCode !== 0) { root.previewImage = ""; return }
      var path = Sanitise.absPath(String(thumbProc.outText).trim())
      // Only ever a file this plugin wrote, inside the private directory it
      // verified. Image.source resolves whatever it is given -- a bare path, a
      // file:// URL, an image:// provider inside the shell -- so the one place
      // it is set is the one place that has to be certain.
      if (path !== "" && root.scratchDir !== "" && path.indexOf(root.scratchDir + "/") === 0) {
        root.previewImage = path
      } else {
        root.previewImage = ""
      }
    }
  }

  Process {
    id: saveProc
    property string payload: ""
    property string errText: ""
    stdinEnabled: true
    onStarted: { write(payload); payload = ""; stdinEnabled = false }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: saveProc.errText = text }
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.busy = false
        root.applyAfterSave = false
        root.setStatus(root.helperError("The theme could not be written.", saveProc.errText), "error")
        return
      }
      root.startBackgroundStep()
    }
  }

  Process {
    id: wallpaperProc
    property string payload: ""
    property string errText: ""
    stdinEnabled: true
    onStarted: { write(payload); payload = ""; stdinEnabled = false }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: wallpaperProc.errText = text }
    onExited: function (exitCode) {
      // A theme without a wallpaper is still a theme: colors.toml is already on
      // disk and Omarchy will fall back to the current background. Say so and
      // carry on rather than unwinding a save that succeeded.
      if (exitCode !== 0) root.setStatus(root.helperError("The background could not be drawn.", wallpaperProc.errText), "error")
      root.finishSave()
    }
  }

  Process {
    id: adoptProc
    property string errText: ""
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: adoptProc.errText = text }
    onExited: function (exitCode) {
      if (exitCode !== 0) root.setStatus(root.helperError("That image could not be used as a background.", adoptProc.errText), "error")
      root.finishSave()
    }
  }

  Process {
    id: applyProc
    property string errText: ""
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: applyProc.errText = text }
    onExited: function (exitCode) {
      root.busy = false
      if (exitCode !== 0) {
        root.setStatus(root.helperError("omarchy-theme-set refused it.", applyProc.errText), "error")
        return
      }
      currentProc.running = true
      root.setStatus("Applied. Your desktop is wearing it now.", "ok")
    }
  }

  Process {
    id: loadProc
    property string themeName: ""
    property string outText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: loadProc.outText = text }
    onExited: function (exitCode) {
      root.busy = false
      if (exitCode !== 0) { root.setStatus("Could not read that theme.", "error"); return }
      var loaded = Palette.fromToml(loadProc.outText)
      if (!loaded) { root.setStatus("That theme has no colours this can read.", "error"); return }
      root.setSpec(loaded)
      root.themeName = loadProc.themeName
      root.sourceImage = ""
      root.previewImage = ""
      // What happens on Save depends on where the theme came from, and saying
      // "saving will overwrite it" about a theme Omarchy ships would be a
      // promise the helper then refuses to keep.
      var problem = root.nameProblem()
      root.setStatus(problem === ""
        ? "Opened " + loadProc.themeName + ". Saving will overwrite it."
        : "Opened " + loadProc.themeName + ". " + problem + " Give it a new name to keep your changes.",
        "info")
    }
  }

  Component.onCompleted: {
    scratchProc.running = true
    prefsLoadProc.running = true
  }
  // ------------------------------------------------------------------- chrome
  //
  // Theme Forge's own colours come from the Color singleton, which is the
  // *current* theme -- so this window is dark because the user's desktop is,
  // and it repaints the moment they apply something they made here.
  //
  // The window ground is translucent, and the amount is measured rather than
  // picked. Omakade -- the Omarchy-adjacent Qt Quick app this was styled after
  // -- was captured over a pure black and a pure white background and solved
  // for its alpha: (white - black) / 255 came out at 0.13 across channels, so
  // its window sits at about 0.87 once Hyprland's own `default-opacity` tag
  // (0.985 focused / 0.96 unfocused) has been applied on top. Normalising for
  // that tag puts Omakade's own paint at 0.906; this file's 0.90 measures back
  // as 0.903 the same way. The two are within a third of a percent.
  //
  // The same measurement over this window confirms the split holds:
  //
  //   the mock desktop      0.016 transparency  (opaque, only the compositor)
  //   the window ground     0.108               (0.90 x 0.985)
  //   a terminal alongside  0.039               (0.96, the control)
  //
  // Hyprland's tag alone is not enough for this look: 0.96 is a four percent
  // wash, invisible against a dark wallpaper. An app that reads as translucent
  // is painting its own alpha, and this is that alpha.
  //
  // What stays opaque matters more than what does not. Every swatch, and the
  // mock desktop in the preview, is a Rectangle with an explicit colour painted
  // over this ground -- so the colours being judged are composited against the
  // theme's own background and never against the wallpaper behind the window.
  // A translucent preview would make this tool lie about the thing it exists to
  // show.
  readonly property color surface: Qt.rgba(Color.menu.background.r,
                                           Color.menu.background.g,
                                           Color.menu.background.b,
                                           root.surfaceAlpha)
  readonly property color ink: Color.menu.text
  readonly property color dim: Qt.rgba(ink.r, ink.g, ink.b, 0.55)
  readonly property color faint: Qt.rgba(ink.r, ink.g, ink.b, 0.28)
  readonly property color hairline: Qt.rgba(ink.r, ink.g, ink.b, 0.12)
  readonly property string uiFont: Style.font.menuFamily
  readonly property string monoFont: "monospace"

  // A real toplevel window rather than a layer-shell surface.
  //
  // A layer surface floats above everything, never enters the layout, and
  // cannot be tiled, moved or resized -- which is wrong for something you sit
  // in and work. As an ordinary window Hyprland tiles it: alone on a workspace
  // it fills the screen, and beside another window the two split under whatever
  // layout and gaps the user already runs. It also gets the theme's own
  // active-border gradient drawn around it by the compositor, for free.
  //
  // Hyprland sees it as class `org.quickshell`, title `Theme Forge`, which is
  // what a window rule would match on. omarchy.dev-gallery is the first-party
  // plugin built the same way.
  FloatingWindow {
    id: window
    title: "Theme Forge"
    color: root.surface
    implicitWidth: 1180
    implicitHeight: 780
    // Below this the two-column layout has already folded to one and the editor
    // has become a scrolling column; smaller than this is not usable.
    minimumSize: Qt.size(560, 460)

    // The window went away without the host asking -- the user pressed the
    // close button, or the binding their window manager uses for that. Tell the
    // shell so its openPanelIds map stays consistent and the next `toggle`
    // works. (Nothing in this plugin sends a signal to any process.)
    onVisibleChanged: {
      if (!visible && !root.closingFromHost) root.notifyHostClosed()
    }

    FocusScope {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      // AfterItem, so a focused text field keeps its own typing. What is left
      // here are the chords and Escape, which no field consumes.
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) {
          root.requestClose()
          event.accepted = true
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) {
          root.roll()
          event.accepted = true
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) {
          root.save(false)
          event.accepted = true
        } else if ((event.modifiers & Qt.ControlModifier)
                   && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
          root.save(true)
          event.accepted = true
        }
      }

      Item {
        id: content
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding

        // ------------------------------------------------------------ header
        Item {
          id: header
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: titleRow.implicitHeight

          Row {
            id: titleRow
            anchors.left: parent.left
            spacing: Style.space(10)

            Text {
              text: "THEME FORGE"
              textFormat: Text.PlainText
              color: root.ink
              font.family: root.uiFont
              font.pixelSize: Style.font.title
              font.bold: true
              font.letterSpacing: 2
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.currentTheme === "" ? "" : "NOW WEARING " + root.currentTheme.toUpperCase()
              textFormat: Text.PlainText
              color: root.faint
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }
          }

          Row {
            id: headerRight
            anchors.right: parent.right
            anchors.verticalCenter: titleRow.verticalCenter
            spacing: Style.space(14)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              // The first thing to go when the window is narrow: the shortcuts
              // are a reminder, and colliding with the title helps nobody.
              visible: header.width - titleRow.width - headerRight.width + width > Style.space(24)
              text: "CTRL+R ROLL   CTRL+S SAVE   CTRL+ENTER APPLY   ESC CLOSE"
              textFormat: Text.PlainText
              color: root.faint
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }

            RiceButton {
              anchors.verticalCenter: parent.verticalCenter
              text: root.page === "settings" ? "DESIGN" : "SETTINGS"
              fontSize: Style.font.caption
              verticalPadding: Style.space(3)
              horizontalPadding: Style.space(8)
              foreground: root.page === "settings" ? root.colors.accent : root.dim
              accent: root.colors.accent
              selected: root.page === "settings"
              tint: root.surface
              fillAlpha: root.surfaceAlpha
              tooltipText: root.page === "settings"
                ? "Back to the palette"
                : "How Theme Forge behaves"
              onClicked: root.page = root.page === "settings" ? "design" : "settings"
            }
          }
        }

        Rectangle {
          id: topRule
          anchors.top: header.bottom
          anchors.topMargin: Style.spacing.lg
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: root.hairline
        }

        // -------------------------------------------------------------- body
        //
        // Two columns while there is room for two, one when there is not. The
        // window is tiled now, so its width is whatever the user's layout gives
        // it -- half a screen beside another window, a third beside two -- and
        // a layout that only worked at its opening size would be broken most of
        // the time.
        Item {
          id: body
          anchors.top: topRule.bottom
          anchors.topMargin: Style.spacing.lg
          anchors.bottom: bottomRule.top
          anchors.bottomMargin: Style.spacing.lg
          anchors.left: parent.left
          anchors.right: parent.right

          readonly property bool wide: width >= Style.space(880)
          readonly property int gap: Style.spacing.lg
          // Stacked, the preview takes the smaller of its natural proportion
          // and a little under half the height, so the editor always has enough
          // room to be worked in.
          readonly property int stackedPreviewHeight:
            Math.min(Math.round(width * 0.58), Math.round(height * 0.46))

          Settings {
            id: settingsPage
            anchors.fill: parent
            visible: root.page === "settings"
            forge: root
            onClosed: root.page = "design"
            onReplayTutorial: {
              root.page = "design"
              root.startTutorial()
            }
          }

          Editor {
            id: editorPane
            visible: root.page === "design"
            forge: root
            x: 0
            y: body.wide ? 0 : body.stackedPreviewHeight + body.gap
            width: body.wide ? Math.min(Style.space(392), Math.round(body.width * 0.42)) : body.width
            height: body.wide ? body.height : body.height - y
          }

          Rectangle {
            visible: root.page === "design"
            x: body.wide ? editorPane.width + body.gap : 0
            y: body.wide ? 0 : body.stackedPreviewHeight + Math.round(body.gap / 2)
            width: body.wide ? 1 : body.width
            height: body.wide ? body.height : 1
            color: root.hairline
          }

          PreviewPane {
            id: previewPane
            visible: root.page === "design"
            forge: root
            compact: !body.wide
            x: body.wide ? editorPane.width + body.gap * 2 + 1 : 0
            y: 0
            width: body.wide ? body.width - x : body.width
            height: body.wide ? body.height : body.stackedPreviewHeight
          }
        }

        Rectangle {
          id: bottomRule
          anchors.bottom: footer.top
          anchors.bottomMargin: Style.spacing.lg
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: root.hairline
        }

        // ------------------------------------------------------------ footer
        Item {
          id: footer
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: Math.max(statusText.implicitHeight, actions.implicitHeight)

          Text {
            id: statusText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - actions.width - Style.space(16))
            text: root.status === ""
              ? (root.failingCount === 0
                  ? "Every colour is inside its contrast band."
                  : root.failingCount + " colour" + (root.failingCount === 1 ? " is" : "s are") + " outside the contrast band.")
              : root.status
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.statusKind === "error" ? root.colors.red
                 : root.statusKind === "ok" ? root.colors.green
                 : root.dim
            font.family: root.uiFont
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            id: actions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.controlGap

            RiceButton {
              text: "Revert"
              enabled: !root.busy && root.themeAtOpen !== "" && root.themeAtOpen !== root.currentTheme
              tooltipText: root.themeAtOpen === "" ? "" : "Put " + root.themeAtOpen + " back"
              foreground: root.ink
              tint: root.surface
              fillAlpha: root.surfaceAlpha
              onClicked: root.revert()
            }

            RiceButton {
              text: root.overwrites() ? "Overwrite" : "Save"
              enabled: !root.busy
              foreground: root.ink
              tint: root.surface
              fillAlpha: root.surfaceAlpha
              onClicked: root.save(false)
            }

            RiceButton {
              text: "Save and apply"
              enabled: !root.busy
              foreground: root.colors.accent
              accent: root.colors.accent
              selected: true
              tint: root.surface
              fillAlpha: root.surfaceAlpha
              onClicked: root.save(true)
            }
          }
        }

        // ------------------------------------------------------------- the tour
        //
        // Loaded only when it is running: a first-run tour that has been
        // dismissed should not be sitting in the scene graph for the rest of
        // the session. It takes the keyboard while it is up so Escape closes
        // the tour rather than the window.
        Loader {
          id: tourLoader
          anchors.fill: parent
          anchors.margins: -Style.spacing.panelPadding
          active: root.tutorialOpen
          z: 50

          // The content sits inside the window's padding; this Loader has been
          // pushed back out to the window edge, so everything measured in
          // content coordinates moves by that much to land here.
          readonly property int pad: Style.spacing.panelPadding

          sourceComponent: Tutorial {
            forge: root
            // The three things a step can point at, mapped into the tour's own
            // coordinates. Bindings rather than a snapshot, so the spotlight
            // follows the layout when the window is resized or folds.
            editorRect: root.page === "design" && editorPane.visible
              ? Qt.rect(tourLoader.pad + body.x + editorPane.x,
                        tourLoader.pad + body.y + editorPane.y,
                        editorPane.width, editorPane.height)
              : Qt.rect(0, 0, 0, 0)
            previewRect: root.page === "design" && previewPane.visible
              ? Qt.rect(tourLoader.pad + body.x + previewPane.x,
                        tourLoader.pad + body.y + previewPane.y,
                        previewPane.width, previewPane.height)
              : Qt.rect(0, 0, 0, 0)
            actionsRect: Qt.rect(tourLoader.pad + footer.x + actions.x,
                                 tourLoader.pad + footer.y + actions.y,
                                 actions.width, actions.height)
            onFinished: function (suppress) { root.finishTutorial(suppress) }
          }
          onLoaded: item.forceActiveFocus()
          onActiveChanged: if (!active) keyCatcher.forceActiveFocus()
        }
      }
    }
  }
}
