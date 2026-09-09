// Node checks for Palette.js, Sanitise.js and BarStyle.js.
//
// These files carry every decision that can make a generated theme
// unreadable or a generated colors.toml untrustworthy, and neither of them
// touches the filesystem, the network, or a QML type -- so all of it is testable
// here, cheaply, before anything is loaded into a live shell.
//
// tools/check-qml-engine.qml asserts the same properties under Qt's V4 engine,
// which is the engine omarchy-shell actually runs. "It worked in Node" has never
// been evidence about the shell; both suites exist because neither one alone is.
//
//     node tools/check-palette.js
//
// Exit 0 when everything passed.

const fs = require("fs")
const path = require("path")

// Both files are QML .js resources: `.pragma library` at the top, and their
// top-level declarations are what QML exposes to an importer. Node has no such
// notion, so the pragma is stripped and an explicit export list is appended,
// built from the declarations actually present.
function loadResource(relativePath) {
  const source = fs.readFileSync(path.join(__dirname, "..", relativePath), "utf8")
  const body = source.replace(/^\s*\.pragma\s+library\s*/, "")
  const names = []
  const declaration = /^(?:function|var)\s+([A-Za-z_$][\w$]*)/gm
  let match
  while ((match = declaration.exec(body)) !== null) {
    if (names.indexOf(match[1]) === -1) names.push(match[1])
  }
  const exports = names.map((n) => JSON.stringify(n) + ": " + n).join(", ")
  return new Function(body + "\n; return { " + exports + " };")()
}

const P = loadResource("Palette.js")
const S = loadResource("Sanitise.js")
const B = loadResource("BarStyle.js")

const TAB = String.fromCharCode(9)
const NEWLINE = String.fromCharCode(10)
const NUL = String.fromCharCode(0)

let checks = 0
let failures = 0
const seen = new Set()

function ok(condition, label) {
  checks++
  if (condition) return
  failures++
  // One line per distinct failure. A broken solver fails hundreds of cases and
  // a wall of near-identical output buries whatever else also broke.
  const key = label.replace(/\d+(\.\d+)?/g, "N")
  if (seen.has(key)) return
  seen.add(key)
  console.log("FAIL  " + label)
}

function eq(actual, expected, label) {
  ok(actual === expected, label + "  (got " + JSON.stringify(actual) + ", want " + JSON.stringify(expected) + ")")
}

function repeat(text, count) {
  let out = ""
  for (let i = 0; i < count; i++) out += text
  return out
}

// ------------------------------------------------------------- conversions

eq(P.normHex("#AABBCC"), "#aabbcc", "normHex lowercases")
eq(P.normHex("  #aabbcc "), "#aabbcc", "normHex trims")
eq(P.normHex("#abc"), "", "normHex refuses shorthand")
eq(P.normHex("aabbcc"), "", "normHex requires the hash")
eq(P.normHex("#aabbcg"), "", "normHex refuses non-hex digits")
eq(P.normHex(null), "", "normHex survives null")
eq(P.normHex(undefined), "", "normHex survives undefined")
eq(P.normHex("#aabbcc<img src=x>"), "", "normHex refuses trailing markup")
eq(P.normHex("#aabbcc" + NEWLINE + "red = #000000"), "", "normHex refuses a forged second line")

for (const sample of ["#000000", "#ffffff", "#7aa2f7", "#f7768e", "#1a1b26", "#3bbb97", "#808080"]) {
  const hsl = P.hexToHsl(sample)
  eq(P.hslToHex(hsl.h, hsl.s, hsl.l), sample, "hsl round-trips " + sample)
}

// Known WCAG anchors.
ok(Math.abs(P.contrast("#ffffff", "#000000") - 21) < 0.001, "white on black is 21:1")
ok(Math.abs(P.contrast("#7aa2f7", "#7aa2f7") - 1) < 0.001, "a colour against itself is 1:1")
ok(Math.abs(P.contrast("#a9b1d6", "#1a1b26") - P.contrast("#1a1b26", "#a9b1d6")) < 1e-9, "contrast is symmetric")

eq(P.mix("#000000", "#ffffff", 0.5), "#808080", "mix midpoint")
eq(P.mix("#123456", "#abcdef", 0), "#123456", "mix at 0 is the first colour")
eq(P.mix("#123456", "#abcdef", 1), "#abcdef", "mix at 1 is the second colour")

// Shortest arc: 356 pulled all the way to 22 must go forward through 0, not
// backward through 180. A hue lerp that gets this wrong sends the reds green.
ok(Math.abs(P.pullHue(356, 22, 1) - 22) < 0.001, "pullHue takes the short way round")
ok(Math.abs(P.pullHue(10, 350, 0.5) - 0) < 0.001, "pullHue crosses zero cleanly")

// ---------------------------------------------------- the contrast solver

for (const background of ["#000000", "#181a1f", "#1a1b26", "#222222", "#f5f5f5", "#ffffff", "#808080"]) {
  for (const target of [4.5, 6.5, 9.5, 12.0]) {
    for (let hue = 0; hue < 360; hue += 30) {
      const hex = P.solvedHex(hue, 0.7, target, background)
      const got = P.contrast(hex, background)
      // A target can legitimately be unreachable -- a saturated blue cannot hit
      // 12:1 on white at any lightness -- so the solver is allowed to fall
      // short. It is never allowed to overshoot: the band has a ceiling, and
      // exceeding it is the glare failure the band exists to prevent.
      ok(got <= target + 0.15,
        "solver does not overshoot: hue " + hue + " target " + target + " on " + background + " gave " + got.toFixed(2))
    }
  }
}

// ------------------------------------------------------------ derivation

for (let seed = 0; seed < 60; seed++) {
  const palette = P.derive(P.rollSpec(seed, "dark"))
  const bg = palette.background
  const light = P.contrast(palette.light_foreground, bg)
  const normal = P.contrast(palette.foreground, bg)
  const bright = P.contrast(palette.bright_foreground, bg)
  ok(light < normal && normal < bright,
    "seed " + seed + ": foreground ramp is ordered (" +
    light.toFixed(1) + " < " + normal.toFixed(1) + " < " + bright.toFixed(1) + ")")
}

for (const mode of ["dark", "light"]) {
  for (let seed = 0; seed < 250; seed++) {
    const bad = P.failingKeys(P.derive(P.rollSpec(seed, mode)))
    ok(bad.length === 0, mode + " seed " + seed + " is out of band: " + bad.join(", "))
  }
}

for (let seed = 0; seed < 120; seed++) {
  const palette = P.derive(P.rollSpec(seed, "dark"))
  for (const key of P.COLOR_KEYS) {
    ok(P.isHex(palette[key]), "seed " + seed + " key " + key + " is a hex, got " + palette[key])
  }
  ok(/^rgba\([0-9a-f]{8}\) rgba\([0-9a-f]{8}\) 45deg$/.test(palette.hyprland_active_border),
    "active border is a hypr gradient: " + palette.hyprland_active_border)
  ok(/^rgba\([0-9a-f]{8}\)$/.test(palette.hyprland_inactive_border),
    "inactive border is a hypr rgba: " + palette.hyprland_inactive_border)
}

{
  const a = JSON.stringify(P.derive(P.rollSpec(4242, "dark")))
  const b = JSON.stringify(P.derive(P.rollSpec(4242, "dark")))
  eq(a, b, "the same seed gives the same palette")
  ok(a !== JSON.stringify(P.derive(P.rollSpec(4243, "dark"))), "a different seed gives a different palette")
}

for (let seed = 0; seed < 40; seed++) {
  const palette = P.derive(P.rollSpec(seed, "light"))
  ok(P.luminance(palette.background) > 0.6, "light seed " + seed + " has a light ground")
  ok(P.luminance(palette.foreground) < P.luminance(palette.background), "light seed " + seed + " has dark text")
  // On a light theme every surface tone recedes from the ground -- which is what
  // both stock light themes do, and the opposite of what the key names suggest.
  ok(P.luminance(palette.dark_background) < P.luminance(palette.background),
    "light seed " + seed + ": dark_background recedes")
  ok(P.luminance(palette.darker_background) < P.luminance(palette.dark_background),
    "light seed " + seed + ": darker_background recedes further")
  ok(P.luminance(palette.lighter_background) < P.luminance(palette.dark_background) &&
     P.luminance(palette.lighter_background) > P.luminance(palette.darker_background),
    "light seed " + seed + ": lighter_background sits between the other two surfaces")
}

// The same three keys on a dark theme, where lighter_background is a raised
// surface rather than a recessed one.
for (let seed = 0; seed < 40; seed++) {
  const palette = P.derive(P.rollSpec(seed, "dark"))
  ok(P.luminance(palette.dark_background) < P.luminance(palette.background),
    "dark seed " + seed + ": dark_background recedes")
  ok(P.luminance(palette.darker_background) < P.luminance(palette.dark_background),
    "dark seed " + seed + ": darker_background recedes further")
  ok(P.luminance(palette.lighter_background) > P.luminance(palette.background),
    "dark seed " + seed + ": lighter_background is raised")
}

{
  const spec = P.rollSpec(7, "dark")
  spec.overrides = { accent: "#ff00ff", red: "#00ff00" }
  const palette = P.derive(spec)
  eq(palette.accent, "#ff00ff", "a pinned accent survives derivation")
  eq(palette.red, "#00ff00", "a pinned ANSI colour survives derivation")
  eq(palette.selection, P.mix(palette.background, "#ff00ff", 0.30), "selection derives from the pinned accent, not the solved one")

  // A hand-picked foreground is kept exactly, even off its band, and what
  // derives from it derives from the picked colour.
  const dim = P.normSpec(P.defaultSpec())
  dim.overrides = { foreground: "#555555" }
  const dimmed = P.derive(dim)
  eq(dimmed.foreground, "#555555", "a pinned foreground is not re-solved")
  eq(dimmed.dark_foreground, P.mix("#555555", dimmed.background, 0.52), "dark_foreground follows the pinned foreground")
  eq(dimmed.muted, P.mix(dimmed.background, "#555555", 0.40), "muted follows the pinned foreground")
  ok(P.failingKeys(dimmed).indexOf("foreground") !== -1, "and the band check reports it rather than hiding it")
  const faint = P.normSpec(P.defaultSpec())
  faint.overrides = { accent: P.mix(faint.background, "#ffffff", 0.05) }
  eq(P.derive(faint).accent, faint.overrides.accent, "a pinned accent is not lifted even when it has collapsed into the ground")
}

{
  const spec = P.normSpec({
    mode: "sideways",
    background: "not a colour",
    chroma: 5000,
    seed: -12,
    overrides: { accent: "#zzzzzz", "../evil": "#ffffff", red: "#ff0000" }
  })
  eq(spec.mode, "dark", "an unknown mode falls back to dark")
  eq(spec.background, P.defaultSpec().background, "an invalid background falls back")
  eq(spec.chroma, 100, "chroma is clamped high")
  eq(spec.seed, 0, "a negative seed is clamped")
  eq(spec.overrides["../evil"], undefined, "an unknown override key is dropped")
  eq(spec.overrides.accent, undefined, "an invalid override hex is dropped")
  eq(spec.overrides.red, "#ff0000", "a valid override survives")
}

// -------------------------------------------------------------- colors.toml

{
  const palette = P.derive(P.rollSpec(99, "dark"))
  const back = P.fromToml(P.toToml(palette, "test-theme"))
  ok(back !== null, "generated toml parses back")
  const rebuilt = P.derive(back)
  for (const key of P.COLOR_KEYS) eq(rebuilt[key], palette[key], "round-trip preserves " + key)
  eq(rebuilt.mode, palette.mode, "round-trip preserves mode")
}

{
  // Every one of these is a value that would break out of the file if it were
  // written through rather than re-validated at the boundary.
  const palette = P.derive(P.rollSpec(1, "dark"))
  palette.red = '#ff0000"' + NEWLINE + 'hyprland_active_border = "rgba(deadbeef)'
  palette.green = "#00ff00; rm -rf /"
  palette.blue = "<img src=http://example.invalid/x>"
  palette.magenta = "#00ff00" + NUL + "#ffffff"
  const toml = P.toToml(palette, 'inject"test' + NEWLINE + 'mode = "light')

  const allowed = /^(mode = "(dark|light)"|hyprland_active_border = "rgba\([0-9a-f]{8}\) rgba\([0-9a-f]{8}\) 45deg"|hyprland_inactive_border = "rgba\([0-9a-f]{8}\)"|[a-z_]+ = "#[0-9a-f]{6}")$/
  for (const line of toml.split(NEWLINE)) {
    if (line === "" || line.charAt(0) === "#") continue
    ok(allowed.test(line), "no line escapes the hex boundary: " + JSON.stringify(line))
  }
  ok(toml.indexOf("rm -rf") === -1, "a shell fragment never reaches the file")
  ok(toml.indexOf("<img") === -1, "markup never reaches the file")
  ok(toml.split(NEWLINE).filter((l) => l.indexOf("mode = ") === 0).length === 1, "exactly one mode line")
  ok(toml.indexOf('mode = "light"') === -1, "a forged mode line never reaches the file")
  ok(toml.indexOf(NUL) === -1, "a null byte never reaches the file")
}

eq(P.fromToml(""), null, "an empty file yields no spec")
eq(P.fromToml("nonsense"), null, "a non-toml file yields no spec")
eq(P.fromToml('background = "#111111"'), null, "a file missing foreground yields no spec")
ok(P.fromToml('background = "#111111"' + NEWLINE + 'foreground = "#eeeeee"') !== null, "the minimum pair is enough")

// ------------------------------------------------------------ image seeding

{
  const samples = [
    ["#000000", "#050505", "#0a0a0a"],                       // a near-black photo
    ["#ffffff", "#fefefe", "#f8f8f8"],                       // a blown-out one
    ["#8b0000", "#ff4500", "#ffd700", "#2e8b57", "#4682b4"], // a colourful one
    ["#808080", "#828282", "#7f7f7f"]                        // a flat grey one
  ]
  for (let i = 0; i < samples.length; i++) {
    for (const mode of ["dark", "light"]) {
      const spec = P.fromImage(samples[i], mode)
      ok(spec !== null, "image sample " + i + " (" + mode + ") produced a spec")
      const bad = P.failingKeys(P.derive(spec))
      ok(bad.length === 0, "image sample " + i + " (" + mode + ") is readable, out of band: " + bad.join(", "))
    }
  }
  eq(P.fromImage([], "dark"), null, "no colours yields no spec")
  eq(P.fromImage(["not a colour", ""], "dark"), null, "no valid colours yields no spec")
}

// ------------------------------------------------------------- theme names

{
  const refused = [
    "", " ", "../evil", "/etc/passwd", ".hidden", "-leading", "UPPER NAME", "with space",
    "semi;colon", "a" + NEWLINE + "b", "a" + TAB + "b", "a" + NUL + "b", repeat("a", 33),
    "dots.in.name", "sla/sh", 'quote"quote', "$(id)", "`id`", "under_score", "tilde~"
  ]
  for (const name of refused) eq(S.themeName(name), "", "refuses theme name " + JSON.stringify(name))

  for (const name of ["tron", "my-theme", "a", "theme2", "x-1-2-3", repeat("a", 32)]) {
    eq(S.themeName(name), name, "accepts theme name " + name)
  }
  eq(S.themeName("  Tron  "), "tron", "trims and lowercases an otherwise fine name")
}

{
  eq(S.plain("<img src=x>"), " img src=x ", "angle brackets go")
  eq(S.plain("a&b"), "a b", "ampersand goes")
  eq(S.plain("line" + NEWLINE + "break"), "line break", "newlines go")
  eq(S.plain("tab" + TAB + "here"), "tab here", "tabs go")
  eq(S.plain("nul" + NUL + "here"), "nul here", "nulls go")
  eq(S.plain(null), "", "null is empty")
  eq(S.plain(undefined), "", "undefined is empty")
  ok(S.plain(repeat("x", 5000)).length <= 400, "long text is capped")
}

{
  eq(S.absPath("relative/path"), "", "a relative path is refused")
  eq(S.absPath("/etc/passwd" + NEWLINE + "rm -rf /"), "", "a newline in a path is refused")
  eq(S.absPath("/a" + NUL + "b"), "", "a null in a path is refused")
  eq(S.absPath("/home/u/pic.png"), "/home/u/pic.png", "an ordinary absolute path is kept")
  eq(S.absPath("/home/u/my pic (1).png"), "/home/u/my pic (1).png", "spaces and brackets are kept")
  eq(S.absPath("/" + repeat("x", 5000)), "", "an over-long path is refused")
  eq(S.absPath(""), "", "empty is refused")
  eq(S.baseName("/home/u/holiday <2019>.png"), "holiday  2019 .png", "baseName is display-safe")
}

{
  eq(S.hexList("#AABBCC" + NEWLINE + "junk" + NEWLINE + "#112233" + NEWLINE + "#AABBCC").join(","),
    "#aabbcc,#112233", "hexList normalises, filters and de-duplicates")
  eq(S.hexList("#AABBC").length, 0, "a truncated final line contributes nothing")
  ok(S.hexList(repeat("#aabbcc" + NEWLINE, 500)).length <= 24, "hexList is row-capped")
  eq(S.nameList("tron" + NEWLINE + "../evil" + NEWLINE + "Tokyo Night" + NEWLINE + "nord").join(","),
    "tron,nord", "nameList applies the same guard per row")
}

// ------------------------------------------------------ variety and chaos

{
  // The ANSI ramp varies with the seed but stays itself: each bright is still
  // brighter than its base, every roll is still in band, and red stays red.
  const redHues = new Set()
  const pulls = new Set()
  for (let seed = 0; seed < 80; seed++) {
    const palette = P.derive(P.rollSpec(seed, "dark"))
    const bg = palette.background
    for (const bright in P.BRIGHT_OF) {
      const base = P.BRIGHT_OF[bright]
      ok(P.contrast(palette[bright], bg) > P.contrast(palette[base], bg),
        "seed " + seed + ": " + bright + " is brighter than " + base)
    }
    const red = P.hexToHsl(palette.red).h
    redHues.add(Math.round(red))
    ok(red <= 16 || red >= 336, "seed " + seed + ": red is still red (" + Math.round(red) + "deg)")
    const yellow = P.hexToHsl(palette.yellow).h
    ok(yellow >= 24 && yellow <= 64, "seed " + seed + ": yellow is still yellow (" + Math.round(yellow) + "deg)")
    const green = P.hexToHsl(palette.green).h
    ok(green >= 118 && green <= 158, "seed " + seed + ": green is still green (" + Math.round(green) + "deg)")
    pulls.add(Math.round(P.hexToHsl(palette.blue).h))
  }
  ok(redHues.size > 10, "red takes many hues across seeds, not one (" + redHues.size + ")")
  ok(pulls.size > 10, "blue takes many hues across seeds, not one (" + pulls.size + ")")
  const same = P.normSpec(P.rollSpec(77, "dark"))
  eq(JSON.stringify(P.derive(same)), JSON.stringify(P.derive(same)), "variety is seeded, so the same spec derives the same palette")

  // Chaos: twenty-six colours from the whole cube, reproducible per seed.
  const chaos = P.chaosSpec(4242, "dark")
  for (const key of P.COLOR_KEYS) ok(P.isHex(chaos.overrides[key]), "chaos sets " + key)
  eq(chaos.background, chaos.overrides.background, "chaos ground is the override it shows")
  const derived = P.derive(chaos)
  for (const key of P.COLOR_KEYS) eq(derived[key], chaos.overrides[key], "chaos " + key + " derives to exactly itself")
  eq(JSON.stringify(P.chaosSpec(4242, "dark")), JSON.stringify(chaos), "chaos is reproducible per seed")
  ok(JSON.stringify(P.chaosSpec(4243, "dark")) !== JSON.stringify(chaos), "and a different seed differs")
  eq(P.chaosSpec(1, "light").mode, "light", "chaos keeps the mode")
  eq(P.chaosSpec("junk", "dark").seed, 0, "a bad seed is clamped")
}

// ---------------------------------------------------- readable surfaces

{
  eq(P.contrastSurface("#101315", "#cacccc", "#7aa2f7"), "#101315", "a readable ground is kept as the surface")
  eq(P.contrastSurface("#ffffff", "#ffffff", "#ffffff"), "#000000", "white text on white falls back to black")
  eq(P.contrastSurface("#000000", "#000000", "#000000"), "#ffffff", "black text on black falls back to white")
  eq(P.contrastSurface("junk", "#ffffff", "#ffffff"), "#000000", "a malformed ground is treated as black")

  const lifted = P.readableAlpha("#000000", "#ffffff", 0.5)
  ok(lifted > 0.5 && lifted <= 1, "readableAlpha lifts a half-transparent dark surface until white text reads on it (" + lifted + ")")
  ok(P.contrast("#ffffff", P.mix("#ffffff", "#000000", lifted)) >= 4.5, "the lifted alpha actually reads over white")
  eq(P.readableAlpha("#000000", "#ffffff", 1), 1, "an opaque surface is left opaque")
  eq(P.readableAlpha("#808080", "#808080", 0.3), 1, "text the colour of its surface cannot be rescued, and says so with 1")
  for (const requested of [0, 0.2, 0.456, 0.878, 1]) {
    const alpha = P.readableAlpha("#181a1f", "#cacccc", requested)
    ok(alpha >= requested - 1e-9 && alpha <= 1, "readableAlpha never goes below what was asked for at " + requested)
  }
}

// ------------------------------------------------------------- the bar

{
  const stock = B.resolve(null)
  eq(stock.position, "top", "no config is a top bar")
  eq(stock.transparent, false, "no config is a solid bar")
  eq(stock.widgets.left[0], "omarchy.menu", "the stock bar starts with the menu")
  eq(B.describe(stock), "top, solid", "the stock bar is described plainly")
  eq(B.describe(null), "stock Omarchy bar", "describe survives nothing at all")

  const layout = {
    left: [{ id: "omarchy.menu" }, { id: "omarchy.workspaces" }, { id: "omarchy.spacer" }],
    center: [{ id: "omarchy.clock", format: "dddd HH:mm", verticalFormat: "HH" + NEWLINE + "mm" }],
    right: [{ id: "omarchy.tray" }, { id: "omarchy.power" }]
  }
  const plain = B.resolve({ position: "bottom", transparent: true, layout: layout })
  eq(plain.position, "bottom", "position is read")
  eq(plain.vertical, false, "bottom is horizontal")
  eq(plain.transparent, true, "transparency is read")
  eq(plain.widgets.left.join(","), "omarchy.menu,omarchy.workspaces", "a spacer draws nothing and is dropped")
  eq(plain.widgets.right.length, 2, "the right section keeps its widgets")
  eq(plain.clockFormat, "dddd HH:mm", "the clock format is read")
  eq(plain.clockFormatVertical, "HH" + NEWLINE + "mm", "a newline in the vertical format is kept")
  eq(B.describe(plain), "bottom, see-through", "a transparent bar is described as see-through")

  eq(B.resolve({ position: " LEFT " }).vertical, true, "position is trimmed and lowercased")
  eq(B.resolve({ position: "sideways" }).position, "top", "an unknown position is the top")
  eq(B.resolve({ position: "right" }).vertical, true, "right is vertical")
  eq(B.resolve("nonsense").position, "top", "a non-object config is the stock bar")
  eq(B.resolve({ layout: "nonsense" }).widgets.center[0], "omarchy.clock", "a non-object layout keeps the stock widgets")
  eq(B.resolve({ layout: { left: "nope" } }).widgets.left.length, 0, "a non-array section is empty")

  const foreign = B.resolve({ id: "someone.other-bar", layout: layout })
  eq(foreign.foreign, "someone.other-bar", "a different bar plugin is noticed")
  ok(B.describe(foreign).indexOf("cannot draw") !== -1, "and said so in the description")
  eq(B.resolve({ id: "omarchy.bar" }).foreign, "", "the stock bar id is not foreign")

  // Bounds. A layout is the user's own file, but a hostile one must still
  // produce something small.
  const many = []
  for (let i = 0; i < 40; i++) many.push({ id: "some.widget" + i })
  many.push({ id: "../evil" })
  many.push({ id: repeat("x", 300) })
  many.push({ id: "" })
  many.push("not-an-object")
  const capped = B.resolve({ layout: { left: many } })
  eq(capped.widgets.left.length, 8, "a section is capped at eight widgets")
  ok(capped.widgets.left.every((id) => /^[A-Za-z0-9._-]{1,80}$/.test(id)), "every kept id is a plain id")

  eq(B.clockFormat("HH" + TAB + ":mm" + NUL, "x"), "HH:mm", "control characters are stripped from a clock format")
  eq(B.clockFormat(repeat("d", 41), "x"), "x", "an over-long format falls back")
  eq(B.clockFormat("", "x"), "x", "an empty format falls back")
  eq(B.clockFormat(null, "x"), "x", "a missing format falls back")

}

// --------------------------------------------------------------- icons.theme
//
// The helper re-checks whatever this returns against its own whitelist before
// it becomes the contents of a file Omarchy hands to gsettings, so the only
// thing that matters here is that the answer is always on that list.

eq(P.iconTheme("#89b4fa"), "Yaru-blue", "a blue accent picks the blue icons")
eq(P.iconTheme("#e53935"), "Yaru-red", "a red accent picks the red icons")
eq(P.iconTheme("#f38ba8"), "Yaru-magenta", "a pink accent picks the magenta icons")
eq(P.iconTheme("#a6e3a1"), "Yaru-sage", "a green accent picks the sage icons")
eq(P.iconTheme("#f9e2af"), "Yaru-yellow", "a yellow accent picks the yellow icons")
eq(P.iconTheme("#cba6f7"), "Yaru-purple", "a violet accent picks the purple icons")
eq(P.iconTheme("#2dd5b7"), "Yaru-prussiangreen", "a teal accent picks prussiangreen")
eq(P.iconTheme("#a2734b"), "Yaru-wartybrown", "an orange-brown accent picks wartybrown")

// A near-grey has no hue worth naming, and neither has a value that is not a
// colour at all. Both land on Omarchy's own fallback rather than on whichever
// band the rounding noise happened to reach.
eq(P.iconTheme("#808080"), "Yaru-blue", "a grey accent falls back")
eq(P.iconTheme("#ffffff"), "Yaru-blue", "white falls back")
eq(P.iconTheme("#000000"), "Yaru-blue", "black falls back")
eq(P.iconTheme(""), "Yaru-blue", "an empty accent falls back")
eq(P.iconTheme(null), "Yaru-blue", "a null accent falls back")
eq(P.iconTheme("Yaru-evil; rm -rf /"), "Yaru-blue", "a non-colour falls back")

// The whole hue circle, and every rolled palette, stays inside the list the
// helper will accept. This is the property that actually matters.
{
  let offList = 0
  for (let hue = 0; hue < 360; hue++) {
    if (P.ICON_THEMES.indexOf(P.iconTheme(P.hslToHex(hue, 0.7, 0.55))) === -1) offList++
  }
  eq(offList, 0, "every hue maps to an icon set the helper accepts")

  let rolledOff = 0
  for (let seed = 0; seed < 120; seed++) {
    const dark = P.derive(P.rollSpec(seed, "dark"))
    const light = P.derive(P.rollSpec(seed, "light"))
    if (P.ICON_THEMES.indexOf(P.iconTheme(dark.accent)) === -1) rolledOff++
    if (P.ICON_THEMES.indexOf(P.iconTheme(light.accent)) === -1) rolledOff++
  }
  eq(rolledOff, 0, "every rolled accent maps to an icon set the helper accepts")

  // Deterministic, like everything else a seed reproduces.
  eq(P.iconTheme(P.derive(P.rollSpec(7, "dark")).accent),
     P.iconTheme(P.derive(P.rollSpec(7, "dark")).accent),
     "the same accent always picks the same icon set")

  ok(P.ICON_THEMES.every((n) => /^Yaru(-[a-z]+)?$/.test(n)), "every listed icon set is a plain Yaru name")
}

console.log((failures === 0 ? "PASS" : "FAIL") + "  " + (checks - failures) + "/" + checks + " checks")
process.exit(failures === 0 ? 0 : 1)
