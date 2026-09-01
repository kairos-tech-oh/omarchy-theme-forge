import QtQuick
import qs.Commons
import qs.Ui

// A text field wearing the same glow surface as the buttons.
//
// `TextField.background` is a settable Item, so this swaps that one thing and
// keeps the shell's field entirely — its selection colours, its placeholder
// treatment, its padding maths, its focus handling. Nothing is reimplemented.
//
// An input is still not a button and should not read as one: it sits at rest
// with a dimmer edge, and lights to the accent only when it has the caret.
// That is the difference between "you may press this" and "you may type here",
// and it survives both of them being on the same surface.
TextField {
  id: field

  property color tint: Color.menu.background
  property real fillAlpha: 0.82
  property int cornerRadius: 16
  property color edgeColor: Color.flatColor(Color.pick("hyprland.active-border", Color.accent), Color.accent)

  // The glow rings take four pixels a side, so the text needs to start further
  // in than it would in a plain field.
  horizontalPadding: Style.spacing.controlPaddingX + Style.space(4)

  background: RiceSurface {
    tint: field.tint
    fillAlpha: field.fillAlpha
    cornerRadius: field.cornerRadius
    hovered: field.hovered || field.activeFocus
    edge: field.activeFocus ? field.accent : field.edgeColor
  }
}
