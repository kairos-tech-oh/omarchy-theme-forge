pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "Palette.js" as Palette

// A hue ring around a saturation/lightness square, for picking a colour by eye
// instead of by three sliders.
//
// It is HSL, not the HSV most wheels use, because HSL is what the rest of this
// plugin thinks in — the sliders, the contrast solver, and every derivation in
// Palette.js. A wheel that handed back HSV would need converting at the edge and
// would disagree with the sliders it sits next to about what "50%" means.
//
// Drawn with Canvas rather than a shader so it works wherever Quickshell does.
// The ring is painted once; the square is repainted only when the hue changes,
// which is the only thing that alters it.
Item {
  id: wheel

  required property var forge

  // The colour being edited. Assigning back happens through the panel, so the
  // contrast solver and the pinning rules apply exactly as they do for a slider.
  property string hex: "#000000"

  signal picked(string hex)
  signal closed()

  // The working HSL, kept here rather than re-read from the hex on every
  // change: a hex has no hue at black, white or grey, so dragging to an edge
  // of the square and back would otherwise snap the ring to red. It is
  // re-read only when the hex stops matching what this last emitted.
  property real hue: 0
  property real sat: 0
  property real light: 0
  readonly property var hsl: ({ h: wheel.hue, s: wheel.sat, l: wheel.light })

  function syncFromHex() {
    if (Palette.hslToHex(wheel.hue, wheel.sat, wheel.light) === wheel.hex) return
    var h = Palette.hexToHsl(wheel.hex)
    wheel.hue = h.h
    wheel.sat = h.s
    wheel.light = h.l
  }
  onHexChanged: syncFromHex()
  Component.onCompleted: syncFromHex()

  readonly property int wheelSize: Style.space(250)
  readonly property real ringOuter: wheelSize / 2
  readonly property real ringInner: ringOuter - Style.space(22)
  // The largest square that fits inside the ring's hole, with a little air.
  readonly property real squareSide: Math.floor((ringInner - Style.space(6)) * Math.SQRT2 / 2) * 2

  function emit(h, s, l) {
    wheel.hue = h
    wheel.sat = s
    wheel.light = l
    wheel.picked(Palette.hslToHex(h, s, l))
  }

  focus: true
  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      wheel.closed()
      event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.55)
  }

  // Anything outside the card closes it, which is what clicking away from a
  // picker is expected to do.
  MouseArea {
    anchors.fill: parent
    onClicked: wheel.closed()
  }

  RiceSurface {
    id: card
    anchors.centerIn: parent
    width: body.implicitWidth + Style.space(40)
    height: body.implicitHeight + Style.space(34)
    tint: wheel.forge.surface
    fillAlpha: 0.97
    cornerRadius: 18

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      id: body
      anchors.centerIn: parent
      spacing: Style.space(12)

      Row {
        spacing: Style.space(8)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "EDITING"
          textFormat: Text.PlainText
          color: wheel.forge.faint
          font.family: wheel.forge.uiFont
          font.pixelSize: Style.font.caption
          font.letterSpacing: 2
          font.bold: true
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: wheel.forge.selectedKey
          textFormat: Text.PlainText
          color: wheel.forge.ink
          font.family: wheel.forge.monoFont
          font.pixelSize: Style.font.caption
        }
      }

      Item {
        id: ringArea
        width: wheel.wheelSize
        height: wheel.wheelSize

        // ---------------------------------------------------------- the ring
        Canvas {
          id: ring
          anchors.fill: parent
          antialiasing: true
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var cx = width / 2
            var cy = height / 2
            var mid = (wheel.ringOuter + wheel.ringInner) / 2
            ctx.lineWidth = wheel.ringOuter - wheel.ringInner
            // One short arc per degree. A conical gradient would be one call,
            // and Canvas has no conical gradient, so this is the honest way to
            // get a smooth hue sweep -- 360 strokes drawn once.
            for (var deg = 0; deg < 360; deg++) {
              var from = (deg - 90.5) * Math.PI / 180
              var to = (deg - 89.0) * Math.PI / 180
              ctx.beginPath()
              ctx.strokeStyle = Qt.hsla(deg / 360, 1.0, 0.5, 1.0)
              ctx.arc(cx, cy, mid, from, to)
              ctx.stroke()
            }
          }
        }

        // The current hue's position on the ring.
        Rectangle {
          readonly property real angle: (wheel.hsl.h - 90) * Math.PI / 180
          readonly property real mid: (wheel.ringOuter + wheel.ringInner) / 2
          width: Style.space(13)
          height: width
          radius: width / 2
          antialiasing: true
          color: "transparent"
          border.width: 2
          border.color: "white"
          x: ringArea.width / 2 + Math.cos(angle) * mid - width / 2
          y: ringArea.height / 2 + Math.sin(angle) * mid - height / 2

          Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: width / 2
            color: Qt.hsla(wheel.hsl.h / 360, 1.0, 0.5, 1.0)
          }
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          onPressed: function (mouse) { pick(mouse.x, mouse.y) }
          onPositionChanged: function (mouse) { if (pressed) pick(mouse.x, mouse.y) }

          function pick(mx, my) {
            var dx = mx - width / 2
            var dy = my - height / 2
            var r = Math.sqrt(dx * dx + dy * dy)
            // Only the ring itself; the square inside has its own handler and
            // the corners outside the ring are dead space.
            if (r < wheel.ringInner - Style.space(2) || r > wheel.ringOuter + Style.space(3)) return
            var deg = Math.atan2(dy, dx) * 180 / Math.PI + 90
            wheel.emit((deg % 360 + 360) % 360, wheel.hsl.s, wheel.hsl.l)
          }
        }

        // -------------------------------------------------------- the square
        Item {
          id: square
          anchors.centerIn: parent
          width: wheel.squareSide
          height: wheel.squareSide

          Canvas {
            id: field
            anchors.fill: parent
            antialiasing: false

            // Repainted only when the hue moves, because the hue is the only
            // thing that changes what this square contains.
            readonly property real hue: wheel.hsl.h
            onHueChanged: requestPaint()

            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              var steps = Math.max(24, Math.min(160, Math.floor(width)))
              var cw = width / steps
              // One column per saturation step, each a vertical HSL ramp:
              // white at lightness 1, the pure hue at 0.5, black at 0. That is
              // exactly what HSL is, so the square and the sliders agree.
              for (var i = 0; i < steps; i++) {
                var sat = i / (steps - 1)
                var grad = ctx.createLinearGradient(0, 0, 0, height)
                grad.addColorStop(0.0, Qt.hsla(hue / 360, sat, 1.0, 1.0))
                grad.addColorStop(0.5, Qt.hsla(hue / 360, sat, 0.5, 1.0))
                grad.addColorStop(1.0, Qt.hsla(hue / 360, sat, 0.0, 1.0))
                ctx.fillStyle = grad
                ctx.fillRect(i * cw, 0, cw + 1, height)
              }
            }
          }

          Rectangle {
            width: Style.space(13)
            height: width
            radius: width / 2
            antialiasing: true
            color: "transparent"
            border.width: 2
            // White on a dark part of the square, black on a light one, so the
            // marker is visible wherever it lands.
            border.color: wheel.hsl.l > 0.55 ? "black" : "white"
            x: wheel.hsl.s * square.width - width / 2
            y: (1 - wheel.hsl.l) * square.height - height / 2
          }

          MouseArea {
            anchors.fill: parent
            onPressed: function (mouse) { pick(mouse.x, mouse.y) }
            onPositionChanged: function (mouse) { if (pressed) pick(mouse.x, mouse.y) }

            function pick(mx, my) {
              var s = Math.max(0, Math.min(1, mx / width))
              var l = Math.max(0, Math.min(1, 1 - my / height))
              wheel.emit(wheel.hsl.h, s, l)
            }
          }
        }
      }

      // ------------------------------------------------------------- readout

      Row {
        spacing: Style.space(10)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(34)
          height: Style.space(30)
          radius: Style.space(8)
          antialiasing: true
          color: wheel.hex
          border.width: 1
          border.color: wheel.forge.hairline
        }

        RiceField {
          id: hexEntry
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(110)
          text: wheel.hex
          foreground: wheel.forge.ink
          accent: wheel.forge.colors.accent
          font.family: wheel.forge.monoFont
          tint: wheel.forge.surface
          fillAlpha: wheel.forge.surfaceAlpha
          onAccepted: {
            var value = Palette.normHex(text)
            if (value === "") { text = wheel.hex; return }
            wheel.picked(value)
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: {
            if (wheel.forge.selectedKey === "background") return "the ground"
            var ratio = Palette.contrast(wheel.hex, wheel.forge.colors.background)
            return ratio.toFixed(1) + ":1"
          }
          textFormat: Text.PlainText
          color: wheel.forge.dim
          font.family: wheel.forge.uiFont
          font.pixelSize: Style.font.caption
        }

        RiceButton {
          anchors.verticalCenter: parent.verticalCenter
          text: "Done"
          foreground: wheel.forge.colors.accent
          accent: wheel.forge.colors.accent
          selected: true
          tint: wheel.forge.surface
          fillAlpha: wheel.forge.surfaceAlpha
          onClicked: wheel.closed()
        }
      }

      Text {
        width: ringArea.width
        wrapMode: Text.WordWrap
        text: wheel.forge.selectedKey === "background"
          ? "The rest of the palette re-solves against this as you drag."
          : "Lands exactly here and pins " + wheel.forge.selectedKey + ", so it survives the next roll."
        textFormat: Text.PlainText
        color: wheel.forge.faint
        font.family: wheel.forge.uiFont
        font.pixelSize: Style.font.caption
      }
    }
  }
}
