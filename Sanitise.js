.pragma library

// Theme Forge — the boundary guards.
//
// Three kinds of string cross into this plugin from outside it: a theme name the
// user types, a file path the desktop portal hands back, and whatever the helper
// script or an external tool prints. Each gets a guard here, and each guard is
// the *only* way that kind of value is allowed to reach a path, an argv, or a
// Text element.
//
// Pure functions, no I/O, so tools/check-palette.js and
// tools/check-qml-engine.qml cover the lot under both engines.

// A theme name becomes a directory under ~/.config/omarchy/themes and an
// argument to omarchy-theme-set. omarchy-theme-set does its own check --
// `[[ -z $THEME_NAME || $THEME_NAME == .* || $THEME_NAME == */* ]]` -- and this
// is deliberately stricter than that, because the name also has to survive being
// a filename, a background prefix and a shell argument.
//
// Returns the normalised name, or "" for anything that is not one. There is no
// "cleaned up" middle ground on purpose: silently turning `../evil` into `evil`
// would write a real theme under a name the user never asked for.
var THEME_NAME_MAX = 32

function themeName(value) {
  var text = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  if (text.length === 0 || text.length > THEME_NAME_MAX) return ""
  if (!/^[a-z0-9][a-z0-9-]*$/.test(text)) return ""
  return text
}

// True when the name is well-formed but the user has not finished typing, so the
// UI can stay quiet instead of flashing an error at every keystroke.
function themeNamePartial(value) {
  var text = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  return text.length === 0
}

// Everything that reaches a Text element. Every Text in this plugin already
// pins textFormat: Text.PlainText, so this is the second layer rather than the
// first -- it exists because a string that has lost its markup-significant
// characters cannot become markup if a later edit adds a sink that does not pin
// the format, and because control characters wreck a single-line label whatever
// the text format says.
var PLAIN_MAX = 400

function plain(value) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/[<>&]/g, " ")
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .substring(0, PLAIN_MAX)
}

// A filesystem path from the desktop portal, or printed by the helper. Kept
// permissive about characters -- people really do have wallpapers called
// "holiday (2019) [edit].jpg" -- and strict about the two things that matter:
// it must be absolute, and it must not contain a newline or a null, because a
// path that does is not a path this plugin will ever be handed honestly and is
// the shape that forges an extra line in anything line-oriented.
//
// PATH_MAX is 4096, so anything longer is not a path this system can open.
var PATH_MAX = 4096

function absPath(value) {
  var text = String(value === undefined || value === null ? "" : value)
  if (text.length === 0 || text.length > PATH_MAX) return ""
  if (text.charAt(0) !== "/") return ""
  if (/[\u0000-\u001f\u007f]/.test(text)) return ""
  return text
}

// The last path component, for display. Never used to build a path.
function baseName(value) {
  var path = absPath(value)
  if (path === "") return ""
  var parts = path.split("/")
  return plain(parts[parts.length - 1] || path)
}

// Pull `#rrggbb` values out of whatever the quantiser printed. Bounded by row
// count as well as by the byte cap the producer already applied, and it accepts
// only complete, well-formed matches -- a truncated final line contributes
// nothing rather than a half colour.
var HEX_ROWS_MAX = 24

function hexList(text) {
  var body = String(text === undefined || text === null ? "" : text)
  var out = []
  var seen = {}
  var lines = body.split("\n")
  for (var i = 0; i < lines.length && out.length < HEX_ROWS_MAX; i++) {
    var m = /^#([0-9a-fA-F]{6})$/.exec(lines[i].trim())
    if (!m) continue
    var hex = "#" + m[1].toLowerCase()
    if (seen[hex]) continue
    seen[hex] = true
    out.push(hex)
  }
  return out
}

// A list of theme names printed by the helper, for the collision check. Same
// guard as a typed name, applied to each row, so a directory someone created by
// hand with a hostile name simply does not appear.
var NAME_ROWS_MAX = 400

function nameList(text) {
  var body = String(text === undefined || text === null ? "" : text)
  var out = []
  var lines = body.split("\n")
  for (var i = 0; i < lines.length && out.length < NAME_ROWS_MAX; i++) {
    var name = themeName(lines[i])
    if (name !== "") out.push(name)
  }
  return out
}
