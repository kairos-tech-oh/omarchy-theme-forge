// Node checks for Palette.js and Sanitise.js.
//
// These two files carry every decision that can make a generated theme
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

console.log((failures === 0 ? "PASS" : "FAIL") + "  " + (checks - failures) + "/" + checks + " checks")
process.exit(failures === 0 ? 0 : 1)
