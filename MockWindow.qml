import QtQuick
import qs.Commons
import "Palette.js" as Palette

// A window in the mock desktop, wearing the border Hyprland would give it.
//
// The border is the reason this is its own component rather than a Rectangle.
// A theme's `hyprland_active_border` is a two-stop gradient at 45 degrees, and
// it is not decoration: shell.toml.tpl feeds that same colour pair to the shell's
// popup, menu and notification borders, so this one pair of colours is what
// makes a desktop look lit or look flat. Drawing it as a flat accent line would
// preview a theme nobody is going to get.
//
// Built as a gradient-filled outer rectangle with the window's own ground inset
// inside it, which is how you get a gradient border out of plain QML.
//
// Every painted part carries a Hotspot naming its colour. The border's is a
// band a few pixels wide rather than the one- or two-pixel border itself, so
// it can actually be hit.
Rectangle {
  id: frame

  required property var forge
  property bool active: false
  property string title: ""
  default property alias content: body.data

  readonly property var colors: forge.colors
  readonly property int borderWidth: active ? 2 : 1

  function withAlpha(hex, alpha) {
    var rgb = Palette.hexToRgb(hex)
    if (!rgb) return Qt.rgba(0, 0, 0, alpha)
    return Qt.rgba(rgb.r / 255, rgb.g / 255, rgb.b / 255, alpha)
  }

  radius: Style.cornerRadius > 0 ? Style.cornerRadius : 3
  // Hyprland's inactive border is `selection` at 0x99, which is the 0.6 here.
  color: active ? "transparent" : frame.withAlpha(colors.selection, 0.6)

  // Hyprland's inactive border is a single flat colour, so only the active one
  // needs the gradient.
  gradient: frame.active
    ? activeBorderGradient
    : null

  Gradient {
    id: activeBorderGradient
    orientation: Gradient.Horizontal
    GradientStop { position: 0.0; color: frame.colors.accent }
    GradientStop { position: 1.0; color: frame.colors.bright_foreground }
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: frame.borderWidth
    radius: Math.max(0, frame.radius - frame.borderWidth)
    color: frame.colors.background

    Hotspot { forge: frame.forge; key: "background" }

    Rectangle {
      id: titleBar
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: Math.max(Style.space(12), Math.round(frame.height * 0.11))
      color: frame.colors.dark_background

      Hotspot { forge: frame.forge; key: "dark_background" }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: frame.title
        textFormat: Text.PlainText
        elide: Text.ElideRight
        width: parent.width - Style.space(12)
        color: frame.active ? frame.colors.foreground : frame.colors.dark_foreground
        font.family: frame.forge.monoFont
        font.pixelSize: Math.max(6, Math.round(titleBar.height * 0.56))

        Hotspot { forge: frame.forge; key: frame.active ? "foreground" : "dark_foreground" }
      }
    }

    Item {
      id: body
      anchors.top: titleBar.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      clip: true
    }
  }

  // The border. Above the ground so the band reaches a few pixels inside the
  // edge; masked so only that band is hit and the middle stays the ground's.
  Hotspot {
    id: borderSpot
    forge: frame.forge
    z: 1
    readonly property real band: frame.borderWidth + Style.space(3)
    // The active gradient runs accent into bright_foreground left to right, so
    // which one you are pointing at depends on which end you are pointing at.
    keyAt: function (mx, my) {
      if (!frame.active) return "selection"
      return mx < frame.width / 2 ? "accent" : "bright_foreground"
    }
    // Typed, because the mask is looked up as a meta-method with a QPointF
    // argument; an untyped JavaScript function is not found and is ignored.
    containmentMask: QtObject {
      function contains(point: point): bool {
        return point.x < borderSpot.band || point.y < borderSpot.band
            || point.x > frame.width - borderSpot.band || point.y > frame.height - borderSpot.band
      }
    }
  }
}
