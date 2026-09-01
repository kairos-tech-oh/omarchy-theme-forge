// The same properties tools/check-palette.js asserts under Node, asserted again
// under Qt's V4 engine -- the one that actually runs inside omarchy-shell.
//
// V4 is not V8. It has its own regex engine, its own number formatting, and its
// own idea of which ES features exist. "It passed under Node" has never been
// evidence about the shell, and the failure mode when the two disagree is a
// guard that quietly does nothing in the only place it matters.
//
// The result is communicated through the exit code rather than console output,
// because Qt's `qml` runner suppresses console messages on some builds. Exit 0
// means everything passed; any other value is the number of the check that did
// not, and the numbers are the comments below.
//
// Run it with:  tools/run-checks.sh

import QtQuick
import "../Palette.js" as Palette
import "../Sanitise.js" as Sanitise

QtObject {
  function fail(code) {
    Qt.exit(code)
    return false
  }

  function near(a, b, tolerance) {
    return Math.abs(a - b) <= tolerance
  }

  Component.onCompleted: {
    // 1-6: hex normalisation. The regexes are the guard, so V4's regex engine
    // agreeing with V8's is the thing being checked, not the function's logic.
    if (Palette.normHex("#AABBCC") !== "#aabbcc") return fail(1)
    if (Palette.normHex("#abc") !== "") return fail(2)
    if (Palette.normHex("#aabbcc<img src=x>") !== "") return fail(3)
    if (Palette.normHex("#aabbcc\nred = #000000") !== "") return fail(4)
    if (Palette.normHex(null) !== "") return fail(5)
    if (Palette.normHex(undefined) !== "") return fail(6)

    // 7-9: the WCAG anchors.
    if (!near(Palette.contrast("#ffffff", "#000000"), 21, 0.001)) return fail(7)
    if (!near(Palette.contrast("#7aa2f7", "#7aa2f7"), 1, 0.001)) return fail(8)
    if (Palette.mix("#000000", "#ffffff", 0.5) !== "#808080") return fail(9)

    // 10-11: shortest-arc hue interpolation. Getting this wrong sends the reds
    // green, and it is entirely a matter of arithmetic sign handling.
    if (!near(Palette.pullHue(356, 22, 1), 22, 0.001)) return fail(10)
    if (!near(Palette.pullHue(10, 350, 0.5), 0, 0.001)) return fail(11)

    // 12-14: the contrast solver reaches its target and never overshoots the
    // band ceiling, across both grounds and the whole hue circle.
    var backgrounds = ["#000000", "#181a1f", "#ffffff", "#f5f5f5"]
    for (var b = 0; b < backgrounds.length; b++) {
      for (var hue = 0; hue < 360; hue += 45) {
        var hex = Palette.solvedHex(hue, 0.7, 6.5, backgrounds[b])
        if (!Palette.isHex(hex)) return fail(12)
        if (Palette.contrast(hex, backgrounds[b]) > 6.65) return fail(13)
      }
    }
    if (Palette.contrast(Palette.solvedHex(210, 0.6, 9.5, "#181a1f"), "#181a1f") < 9.0) return fail(14)

    // 15-18: a rolled palette is complete, in band, ordered, and reproducible.
    for (var seed = 0; seed < 60; seed++) {
      var colors = Palette.derive(Palette.rollSpec(seed, "dark"))
      for (var k = 0; k < Palette.COLOR_KEYS.length; k++) {
        if (!Palette.isHex(colors[Palette.COLOR_KEYS[k]])) return fail(15)
      }
      if (Palette.failingKeys(colors).length !== 0) return fail(16)
      var light = Palette.contrast(colors.light_foreground, colors.background)
      var normal = Palette.contrast(colors.foreground, colors.background)
      var bright = Palette.contrast(colors.bright_foreground, colors.background)
      if (!(light < normal && normal < bright)) return fail(17)
    }
    if (JSON.stringify(Palette.derive(Palette.rollSpec(4242, "dark")))
        !== JSON.stringify(Palette.derive(Palette.rollSpec(4242, "dark")))) return fail(18)

    // 19-20: light mode inverts, and its surface tones recede the way both
    // stock light themes do.
    for (var s = 0; s < 40; s++) {
      var lightColors = Palette.derive(Palette.rollSpec(s, "light"))
      if (Palette.luminance(lightColors.background) < 0.6) return fail(19)
      if (Palette.failingKeys(lightColors).length !== 0) return fail(20)
    }

    // 21-24: the colors.toml boundary. Every one of these values would break out
    // of the file if it were written through instead of re-validated.
    var poisoned = Palette.derive(Palette.rollSpec(1, "dark"))
    poisoned.red = '#ff0000"\nhyprland_active_border = "rgba(deadbeef)'
    poisoned.green = "#00ff00; rm -rf /"
    poisoned.blue = "<img src=http://example.invalid/x>"
    var toml = Palette.toToml(poisoned, 'inject"test\nmode = "light')
    if (toml.indexOf("rm -rf") !== -1) return fail(21)
    if (toml.indexOf("<img") !== -1) return fail(22)
    if (toml.indexOf('mode = "light"') !== -1) return fail(23)
    var allowed = /^(mode = "(dark|light)"|hyprland_active_border = "rgba\([0-9a-f]{8}\) rgba\([0-9a-f]{8}\) 45deg"|hyprland_inactive_border = "rgba\([0-9a-f]{8}\)"|[a-z_]+ = "#[0-9a-f]{6}")$/
    var lines = toml.split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (lines[i] === "" || lines[i].charAt(0) === "#") continue
      if (!allowed.test(lines[i])) return fail(24)
    }

    // 25: a generated theme reads back as the same theme.
    var original = Palette.derive(Palette.rollSpec(99, "dark"))
    var reopened = Palette.fromToml(Palette.toToml(original, "round-trip"))
    if (!reopened) return fail(25)
    var rebuilt = Palette.derive(reopened)
    for (var c = 0; c < Palette.COLOR_KEYS.length; c++) {
      if (rebuilt[Palette.COLOR_KEYS[c]] !== original[Palette.COLOR_KEYS[c]]) return fail(25)
    }

    // 26-27: seeding from an image never produces an unreadable palette, however
    // little the image had to offer.
    var samples = [["#000000", "#050505"], ["#ffffff", "#f8f8f8"],
                   ["#8b0000", "#ff4500", "#4682b4"], ["#808080", "#7f7f7f"]]
    for (var m = 0; m < samples.length; m++) {
      var seeded = Palette.fromImage(samples[m], "dark")
      if (!seeded) return fail(26)
      if (Palette.failingKeys(Palette.derive(seeded)).length !== 0) return fail(27)
    }
    if (Palette.fromImage([], "dark") !== null) return fail(26)

    // 28-31: the boundary guards. These are all regex, so V4 is the engine that
    // has to agree.
    // "UPPER" is deliberately absent: themeName lowercases before it checks, so
    // a name that is only wrong in its case is accepted and normalised, which is
    // what check 29 asserts. Only names that are wrong in some other way belong
    // in this list.
    var refused = ["", "../evil", "/etc/passwd", ".hidden", "-leading", "UPPER NAME",
                   "with space", "a\nb", "a\tb", "under_score", "sla/sh", "$(id)"]
    for (var r = 0; r < refused.length; r++) {
      if (Sanitise.themeName(refused[r]) !== "") return fail(28)
    }
    if (Sanitise.themeName("  Tron  ") !== "tron") return fail(29)
    if (Sanitise.plain("<img src=x>") !== " img src=x ") return fail(30)
    if (Sanitise.plain("a\nb\tc") !== "a b c") return fail(30)
    if (Sanitise.absPath("relative") !== "") return fail(31)
    if (Sanitise.absPath("/a\nb") !== "") return fail(31)
    if (Sanitise.absPath("/home/u/my pic (1).png") !== "/home/u/my pic (1).png") return fail(31)

    // 32: the helper's output parsers, which see whatever ImageMagick and find
    // printed.
    if (Sanitise.hexList("#AABBCC\njunk\n#112233\n#AABBCC").join(",") !== "#aabbcc,#112233") return fail(32)
    if (Sanitise.hexList("#AABBC").length !== 0) return fail(32)
    if (Sanitise.nameList("tron\n../evil\nTokyo Night\nnord").join(",") !== "tron,nord") return fail(32)

    Qt.exit(0)
  }
}
