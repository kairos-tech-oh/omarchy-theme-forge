import QtQuick
import qs.Commons
import qs.Ui

// A labelled slider with a live readout, wrapping qs.Ui's PanelSlider.
//
// PanelSlider never writes back to its own `value` -- it reports through
// moved()/released() and leaves the property a binding the caller owns. That is
// what lets `value` here stay bound to the derived palette: a drag changes the
// spec, the palette re-derives, and the knob follows the colour that actually
// came out rather than the position the pointer was in. When the contrast
// solver overrules a lightness, the slider visibly settles where the solver put
// it, which is the honest thing for it to do.
Item {
  id: row

  required property var forge
  property string label: ""
  property string readout: ""
  property string hint: ""
  property real value: 0
  property real minimum: 0
  property real maximum: 1

  signal movedTo(real value)

  implicitHeight: labelRow.implicitHeight + slider.implicitHeight
                  + (hint === "" ? 0 : hintText.implicitHeight + Style.space(2))

  Item {
    id: labelRow
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    implicitHeight: nameText.implicitHeight

    Text {
      id: nameText
      anchors.left: parent.left
      text: row.label
      textFormat: Text.PlainText
      color: row.forge.faint
      font.family: row.forge.uiFont
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
      font.bold: true
    }

    Text {
      anchors.right: parent.right
      text: row.readout
      textFormat: Text.PlainText
      color: row.forge.dim
      font.family: row.forge.monoFont
      font.pixelSize: Style.font.caption
    }
  }

  PanelSlider {
    id: slider
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: labelRow.bottom
    value: row.value
    minimum: row.minimum
    maximum: row.maximum
    step: (row.maximum - row.minimum) / 200
    fillColor: row.forge.colors.accent
    knobColor: row.forge.ink
    trackColor: Qt.rgba(row.forge.ink.r, row.forge.ink.g, row.forge.ink.b, 0.14)
    onMoved: function (v) { row.movedTo(v) }
    onReleased: function (v) { row.movedTo(v) }
  }

  Text {
    id: hintText
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: slider.bottom
    anchors.topMargin: Style.space(2)
    visible: row.hint !== ""
    text: row.hint
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    color: row.forge.faint
    font.family: row.forge.uiFont
    font.pixelSize: Style.font.caption
  }
}
