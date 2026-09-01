import QtQuick
import qs.Commons

// The chrome behind a control, drawn the way Rice Bar's `glow` preset draws the
// chrome behind a bar section.
//
// That preset's recipe, read out of the plugin rather than guessed at:
//
//   fill    Qt.darker(surface, 1.28) at the configured alpha
//   border  1px of the theme's Hyprland active-border colour
//   glow    two more outlines inset by 2px and 4px, at 0.34 and 0.14 of that
//           same colour, scaled by the alpha
//
// The layered outlines are the whole signature. One border is a box; three at
// falling opacity read as something lit from inside, which is why the preset is
// called glow and why copying only the outer border would miss the point.
//
// It is drawn *behind* whatever sits on top and never draws content itself,
// which is also Rice Bar's own approach -- it decorates the stock bar without
// replacing any of it. Here that means the shell's own Button keeps its hover,
// press, focus and tooltip behaviour, and only gains a new surface underneath.
Item {
  id: surface

  // The colour the fill is darkened from. Defaults to the window ground so a
  // control reads as carved out of the surface it sits on.
  property color tint: Color.menu.background

  // The theme's lit edge. `hyprland.active-border` is what Hyprland draws
  // around the focused window and what the shell feeds to its popup, menu and
  // notification borders, so a control wearing it belongs to the same desktop.
  property color edge: Color.flatColor(Color.pick("hyprland.active-border", Color.accent), Color.accent)

  property real fillAlpha: 0.82
  property int cornerRadius: 16
  property bool bordered: true
  property bool glow: true

  // Lifted a little on hover and pressed in on click. The shell's own Button
  // paints its state fill on top of this, so these are deliberately small --
  // enough that the surface acknowledges the pointer without competing.
  property bool hovered: false
  property bool pressed: false

  readonly property real _alpha: Math.max(0, Math.min(1, fillAlpha))
  readonly property int _radius: Math.max(0, Math.min(cornerRadius, Math.round(Math.min(width, height) / 2)))

  function _withAlpha(color, alpha) {
    return Qt.rgba(color.r, color.g, color.b, Math.max(0, Math.min(1, alpha)))
  }

  Rectangle {
    id: base
    anchors.fill: parent
    radius: surface._radius
    color: "transparent"
    clip: true
    antialiasing: true
    border.width: surface.bordered ? 1 : 0
    border.color: surface.bordered
      ? surface._withAlpha(surface.edge, surface.hovered ? 1.0 : 0.75)
      : "transparent"

    Behavior on border.color { ColorAnimation { duration: 120 } }

    Rectangle {
      anchors.fill: parent
      anchors.margins: base.border.width
      radius: Math.max(0, base.radius - base.border.width)
      antialiasing: true
      color: surface._withAlpha(
        Qt.darker(surface.tint, surface.pressed ? 1.10 : (surface.hovered ? 1.18 : 1.28)),
        surface._alpha)

      Behavior on color { ColorAnimation { duration: 120 } }
    }

    // The two inner rings. Their alphas scale with the fill's, so turning the
    // surface down turns the glow down with it rather than leaving a bright
    // wireframe floating on a faint fill.
    Rectangle {
      anchors.fill: parent
      anchors.margins: 2
      visible: surface.glow && surface.bordered && base.radius > 3
      color: "transparent"
      radius: Math.max(0, parent.radius - 2)
      antialiasing: true
      border.width: 1
      border.color: surface._withAlpha(surface.edge, 0.34 * surface._alpha)
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: 4
      visible: surface.glow && surface.bordered && base.radius > 5
      color: "transparent"
      radius: Math.max(0, parent.radius - 4)
      antialiasing: true
      border.width: 1
      border.color: surface._withAlpha(surface.edge, 0.14 * surface._alpha)
    }
  }
}
