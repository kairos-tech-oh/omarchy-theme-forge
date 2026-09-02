import QtQuick
import qs.Commons
import qs.Ui
import "Sanitise.js" as Sanitise

// A button wearing Rice Bar's glow chrome.
//
// It is the shell's own `qs.Ui.Button` with its fill and border turned off and
// a RiceSurface drawn behind it — not a reimplementation. That matters for more
// than tidiness: Button carries the tooltip, the hover and press fills, the
// focus ring and the keyboard handling that every other control in the shell
// has, and a hand-rolled Rectangle-with-a-MouseArea would quietly drop all of
// it. Decorating rather than replacing is also exactly what Rice Bar does to
// the stock bar, which is the plugin this styling comes from.
//
// The API is Button's, so a caller changes `Button {` to `RiceButton {` and
// leaves the rest alone. `enabled` and `opacity` are Item's own and are not
// redeclared here — declaring them would shadow the ones every QML type already
// has, and disabling this Item already disables the Button inside it.
Item {
  id: root

  property string text: ""
  property string tooltipText: ""
  property bool selected: false
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property color tint: Color.menu.background
  // The theme's lit window edge, which is what the glow preset outlines with.
  property color edgeColor: Color.flatColor(Color.pick("hyprland.active-border", Color.accent), Color.accent)
  property string fontFamily: Style.font.menuFamily
  property real fontSize: Style.font.body
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.controlPaddingY
  property real fillAlpha: 0.82
  property int cornerRadius: 16
  property bool bordered: true
  property bool glow: true

  signal clicked()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  opacity: enabled ? 1 : 0.4

  RiceSurface {
    anchors.fill: parent
    tint: root.tint
    fillAlpha: root.fillAlpha
    cornerRadius: root.cornerRadius
    bordered: root.bordered
    glow: root.glow
    hovered: button.hot && root.enabled
    // A chosen option is outlined in the accent rather than the window edge, so
    // "this one is selected" reads as lit rather than merely filled.
    edge: root.selected ? root.accent : root.edgeColor
  }

  Button {
    id: button
    anchors.fill: parent

    // Chrome off: the RiceSurface behind is the chrome now. What Button still
    // paints is its own state fill, which lands on top of that surface as a
    // subtle wash — so hover and press stay consistent with every other control
    // in the shell without this file having to reimplement either.
    bordered: false
    background: "transparent"

    // Button is a BorderSurface, and its radius defaults to Style.cornerRadius,
    // which mirrors Hyprland's `decoration:rounding` -- 0 on a sharp-cornered
    // setup. Left alone, the hover fill and the hover border it paints came out
    // as a square sitting inside a rounded pill. It has to be told the shape it
    // is decorating, because the shape is this component's choice and not the
    // compositor's.
    radius: Math.max(0, Math.min(root.cornerRadius,
                                 Math.round(Math.min(width, height) / 2)))

    // Button's label and tooltip are rendered by Text elements inside the
    // shell, with Qt's default AutoText, so they are sanitised here at the
    // boundary rather than trusted from whichever caller set them.
    text: Sanitise.plain(root.text)
    tooltipText: Sanitise.plain(root.tooltipText)
    selected: root.selected
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    fontSize: root.fontSize
    // The glow rings eat four pixels a side, so the label needs a little more
    // room than a plain button's to avoid sitting on them.
    horizontalPadding: root.horizontalPadding + Style.space(4)
    verticalPadding: root.verticalPadding

    onClicked: root.clicked()
  }
}
