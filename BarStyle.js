.pragma library

// What the user's bar looks like, read out of the shell's own bar config.
//
// The preview's bar used to be a fixed drawing: opaque, along the top, five
// workspaces and a clock. Most people's bars are not that. This reads the same
// `bar` object the shell hands every plugin -- position, transparency and which
// widgets sit where -- and turns it into a small plain description the preview
// can draw from.
//
// Pure functions over plain objects, like Palette.js: no I/O, no QML type, so
// the same code runs under Node in tools/check-palette.js and under Qt's V4
// engine in tools/check-qml-engine.qml. Everything that arrives is treated as
// untrusted shape -- shell.json is the user's own file, but a malformed one
// must draw a stock bar rather than throw inside the preview.

var POSITIONS = ["top", "bottom", "left", "right"]

var SECTIONS = ["left", "center", "right"]

// A busy bar still has to fit a preview a few hundred pixels wide.
var MAX_WIDGETS_PER_SECTION = 8
var MAX_FORMAT_LENGTH = 40

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function normalizePosition(value) {
  var text = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  return POSITIONS.indexOf(text) !== -1 ? text : "top"
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
    }
  }
}

// The whole description, from the shell's `bar` config object.
function resolve(barConfig) {
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
        // A spacer is empty by definition; every other widget takes up room.
        if (id === "" || id === "omarchy.spacer") continue
        widgets[SECTIONS[s]].push(id)
        if (id === "omarchy.clock") {
          out.clockFormat = clockFormat(entries[i].format, out.clockFormat)
          out.clockFormatVertical = clockFormat(entries[i].verticalFormat, out.clockFormatVertical)
        }
      }
    }
    out.widgets = widgets
  }

  return out
}

// One line for the settings page: "top, see-through".
function describe(style) {
  if (!isObject(style)) return "stock Omarchy bar"
  var parts = [normalizePosition(style.position)]
  if (style.foreign) {
    parts.push("a bar plugin this cannot draw, so the stock bar stands in")
    return parts.join(", ")
  }
  parts.push(style.transparent === true ? "see-through" : "solid")
  return parts.join(", ")
}
