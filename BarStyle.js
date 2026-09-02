.pragma library

// What the user's bar looks like, read out of the shell's own bar config.
//
// The preview's bar used to be a fixed drawing: opaque, along the top, five
// workspaces and a clock. Most people's bars are not that. This reads the same
// `bar` object the shell hands every plugin -- position, transparency, which
// widgets sit where, and Rice Bar's preset when that plugin is installed -- and
// turns it into a small plain description the preview can draw from.
//
// Pure functions over plain objects, like Palette.js: no I/O, no QML type, so
// the same code runs under Node in tools/check-palette.js and under Qt's V4
// engine in tools/check-qml-engine.qml. Everything that arrives is treated as
// untrusted shape -- shell.json is the user's own file, but a malformed one
// must draw a stock bar rather than throw inside the preview.

var RICE_ID = "io.github.jcarcinogen.rice-bar"

var POSITIONS = ["top", "bottom", "left", "right"]

var PRESETS = [
  "omarchy", "islands", "pills", "material", "outline",
  "rail", "bracket", "glow", "powerline", "mono", "minimal"
]

// Lifted from Rice Bar's RiceModel.js, which is the definition of what each
// preset paints. `geometry` is one surface per section or one per widget.
var RECIPES = {
  omarchy:   { geometry: "none",     decoration: "none" },
  islands:   { geometry: "sections", decoration: "surface" },
  pills:     { geometry: "widgets",  decoration: "surface" },
  material:  { geometry: "sections", decoration: "material" },
  outline:   { geometry: "sections", decoration: "outline" },
  rail:      { geometry: "sections", decoration: "rail" },
  bracket:   { geometry: "sections", decoration: "bracket" },
  glow:      { geometry: "sections", decoration: "glow" },
  powerline: { geometry: "sections", decoration: "powerline" },
  mono:      { geometry: "sections", decoration: "mono" },
  minimal:   { geometry: "sections", decoration: "minimal" }
}

var STYLE_DEFAULTS = {
  omarchy:   { opacity: 100, radius: 0,  gap: 0, border: false },
  islands:   { opacity: 92,  radius: 12, gap: 4, border: true },
  pills:     { opacity: 90,  radius: 18, gap: 3, border: true },
  material:  { opacity: 92,  radius: 20, gap: 8, border: false },
  outline:   { opacity: 20,  radius: 14, gap: 6, border: true },
  rail:      { opacity: 60,  radius: 0,  gap: 4, border: false },
  bracket:   { opacity: 20,  radius: 0,  gap: 8, border: true },
  glow:      { opacity: 82,  radius: 16, gap: 8, border: true },
  powerline: { opacity: 92,  radius: 0,  gap: 6, border: true },
  mono:      { opacity: 96,  radius: 2,  gap: 3, border: true },
  minimal:   { opacity: 55,  radius: 0,  gap: 2, border: false }
}

var SECTIONS = ["left", "center", "right"]

// A busy bar still has to fit a preview a few hundred pixels wide.
var MAX_WIDGETS_PER_SECTION = 8
var MAX_FORMAT_LENGTH = 40

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function clampNumber(value, lo, hi, fallback) {
  var n = Number(value)
  if (!isFinite(n)) return fallback
  return Math.max(lo, Math.min(hi, n))
}

function normalizePosition(value) {
  var text = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  return POSITIONS.indexOf(text) !== -1 ? text : "top"
}

function normalizePreset(value) {
  var text = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  if (text === "default" || text === "stock") return "omarchy"
  return PRESETS.indexOf(text) !== -1 ? text : "islands"
}

// A widget id is only ever used to look up a glyph, never shown, but it is
// still bounded so a hostile layout cannot grow a string without limit.
function widgetId(value) {
  var text = String(value === undefined || value === null ? "" : value).trim()
  if (!/^[A-Za-z0-9._-]{1,80}$/.test(text)) return ""
  return text
}

// Qt.formatDateTime renders this, and the Text that shows the result is plain
// text, so only the length and control characters need bounding here.
function clockFormat(value, fallback) {
  var text = String(value === undefined || value === null ? "" : value)
  text = text.replace(/[\x00-\x09\x0b-\x1f\x7f]/g, "")
  if (text.length === 0 || text.length > MAX_FORMAT_LENGTH) return fallback
  return text
}

function boolValue(value, fallback) {
  if (value === true || value === "true" || value === 1 || value === "1") return true
  if (value === false || value === "false" || value === 0 || value === "0") return false
  return fallback === true
}

function hasAppearance(source) {
  return isObject(source) && (source.opacity !== undefined || source.radius !== undefined
    || source.gap !== undefined || source.border !== undefined)
}

function normalizeAppearance(source, defaults) {
  var values = isObject(source) ? source : {}
  return {
    opacity: Math.round(clampNumber(values.opacity === undefined ? defaults.opacity : values.opacity, 20, 100, defaults.opacity)),
    radius: Math.round(clampNumber(values.radius === undefined ? defaults.radius : values.radius, 0, 24, defaults.radius)),
    gap: Math.round(clampNumber(values.gap === undefined ? defaults.gap : values.gap, 0, 24, defaults.gap)),
    border: boolValue(values.border, defaults.border)
  }
}

function findEntry(layout, id) {
  if (!isObject(layout)) return null
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = layout[SECTIONS[s]]
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      if (isObject(entries[i]) && String(entries[i].id || "") === id) return entries[i]
    }
  }
  return null
}

// Rice Bar keeps one appearance per preset under `profiles`, with the flat
// opacity/radius/gap/border on the entry belonging to `activeProfile`. This
// follows RiceModel.resolvedState so the preview and the bar agree.
function riceSettings(entry) {
  var source = isObject(entry) ? entry : {}
  var preset = normalizePreset(source.preset)
  var defaults = STYLE_DEFAULTS[preset]
  var profiles = {}
  if (isObject(source.profiles)) {
    for (var p = 0; p < PRESETS.length; p++) {
      if (isObject(source.profiles[PRESETS[p]]))
        profiles[PRESETS[p]] = normalizeAppearance(source.profiles[PRESETS[p]], STYLE_DEFAULTS[PRESETS[p]])
    }
  }
  var marked = Number(source.profileVersion) === 1
    && PRESETS.indexOf(String(source.activeProfile || "").toLowerCase()) !== -1
  var appearance
  if (marked) {
    var active = normalizePreset(source.activeProfile)
    if (hasAppearance(source)) profiles[active] = normalizeAppearance(source, STYLE_DEFAULTS[active])
    appearance = profiles[preset] || defaults
  } else {
    appearance = hasAppearance(source)
      ? normalizeAppearance(source, defaults)
      : (profiles[preset] || defaults)
  }
  var recipe = RECIPES[preset]
  return {
    preset: preset,
    opacity: appearance.opacity,
    radius: appearance.radius,
    gap: appearance.gap,
    border: appearance.border,
    geometry: recipe.geometry,
    decoration: recipe.decoration
  }
}

// Rice Bar's own floor: even "20% opacity" leaves a third of the surface, so
// the chrome never disappears entirely.
function visibleAlpha(opacity) {
  return Math.min(1, 0.32 + clampNumber(opacity, 0, 100, 92) / 100 * 0.68)
}

function stock() {
  return {
    position: "top",
    vertical: false,
    transparent: false,
    foreign: "",
    clockFormat: "HH:mm",
    clockFormatVertical: "HH\nmm",
    widgets: {
      left: ["omarchy.menu", "omarchy.workspaces"],
      center: ["omarchy.clock"],
      right: ["omarchy.system-update", "omarchy.audio", "omarchy.network", "omarchy.power"]
    },
    rice: null
  }
}

// The whole description, from the shell's `bar` config object. `riceInstalled`
// is whether the plugin is present and enabled; the entry alone is not enough.
function resolve(barConfig, riceInstalled) {
  var out = stock()
  if (!isObject(barConfig)) return out

  out.position = normalizePosition(barConfig.position)
  out.vertical = out.position === "left" || out.position === "right"
  out.transparent = barConfig.transparent === true

  // A different bar plugin altogether: its layout is not this one's to draw,
  // so the stock bar stands in and the settings page says so.
  var barId = widgetId(barConfig.id)
  if (barId !== "" && barId !== "omarchy.bar") out.foreign = barId

  var layout = isObject(barConfig.layout) ? barConfig.layout : null
  if (layout) {
    var widgets = { left: [], center: [], right: [] }
    for (var s = 0; s < SECTIONS.length; s++) {
      var entries = layout[SECTIONS[s]]
      if (!Array.isArray(entries)) continue
      for (var i = 0; i < entries.length && widgets[SECTIONS[s]].length < MAX_WIDGETS_PER_SECTION; i++) {
        var id = isObject(entries[i]) ? widgetId(entries[i].id) : ""
        // Rice Bar's own widget is a settings button that paints nothing of its
        // own, and a spacer is empty by definition.
        if (id === "" || id === RICE_ID || id === "omarchy.spacer") continue
        widgets[SECTIONS[s]].push(id)
        if (id === "omarchy.clock") {
          out.clockFormat = clockFormat(entries[i].format, out.clockFormat)
          out.clockFormatVertical = clockFormat(entries[i].verticalFormat, out.clockFormatVertical)
        }
      }
    }
    out.widgets = widgets
  }

  var entry = riceInstalled === true && layout ? findEntry(layout, RICE_ID) : null
  if (entry) {
    var rice = riceSettings(entry)
    if (rice.preset !== "omarchy") {
      out.rice = rice
      // Rice Bar turns the stock ground off and paints its own beneath.
      out.transparent = true
    }
  }
  return out
}

// One line for the settings page: "top, see-through, Rice Bar glow".
function describe(style) {
  if (!isObject(style)) return "stock Omarchy bar"
  var parts = [normalizePosition(style.position)]
  if (style.foreign) {
    parts.push("a bar plugin this cannot draw, so the stock bar stands in")
    return parts.join(", ")
  }
  if (isObject(style.rice)) parts.push("Rice Bar " + style.rice.preset)
  else parts.push(style.transparent === true ? "see-through" : "solid")
  return parts.join(", ")
}
