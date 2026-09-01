.pragma library

// Theme Forge — all of the colour maths, and nothing else.
//
// Pure functions over strings and numbers. No I/O, no Process, no QML types, so
// the whole file runs unchanged under `node` and `qmljs` and is covered by
// tools/check-palette.js. That is deliberate: this is the part of the plugin
// most likely to be wrong, and it is the part cheapest to test.
//
// The shape of a theme is one flat map of `key -> "#rrggbb"`, which is what
// omarchy-theme-set reads out of colors.toml before regenerating alacritty,
// btop, neovim, hyprland, vscode and the shell's own palette from it. Producing
// a complete desktop theme is therefore exactly the job of producing the 26
// good hex values below.

// ---------------------------------------------------------------- key order
//
// The order colors.toml is written in. Matches the stock themes so a diff
// against one reads cleanly.
var COLOR_KEYS = [
  "accent", "selection", "muted",
  "background", "dark_background", "darker_background", "lighter_background",
  "foreground", "dark_foreground", "light_foreground", "bright_foreground",
  "red", "yellow", "orange", "green", "cyan", "blue", "magenta", "brown",
  "bright_red", "bright_yellow", "bright_green",
  "bright_cyan", "bright_blue", "bright_magenta"
]

var GRADIENT_KEYS = ["hyprland_active_border", "hyprland_inactive_border"]

// ------------------------------------------------------------ contrast bands
//
// Ported from ~/.config/omarchy/themes/tron/tools/check-contrast.py. The gate is
// a *band*, not a floor: the floors are WCAG AA with headroom, and the ceilings
// exist because neon-on-black at 13-18:1 is a glare source in a terminal you
// read for hours. Chrome sits behind or beside content, or is a lit edge meant
// to stand out, so the band does not apply to it.
var FG_BAND = [6.0, 13.5]
var ANSI_BAND = [4.5, 9.5]

var FOREGROUND_KEYS = ["foreground", "bright_foreground", "light_foreground"]
var ANSI_KEYS = [
  "red", "yellow", "orange", "green", "cyan", "blue", "magenta",
  "bright_red", "bright_yellow", "bright_green",
  "bright_cyan", "bright_blue", "bright_magenta"
]
var CHROME_KEYS = [
  "accent", "selection", "muted", "brown", "dark_foreground",
  "dark_background", "darker_background", "lighter_background", "background"
]

// Rather than nudging a colour until it merely lands inside its band, every
// managed key is solved to an explicit target ratio. Two reasons: the result is
// deterministic for a given seed, and the targets are ordered, so
// light < normal < bright holds by construction instead of by luck. A pass that
// only clamped into the band could legally emit a bright_foreground dimmer than
// its foreground.
var TARGET = {
  light_foreground: 7.0,
  foreground: 9.5,
  bright_foreground: 12.0,

  red: 6.4, orange: 6.6, yellow: 6.9, green: 6.6,
  cyan: 6.5, blue: 6.1, magenta: 6.2,

  bright_red: 8.1, bright_yellow: 8.6, bright_green: 8.3,
  bright_cyan: 8.2, bright_blue: 7.9, bright_magenta: 8.0
}

// Base hue anchors, in degrees. Each is pulled a little toward the theme's
// accent hue during derivation so a palette reads as one family rather than as
// a stock ANSI ramp dropped onto a coloured background.
var HUE = {
  red: 356, orange: 22, yellow: 44, green: 138,
  cyan: 184, blue: 212, magenta: 278
}

var BRIGHT_OF = {
  bright_red: "red", bright_yellow: "yellow", bright_green: "green",
  bright_cyan: "cyan", bright_blue: "blue", bright_magenta: "magenta"
}

// --------------------------------------------------------------- conversions

function clamp(value, lo, hi) {
  var v = Number(value)
  if (!isFinite(v)) return lo
  return v < lo ? lo : (v > hi ? hi : v)
}

// The one place a string is admitted as a colour. Everything downstream may
// assume "#rrggbb", lowercase, exactly seven characters.
function normHex(value) {
  var m = /^#([0-9a-fA-F]{6})$/.exec(String(value === undefined || value === null ? "" : value).trim())
  return m ? "#" + m[1].toLowerCase() : ""
}

function isHex(value) {
  return normHex(value) !== ""
}

function hexToRgb(hex) {
  var clean = normHex(hex)
  if (clean === "") return null
  var n = parseInt(clean.substring(1), 16)
  return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 }
}

function rgbToHex(r, g, b) {
  function pair(v) {
    var s = Math.round(clamp(v, 0, 255)).toString(16)
    return s.length < 2 ? "0" + s : s
  }
  return "#" + pair(r) + pair(g) + pair(b)
}

function rgbToHsl(r, g, b) {
  var rr = clamp(r, 0, 255) / 255, gg = clamp(g, 0, 255) / 255, bb = clamp(b, 0, 255) / 255
  var max = Math.max(rr, gg, bb), min = Math.min(rr, gg, bb)
  var l = (max + min) / 2
  var h = 0, s = 0
  if (max !== min) {
    var d = max - min
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
    if (max === rr) h = (gg - bb) / d + (gg < bb ? 6 : 0)
    else if (max === gg) h = (bb - rr) / d + 2
    else h = (rr - gg) / d + 4
    h *= 60
  }
  return { h: h, s: s, l: l }
}

function hslToRgb(h, s, l) {
  var hh = ((Number(h) % 360) + 360) % 360
  var ss = clamp(s, 0, 1), ll = clamp(l, 0, 1)
  if (ss === 0) {
    var g = ll * 255
    return { r: g, g: g, b: g }
  }
  var q = ll < 0.5 ? ll * (1 + ss) : ll + ss - ll * ss
  var p = 2 * ll - q
  function channel(t) {
    var tt = t
    if (tt < 0) tt += 1
    if (tt > 1) tt -= 1
    if (tt < 1 / 6) return p + (q - p) * 6 * tt
    if (tt < 1 / 2) return q
    if (tt < 2 / 3) return p + (q - p) * (2 / 3 - tt) * 6
    return p
  }
  var hk = hh / 360
  return {
    r: channel(hk + 1 / 3) * 255,
    g: channel(hk) * 255,
    b: channel(hk - 1 / 3) * 255
  }
}

function hexToHsl(hex) {
  var rgb = hexToRgb(hex)
  if (!rgb) return { h: 0, s: 0, l: 0 }
  return rgbToHsl(rgb.r, rgb.g, rgb.b)
}

function hslToHex(h, s, l) {
  var rgb = hslToRgb(h, s, l)
  return rgbToHex(rgb.r, rgb.g, rgb.b)
}

// WCAG 2.1 relative luminance, and the ratio built from it. Both lifted from
// the Tron theme's own contrast checker so the numbers this plugin reports and
// the numbers that theme was tuned against are the same numbers.
function luminance(hex) {
  var rgb = hexToRgb(hex)
  if (!rgb) return 0
  var chan = [rgb.r / 255, rgb.g / 255, rgb.b / 255].map(function (c) {
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
  })
  return 0.2126 * chan[0] + 0.7152 * chan[1] + 0.0722 * chan[2]
}

function contrast(a, b) {
  var la = luminance(a), lb = luminance(b)
  var hi = Math.max(la, lb), lo = Math.min(la, lb)
  return (hi + 0.05) / (lo + 0.05)
}

function mix(a, b, amount) {
  var ra = hexToRgb(a), rb = hexToRgb(b)
  if (!ra || !rb) return normHex(a) || "#000000"
  var t = clamp(amount, 0, 1)
  return rgbToHex(
    ra.r + (rb.r - ra.r) * t,
    ra.g + (rb.g - ra.g) * t,
    ra.b + (rb.b - ra.b) * t
  )
}

// Shortest-arc interpolation between two hues, so pulling 356 toward 22 goes
// forward through 0 rather than backward through 180.
function pullHue(from, toward, amount) {
  var a = ((Number(from) % 360) + 360) % 360
  var b = ((Number(toward) % 360) + 360) % 360
  var delta = b - a
  if (delta > 180) delta -= 360
  if (delta < -180) delta += 360
  return ((a + delta * clamp(amount, 0, 1)) % 360 + 360) % 360
}

// ------------------------------------------------------------ contrast solver
//
// Find the lightness at which a colour of the given hue and saturation hits a
// target contrast ratio against the background.
//
// Contrast against a fixed background is monotonic in lightness on each side of
// that background's own lightness, so a bisection over the correct side always
// converges and never has to guess. Which side is "correct" is decided by the
// background's luminance, not by the declared mode: a theme whose author typed a
// pale hex into a dark-mode palette still needs readable text.
function solveLightness(hue, sat, target, background) {
  var bgLum = luminance(background)
  var bgL = hexToHsl(background).l
  var goLighter = bgLum < 0.5
  var lo = goLighter ? bgL : 0.0
  var hi = goLighter ? 1.0 : bgL

  function ratioAt(l) { return contrast(hslToHex(hue, sat, l), background) }

  // Best reachable on this side. If even the extreme cannot make the target,
  // desaturating buys real headroom -- a fully saturated blue simply cannot be
  // bright enough -- so try once at half chroma before giving up on the extreme.
  var extreme = goLighter ? hi : lo
  if (ratioAt(extreme) < target) {
    if (sat > 0.08) return solveLightness(hue, sat * 0.5, target, background)
    return { l: extreme, sat: sat, reached: false }
  }

  for (var i = 0; i < 48; i++) {
    var mid = (lo + hi) / 2
    var r = ratioAt(mid)
    // On the lighter side ratio grows with l; on the darker side it shrinks.
    if (goLighter ? (r < target) : (r > target)) lo = mid
    else hi = mid
  }
  return { l: (lo + hi) / 2, sat: sat, reached: true }
}

function solvedHex(hue, sat, target, background) {
  var s = solveLightness(hue, sat, target, background)
  return hslToHex(hue, s.sat, s.l)
}

// ------------------------------------------------------------------ the spec
//
// What the user actually manipulates. Everything else in a theme is derived
// from these six values plus any per-key overrides they have pinned by hand.
function defaultSpec() {
  return {
    mode: "dark",
    background: "#181a1f",
    foreground: "#c3c8d1",
    accent: "#7aa2f7",
    chroma: 62,
    seed: 0,
    overrides: {}
  }
}

function normSpec(input) {
  var d = defaultSpec()
  var s = (input && typeof input === "object") ? input : {}
  var out = {
    mode: s.mode === "light" ? "light" : "dark",
    background: normHex(s.background) || d.background,
    foreground: normHex(s.foreground) || d.foreground,
    accent: normHex(s.accent) || d.accent,
    chroma: Math.round(clamp(s.chroma === undefined ? d.chroma : s.chroma, 0, 100)),
    seed: Math.floor(clamp(s.seed === undefined ? 0 : s.seed, 0, 999999)),
    overrides: {}
  }
  // Overrides are read back from a file the user can edit, so each one is
  // re-validated against the known key list rather than trusted as a map.
  var src = (s.overrides && typeof s.overrides === "object") ? s.overrides : {}
  for (var i = 0; i < COLOR_KEYS.length; i++) {
    var key = COLOR_KEYS[i]
    var value = normHex(src[key])
    if (value !== "") out.overrides[key] = value
  }
  return out
}

// --------------------------------------------------------------- derivation

function derive(specInput) {
  var spec = normSpec(specInput)
  var p = {}
  var bg = spec.background
  var bgHsl = hexToHsl(bg)
  var dark = spec.mode !== "light"

  // Backgrounds. `dark_background` and `darker_background` are recessed surfaces
  // in both modes -- tokyo-night runs -0.032 / -0.063 off its base, and
  // catppuccin-latte runs -0.055 / -0.096 off its own, in the same direction.
  //
  // `lighter_background` is the one that is not symmetric, and reading it as
  // "background, but lighter" is wrong in half of all themes. It is the raised
  // surface: lighter than the ground on a dark theme, and on a light theme a
  // *third* recessed tone sitting between the other two (latte: base .951,
  // dark .896, lighter .882, darker .855). Both stock light themes agree, so
  // the name is historical and the behaviour is what it has to match.
  p.background = bg
  p.dark_background = hslToHex(bgHsl.h, bgHsl.s, clamp(bgHsl.l - (dark ? 0.032 : 0.055), 0, 1))
  p.darker_background = hslToHex(bgHsl.h, bgHsl.s, clamp(bgHsl.l - (dark ? 0.063 : 0.096), 0, 1))
  p.lighter_background = dark
    ? hslToHex(bgHsl.h, bgHsl.s * 1.05, clamp(bgHsl.l + 0.058, 0, 1))
    : hslToHex(bgHsl.h, bgHsl.s * 1.05, clamp(bgHsl.l - 0.069, 0, 1))

  // Foreground ramp. Hue and saturation come from the user's foreground; only
  // lightness is solved, so the tint they picked survives the contrast pass.
  var fgHsl = hexToHsl(spec.foreground)
  p.foreground = solvedHex(fgHsl.h, fgHsl.s, TARGET.foreground, bg)
  p.light_foreground = solvedHex(fgHsl.h, fgHsl.s * 0.92, TARGET.light_foreground, bg)
  p.bright_foreground = solvedHex(fgHsl.h, fgHsl.s * 0.85, TARGET.bright_foreground, bg)
  p.dark_foreground = mix(p.foreground, bg, 0.52)

  // Accent is chrome and is the user's to choose, but an accent that vanishes
  // into the background stops being an accent. Lift it only if it has actually
  // collapsed -- never clamp a strong one down.
  var accentHsl = hexToHsl(spec.accent)
  p.accent = contrast(spec.accent, bg) < 2.6
    ? solvedHex(accentHsl.h, accentHsl.s, 3.4, bg)
    : spec.accent

  p.selection = mix(bg, p.accent, 0.30)
  p.muted = mix(bg, p.foreground, 0.40)

  // Brown is chrome in every stock theme -- a dark warm tone, well below the
  // ANSI band (tokyo-night's is 2.9:1). Derived, not solved.
  p.brown = hslToHex(24, 0.34, clamp(bgHsl.l + (dark ? 0.16 : -0.16), 0.05, 0.95))

  // The ANSI ramp. Each anchor is pulled 14% toward the accent hue so the ramp
  // belongs to this palette, then solved for its target contrast at the theme's
  // chroma level.
  var sat = clamp(0.30 + 0.55 * (spec.chroma / 100), 0.05, 0.95)
  var accentHue = accentHsl.h
  var i, key, hue

  for (key in HUE) {
    if (!HUE.hasOwnProperty(key)) continue
    hue = pullHue(HUE[key], accentHue, 0.14)
    p[key] = solvedHex(hue, sat, TARGET[key], bg)
  }

  for (key in BRIGHT_OF) {
    if (!BRIGHT_OF.hasOwnProperty(key)) continue
    hue = pullHue(HUE[BRIGHT_OF[key]], accentHue, 0.14)
    p[key] = solvedHex(hue, sat * 0.94, TARGET[key], bg)
  }

  // Hyprland's lit window edge, and the shell's popup/menu/notification borders
  // with it. Written in the gradient form the stock themes use; the templates
  // parse it with `hypr_gradient`, so anything else here is dropped silently.
  p.hyprland_active_border = "rgba(" + strip(p.accent) + "dd) rgba(" + strip(p.bright_foreground) + "dd) 45deg"
  p.hyprland_inactive_border = "rgba(" + strip(p.selection) + "99)"

  // Manual pins win over everything derived. Applied last so a user who has
  // fixed one swatch keeps it while the rest of the palette moves under it.
  for (i = 0; i < COLOR_KEYS.length; i++) {
    var k = COLOR_KEYS[i]
    if (spec.overrides[k]) p[k] = spec.overrides[k]
  }

  p.mode = spec.mode
  return p
}

function strip(hex) {
  var clean = normHex(hex)
  return clean === "" ? "000000" : clean.substring(1)
}

// ------------------------------------------------------------------- report
//
// What the contrast strip in the UI renders, and what check-palette.js asserts
// against. Chrome is listed as exempt rather than omitted, so the panel can show
// the whole palette without implying an unchecked colour was checked.
function report(palette) {
  var rows = []
  var bg = palette.background
  function push(key, band) {
    var value = palette[key]
    if (!isHex(value)) return
    var ratio = contrast(value, bg)
    rows.push({
      key: key,
      hex: value,
      ratio: ratio,
      exempt: band === null,
      ok: band === null ? true : (ratio >= band[0] && ratio <= band[1]),
      low: band !== null && ratio < band[0],
      high: band !== null && ratio > band[1]
    })
  }
  var i
  for (i = 0; i < FOREGROUND_KEYS.length; i++) push(FOREGROUND_KEYS[i], FG_BAND)
  for (i = 0; i < ANSI_KEYS.length; i++) push(ANSI_KEYS[i], ANSI_BAND)
  for (i = 0; i < CHROME_KEYS.length; i++) push(CHROME_KEYS[i], null)
  return rows
}

function failingKeys(palette) {
  var rows = report(palette)
  var bad = []
  for (var i = 0; i < rows.length; i++) if (!rows[i].ok) bad.push(rows[i].key)
  return bad
}

// -------------------------------------------------------------- randomizer
//
// mulberry32: small, fast, and identical under node and Qt's JS engine, which is
// what makes a seed reproducible across the test suite and the running shell.
function mulberry32(seed) {
  var a = seed >>> 0
  return function () {
    a = (a + 0x6D2B79F5) >>> 0
    var t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

var SCHEMES = ["analogous", "triad", "split", "complement", "mono"]

function accentHueFor(scheme, baseHue, rnd) {
  switch (scheme) {
    case "analogous": return baseHue + (rnd() < 0.5 ? -1 : 1) * (22 + rnd() * 26)
    case "triad": return baseHue + (rnd() < 0.5 ? 120 : 240)
    case "split": return baseHue + (rnd() < 0.5 ? 150 : 210)
    case "complement": return baseHue + 180
    default: return baseHue + (rnd() - 0.5) * 10
  }
}

// A roll respects the mode the user is in. Someone working on a light theme who
// presses randomize wants another light theme, not a coin flip.
function randomSpec(seed, mode) {
  var s = Math.floor(clamp(seed, 0, 999999))
  var rnd = mulberry32(s + 1)
  var dark = mode !== "light"
  var scheme = SCHEMES[Math.floor(rnd() * SCHEMES.length) % SCHEMES.length]

  var baseHue = rnd() * 360
  var accentHue = accentHueFor(scheme, baseHue, rnd)

  var bgSat = 0.03 + rnd() * 0.17
  var bgL = dark ? (0.065 + rnd() * 0.085) : (0.905 + rnd() * 0.065)
  var background = hslToHex(baseHue, bgSat, bgL)

  // Foreground sits near the background's hue for a tinted-neutral read, and
  // occasionally on the accent's for a stronger one.
  var fgHue = rnd() < 0.72 ? baseHue : accentHue
  var fgSat = 0.05 + rnd() * 0.28
  var foreground = solvedHex(fgHue, fgSat, TARGET.foreground, background)

  var accent = solvedHex(accentHue, 0.42 + rnd() * 0.44, 4.4 + rnd() * 2.6, background)

  return normSpec({
    mode: dark ? "dark" : "light",
    background: background,
    foreground: foreground,
    accent: accent,
    chroma: Math.round(34 + rnd() * 56),
    seed: s,
    overrides: {}
  })
}

// Roll until the derived palette actually passes its own bands. In practice the
// solver lands it first time; the loop exists because an extreme background can
// leave a target unreachable, and shipping a palette we know fails would make
// the contrast strip a decoration rather than a gate.
function rollSpec(seed, mode) {
  var s = Math.floor(clamp(seed, 0, 999999))
  for (var attempt = 0; attempt < 24; attempt++) {
    var candidate = randomSpec((s + attempt * 7919) % 1000000, mode)
    if (failingKeys(derive(candidate)).length === 0) return candidate
  }
  return randomSpec(s, mode)
}

function randomSeed() {
  return Math.floor(Math.random() * 1000000)
}

// -------------------------------------------------- palette from an image
//
// Takes the dominant colours ImageMagick found and turns them into a spec. The
// image chooses hue and energy; the contrast solver still decides every
// lightness, so a muddy photograph cannot produce an unreadable terminal.
function fromImage(hexes, mode) {
  var dark = mode !== "light"
  var pool = []
  var i
  for (i = 0; i < hexes.length; i++) {
    var hex = normHex(hexes[i])
    if (hex === "") continue
    var hsl = hexToHsl(hex)
    pool.push({ hex: hex, h: hsl.h, s: hsl.s, l: hsl.l, lum: luminance(hex) })
  }
  if (pool.length === 0) return null

  // Ground: the darkest sample for a dark theme, the lightest for a light one.
  // Its hue is kept, its saturation is capped so the desktop is a tinted
  // neutral rather than a colour field, and its lightness is replaced outright.
  var ground = pool[0]
  for (i = 1; i < pool.length; i++) {
    if (dark ? (pool[i].lum < ground.lum) : (pool[i].lum > ground.lum)) ground = pool[i]
  }
  var bgSat = Math.min(ground.s, 0.20)
  var bgL = dark ? clamp(0.07 + ground.s * 0.03, 0.05, 0.16) : clamp(0.94 - ground.s * 0.03, 0.86, 0.97)
  var background = hslToHex(ground.h, bgSat, bgL)

  // Accent: the most colourful sample that is not the ground. Weighted toward
  // mid lightness, because a near-black or near-white sample carries hue
  // unreliably however saturated it claims to be.
  var accentSrc = null, bestScore = -1
  for (i = 0; i < pool.length; i++) {
    var midness = 1 - Math.abs(pool[i].l - 0.5) * 2
    var score = pool[i].s * (0.35 + 0.65 * midness)
    if (score > bestScore) { bestScore = score; accentSrc = pool[i] }
  }
  var accent = solvedHex(accentSrc.h, clamp(accentSrc.s, 0.35, 0.9), 4.8, background)

  // Text takes the ground's hue so it reads as belonging to the wallpaper,
  // desaturated to stay legible over long sessions.
  var foreground = solvedHex(ground.h, clamp(ground.s * 0.6, 0.05, 0.30), TARGET.foreground, background)

  var satSum = 0
  for (i = 0; i < pool.length; i++) satSum += pool[i].s
  var chroma = Math.round(clamp((satSum / pool.length) * 130, 30, 92))

  return normSpec({
    mode: dark ? "dark" : "light",
    background: background,
    foreground: foreground,
    accent: accent,
    chroma: chroma,
    seed: 0,
    overrides: {}
  })
}

// ----------------------------------------------------------------- colors.toml
//
// The boundary. Every value is re-validated here rather than trusted from the
// map, so nothing that is not a six-digit hex -- or one of the two gradient
// forms, which are rebuilt from validated hexes rather than passed through --
// can reach the file. That is what makes the generated toml injection-proof by
// construction instead of by escaping.
function toToml(palette, themeName) {
  var name = String(themeName || "").replace(/[^A-Za-z0-9 _-]/g, "").substring(0, 48)
  var lines = []
  lines.push("# " + (name || "Untitled") + " -- generated by Theme Forge.")
  lines.push("#")
  lines.push("# Every other themed config Omarchy generates derives from this file,")
  lines.push("# so this is the whole theme. Edit it by hand freely; Theme Forge will")
  lines.push("# read it back the next time you open this theme.")
  lines.push("")
  lines.push('mode = "' + (palette.mode === "light" ? "light" : "dark") + '"')
  lines.push("")

  function emit(key) {
    var value = normHex(palette[key])
    if (value === "") return false
    lines.push(key + ' = "' + value + '"')
    return true
  }

  var groups = [
    ["accent", "selection", "muted"],
    ["background", "dark_background", "darker_background", "lighter_background"],
    ["foreground", "dark_foreground", "light_foreground", "bright_foreground"]
  ]
  for (var g = 0; g < groups.length; g++) {
    for (var i = 0; i < groups[g].length; i++) emit(groups[g][i])
    lines.push("")
  }

  // Rebuilt from validated hexes, never copied from the palette map.
  var accent = normHex(palette.accent)
  var brightFg = normHex(palette.bright_foreground)
  var selection = normHex(palette.selection)
  if (accent && brightFg) {
    lines.push('hyprland_active_border = "rgba(' + strip(accent) + "dd) rgba(" + strip(brightFg) + 'dd) 45deg"')
  }
  if (selection) {
    lines.push('hyprland_inactive_border = "rgba(' + strip(selection) + '99)"')
  }
  lines.push("")

  var ansi = ["red", "yellow", "orange", "green", "cyan", "blue", "magenta", "brown"]
  for (var a = 0; a < ansi.length; a++) emit(ansi[a])
  lines.push("")
  var bright = ["bright_red", "bright_yellow", "bright_green", "bright_cyan", "bright_blue", "bright_magenta"]
  for (var b = 0; b < bright.length; b++) emit(bright[b])
  lines.push("")

  return lines.join("\n")
}

// Read a colors.toml back into a spec, for reopening a theme built earlier. The
// regex admits only `key = "#rrggbb"` and `mode = "dark"`, so a file that has
// grown anything else since -- a comment, a stray section, a gradient -- simply
// contributes nothing rather than being parsed for it.
function fromToml(text) {
  var body = String(text === undefined || text === null ? "" : text)
  var lines = body.split("\n")
  var found = {}
  var mode = "dark"
  for (var i = 0; i < lines.length && i < 400; i++) {
    var m = /^\s*([a-z_]{1,32})\s*=\s*"([^"]{0,64})"\s*$/.exec(lines[i])
    if (!m) continue
    if (m[1] === "mode") { mode = m[2] === "light" ? "light" : "dark"; continue }
    var hex = normHex(m[2])
    if (hex !== "") found[m[1]] = hex
  }
  if (!found.background || !found.foreground) return null

  // Everything present becomes a pin, so reopening a hand-edited theme shows
  // exactly the colours on disk rather than a re-derivation that quietly
  // discards the user's edits.
  var overrides = {}
  for (var k = 0; k < COLOR_KEYS.length; k++) {
    var key = COLOR_KEYS[k]
    if (found[key]) overrides[key] = found[key]
  }
  return normSpec({
    mode: mode,
    background: found.background,
    foreground: found.foreground,
    accent: found.accent || found.foreground,
    chroma: 62,
    seed: 0,
    overrides: overrides
  })
}
