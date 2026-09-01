import QtQuick
import qs.Commons

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
Rectangle {
  id: frame

  required property var forge
  property bool active: false
  property string title: ""
  default property alias content: body.data

  readonly property var colors: forge.colors
  readonly property int borderWidth: active ? 2 : 1

  radius: Style.cornerRadius > 0 ? Style.cornerRadius : 3
  color: active ? "transparent" : colors.hyprland_inactive_border !== undefined
    ? Qt.rgba(colors.selection.r, colors.selection.g, colors.selection.b, 0.6)
    : colors.selection

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

    Rectangle {
      id: titleBar
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: Math.max(Style.space(12), Math.round(frame.height * 0.11))
      color: frame.colors.dark_background

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
}
