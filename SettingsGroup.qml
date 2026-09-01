import QtQuick
import qs.Commons

// A titled block of settings rows, on the same glow surface the buttons wear so
// the page reads as one family rather than as controls floating on a scrim.
Item {
  id: group

  required property var forge
  property string title: ""
  default property alias content: body.data

  implicitHeight: heading.implicitHeight + Style.space(8) + surface.height

  Text {
    id: heading
    anchors.top: parent.top
    anchors.left: parent.left
    text: group.title
    textFormat: Text.PlainText
    color: group.forge.dim
    font.family: group.forge.uiFont
    font.pixelSize: Style.font.bodySmall
    font.bold: true
  }

  RiceSurface {
    id: surface
    anchors.top: heading.bottom
    anchors.topMargin: Style.space(8)
    anchors.left: parent.left
    anchors.right: parent.right
    height: body.implicitHeight + Style.space(28)
    tint: group.forge.surface
    // Fainter than a button: a panel this large at a button's fill would be a
    // slab, and the point of the surface here is to group rows, not to shout.
    fillAlpha: 0.55
    cornerRadius: 16

    Column {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Style.space(16)
      anchors.rightMargin: Style.space(16)
      anchors.topMargin: Style.space(14)
      spacing: Style.spacing.lg
    }
  }
}
