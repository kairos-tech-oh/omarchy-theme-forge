import QtQuick

// A part of the preview that knows which of the twenty-six colours it wears.
//
// Dropped inside any painted element as a filling child, it makes that element
// the way into editing its colour: hovering names the key and outlines the
// element, clicking selects the key and opens the colour wheel on it. Twenty-six
// names in a grid are a lookup table; the same twenty-six as "that bit of the
// terminal" are what a person actually means when they say a colour is wrong.
//
// `keyAt` is for an element wearing two colours -- the active window border is
// a gradient from accent into bright_foreground -- and picks by pointer position.
// A right click locks or unlocks the colour, so it survives the next roll.
MouseArea {
  id: spot

  required property var forge
  property string key: ""
  property var keyAt: null

  // The key under the pointer right now, whichever way it is decided.
  function keyFor(mx, my) {
    if (typeof spot.keyAt === "function") return String(spot.keyAt(mx, my) || "")
    return spot.key
  }

  anchors.fill: parent
  hoverEnabled: true
  cursorShape: Qt.PointingHandCursor
  acceptedButtons: Qt.LeftButton | Qt.RightButton

  onEntered: spot.forge.previewHover(spot, spot.keyFor(mouseX, mouseY))
  onPositionChanged: function (mouse) { spot.forge.previewHover(spot, spot.keyFor(mouse.x, mouse.y)) }
  onExited: spot.forge.previewUnhover(spot)
  onClicked: function (mouse) {
    if (mouse.button === Qt.RightButton) spot.forge.togglePin(spot.keyFor(mouse.x, mouse.y))
    else spot.forge.pickFromPreview(spot.keyFor(mouse.x, mouse.y))
  }
  // A hidden or destroyed element must not leave its outline behind.
  onVisibleChanged: if (!visible) spot.forge.previewUnhover(spot)
  Component.onDestruction: spot.forge.previewUnhover(spot)
}
