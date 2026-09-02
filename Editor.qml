pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "Palette.js" as Palette
import "Sanitise.js" as Sanitise

// The left column: name it, roll it, tune it.
//
// Six inputs drive a theme -- mode, background, foreground, accent, ANSI chroma,
// and a seed -- and the other twenty colours derive from them. Anything derived
// can still be overruled one swatch at a time, and an overruled swatch is
// *pinned*: it survives every later re-derivation until it is unpinned, so
// fixing one colour by hand does not mean giving up the roller.
//
// Every Text here sets textFormat: Text.PlainText, including the ones showing
// numbers this file generated. That is the point of doing it unconditionally --
// the safe default then covers whatever the next edit adds, rather than
// depending on someone noticing that a new label happens to show a filename.
// The root is an Item rather than the Flickable itself so the scroll indicator
// can sit beside the scrolling area instead of inside it. A Rectangle declared
// as a child of a Flickable goes into its contentItem and scrolls away with
// everything else -- which is exactly what an indicator must not do.
Item {
  id: editor

  required property var forge

  readonly property var colors: forge.colors
  readonly property var spec: forge.spec
  readonly property string selectedKey: forge.selectedKey
  readonly property string selectedHex: Palette.normHex(colors[selectedKey]) || "#000000"
  // The working HSL for the sliders, kept rather than re-read from the hex:
  // a grey or a black has no hue, so sliding LIGHT to the bottom and back
  // would otherwise lose the hue. Re-read only when the hex changes elsewhere.
  property real workHue: 0
  property real workSat: 0
  property real workLight: 0
  readonly property var selectedHsl: ({ h: workHue, s: workSat, l: workLight })

  function syncHsl() {
    if (Palette.hslToHex(editor.workHue, editor.workSat, editor.workLight) === editor.selectedHex) return
    var h = Palette.hexToHsl(editor.selectedHex)
    editor.workHue = h.h
    editor.workSat = h.s
    editor.workLight = h.l
  }
  onSelectedHexChanged: syncHsl()
  Component.onCompleted: syncHsl()

  property bool stockOpen: false

  function applyHsl(hue, sat, light) {
    editor.workHue = hue
    editor.workSat = sat
    editor.workLight = light
    forge.setColor(editor.selectedKey, Palette.hslToHex(hue, sat, light))
  }

  // A thin track down the right edge, visible only when there is more column
  // than there is room. Without it the palette grid simply stops mid-row at the
  // bottom of the card, which reads as a rendering fault rather than as an
  // invitation to scroll.
  Rectangle {
    anchors.right: parent.right
    anchors.rightMargin: -Style.space(4)
    y: {
      var travel = Math.max(1, flick.contentHeight - flick.height)
      return Math.max(0, Math.min(1, flick.contentY / travel)) * (flick.height - height)
    }
    width: Style.space(2)
    radius: width / 2
    height: Math.max(Style.space(28), flick.height * (flick.height / Math.max(1, flick.contentHeight)))
    color: forge.ink
    visible: flick.contentHeight > flick.height
    opacity: flick.moving ? 0.55 : 0.22
    Behavior on opacity { NumberAnimation { duration: 160 } }
    z: 2
  }

  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: column
      width: flick.width
      spacing: Style.spacing.lg

      // ------------------------------------------------------------- the name

      Text {
        text: "THEME"
        textFormat: Text.PlainText
        color: forge.faint
        font.family: forge.uiFont
        font.pixelSize: Style.font.caption
        font.letterSpacing: 2
        font.bold: true
      }

      RiceField {
        id: nameField
        width: parent.width
        placeholderText: "lowercase-name"
        text: forge.themeName
        foreground: forge.ink
        accent: forge.colors.accent
        font.family: forge.monoFont
        onTextChanged: forge.themeName = text
        onAccepted: forge.save(false)
        tint: forge.surface
        fillAlpha: forge.surfaceAlpha
      }

      Text {
        width: parent.width
        visible: text !== ""
        wrapMode: Text.WordWrap
        text: {
          var problem = forge.nameProblem()
          if (problem !== "" && String(forge.themeName).trim() !== "") return problem
          if (forge.overwrites()) return "This will overwrite the theme you already have by that name."
          return ""
        }
        textFormat: Text.PlainText
        color: forge.overwrites() && forge.nameProblem() === "" ? forge.colors.yellow : forge.colors.red
        font.family: forge.uiFont
        font.pixelSize: Style.font.caption
      }

      // What Save means. Two states, next to the name, because it changes where
      // the theme lands and whether it shows up in the switcher -- that belongs
      // beside the name it is being saved under, not hidden in the footer.
      Row {
        width: parent.width
        spacing: Style.spacing.sm

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "SAVE AS"
          textFormat: Text.PlainText
          color: forge.faint
          font.family: forge.uiFont
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }

        RiceButton {
          text: "a theme"
          fontSize: Style.font.caption
          verticalPadding: Style.space(2)
          horizontalPadding: Style.space(4)
          selected: !forge.savingWip
          foreground: selected ? forge.colors.accent : forge.dim
          accent: forge.colors.accent
          tint: forge.surface
          fillAlpha: forge.surfaceAlpha
          tooltipText: "Goes to ~/.config/omarchy/themes and shows up in your theme switcher"
          onClicked: forge.saveMode = "theme"
        }

        RiceButton {
          text: "in progress"
          fontSize: Style.font.caption
          verticalPadding: Style.space(2)
          horizontalPadding: Style.space(4)
          selected: forge.savingWip
          foreground: selected ? forge.colors.yellow : forge.dim
          accent: forge.colors.yellow
          tint: forge.surface
          fillAlpha: forge.surfaceAlpha
          tooltipText: "A real theme file, kept out of the way -- it will not appear in your theme switcher until you save it as a theme"
          onClicked: forge.saveMode = "wip"
        }
      }

      // Everything openable, in three bands, because "can I save over this?"
      // has three different answers and that is the only thing worth grouping
      // them by. Yours first, since that is what you came back for.
      Flow {
        width: parent.width
        spacing: Style.spacing.sm
        visible: mine.count > 0 || drafts.count > 0

        Text {
          text: "OPEN"
          textFormat: Text.PlainText
          color: forge.faint
          font.family: forge.uiFont
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }

        Repeater {
          id: drafts
          model: forge.wipThemes
          delegate: RiceButton {
            required property string modelData
            text: modelData
            fontSize: Style.font.caption
            verticalPadding: Style.space(2)
            horizontalPadding: Style.space(4)
            // In-progress themes are marked, because the difference between one
            // of these and a finished theme is the whole point of having both.
            foreground: forge.colors.yellow
            accent: forge.colors.yellow
            tooltipText: "In progress -- not in your theme switcher"
            tint: forge.surface
            fillAlpha: forge.surfaceAlpha
            enabled: !forge.busy
            onClicked: forge.loadTheme(modelData, "wip")
          }
        }

        Repeater {
          id: mine
          model: forge.userThemes
          delegate: RiceButton {
            required property string modelData
            text: modelData
            fontSize: Style.font.caption
            verticalPadding: Style.space(2)
            horizontalPadding: Style.space(4)
            foreground: forge.dim
            tint: forge.surface
            fillAlpha: forge.surfaceAlpha
            enabled: !forge.busy
            onClicked: forge.loadTheme(modelData)
          }
        }
      }

      // The twenty-odd themes Omarchy ships, behind a fold. Opening one is the
      // best way to start from something known -- and to see the numbers behind
      // a palette you already like -- but listing them all unfolded would push
      // everything else off the column.
      Row {
        width: parent.width
        spacing: Style.spacing.sm

        RiceButton {
          text: (editor.stockOpen ? "\u2212  " : "+  ") + "Start from an Omarchy theme"
          fontSize: Style.font.caption
          verticalPadding: Style.space(2)
          horizontalPadding: Style.space(4)
          foreground: forge.faint
          tint: forge.surface
          fillAlpha: forge.surfaceAlpha
          enabled: !forge.busy && forge.stockThemes.length > 0
          tooltipText: "Saving one of these needs a new name -- Theme Forge will not write over a theme Omarchy ships"
          onClicked: editor.stockOpen = !editor.stockOpen
        }
      }

      Flow {
        width: parent.width
        spacing: Style.spacing.sm
        visible: editor.stockOpen

        Repeater {
          model: forge.stockThemes
          delegate: RiceButton {
            required property string modelData
            text: modelData
            fontSize: Style.font.caption
            verticalPadding: Style.space(2)
            horizontalPadding: Style.space(4)
            foreground: forge.faint
            tint: forge.surface
            fillAlpha: forge.surfaceAlpha
            enabled: !forge.busy
            onClicked: forge.loadTheme(modelData)
          }
        }
      }

      Rectangle { width: parent.width; height: 1; color: forge.hairline }

      // ---------------------------------------------------------- mode + roll

      Row {
        width: parent.width
        spacing: Style.spacing.controlGap

        // Two buttons rather than qs.Ui's segmented ButtonGroup. The kit's
        // control draws its own flat chrome and cannot be decorated the way
        // Button can, so sitting between two glow pills it read as the one
        // control that had been left out. A pair of RiceButtons with `selected`
        // is the same affordance wearing the same surface as everything else.
        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Repeater {
            model: ["dark", "light"]
            delegate: RiceButton {
              required property string modelData
              text: modelData
              fontSize: Style.font.caption
              selected: editor.spec.mode === modelData
              foreground: selected ? forge.colors.accent : forge.dim
              accent: forge.colors.accent
              tint: forge.surface
              fillAlpha: forge.surfaceAlpha
              onClicked: forge.setMode(modelData)
            }
          }
        }

        Item { width: Style.space(4); height: 1 }

        RiceField {
          id: seedField
          width: Style.space(84)
          text: String(editor.spec.seed)
          foreground: forge.ink
          accent: forge.colors.accent
          font.family: forge.monoFont
          onAccepted: forge.rollSeed(text)
          tint: forge.surface
          fillAlpha: forge.surfaceAlpha
        }

        RiceButton {
          text: "Roll"
          foreground: forge.colors.accent
          accent: forge.colors.accent
          tooltipText: "A new random palette that passes its own contrast bands"
          onClicked: forge.roll()
          tint: forge.surface
          fillAlpha: forge.surfaceAlpha
          selected: true
        }
      }

      // --------------------------------------------------------- the image

      Row {
        width: parent.width
        spacing: Style.spacing.controlGap

        RiceButton {
          text: forge.sourceImage === "" ? "Use an image" : "Change image"
          foreground: forge.ink
          enabled: !forge.busy && forge.imagesUsable()
          tooltipText: forge.imagesUsable()
            ? "Seed the palette from a picture, and use it as the background"
            : forge.imageBlockedReason()
          onClicked: forge.pickImage()
          tint: forge.surface
          fillAlpha: forge.surfaceAlpha
        }

        RiceButton {
          visible: forge.sourceImage !== ""
          text: "Drop it"
          foreground: forge.dim
          enabled: !forge.busy
          tooltipText: "Go back to a background drawn from the palette"
          onClicked: forge.clearImage()
          tint: forge.surface
          fillAlpha: forge.surfaceAlpha
        }
      }

      Text {
        width: parent.width
        visible: text !== ""
        elide: Text.ElideMiddle
        text: forge.sourceImage === "" ? forge.imageBlockedReason() : Sanitise.baseName(forge.sourceImage)
        textFormat: Text.PlainText
        color: forge.faint
        font.family: forge.monoFont
        font.pixelSize: Style.font.caption
      }

      Rectangle { width: parent.width; height: 1; color: forge.hairline }

      // ------------------------------------------------------- the swatch bench

      Row {
        width: parent.width
        spacing: Style.spacing.sm

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "EDITING"
          textFormat: Text.PlainText
          color: forge.faint
          font.family: forge.uiFont
          font.pixelSize: Style.font.caption
          font.letterSpacing: 2
          font.bold: true
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: editor.selectedKey
          textFormat: Text.PlainText
          color: forge.ink
          font.family: forge.monoFont
          font.pixelSize: Style.font.caption
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: forge.isPinned(editor.selectedKey)
          text: "LOCKED"
          textFormat: Text.PlainText
          color: forge.colors.yellow
          font.family: forge.uiFont
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }

        RiceButton {
          anchors.verticalCenter: parent.verticalCenter
          text: forge.isPinned(editor.selectedKey) ? "unlock" : "lock"
          fontSize: Style.font.caption
          verticalPadding: Style.space(1)
          horizontalPadding: Style.space(5)
          foreground: forge.isPinned(editor.selectedKey) ? forge.dim : forge.colors.yellow
          accent: forge.colors.yellow
          tooltipText: forge.isPinned(editor.selectedKey)
            ? "Let the next roll change this colour again"
            : "Keep this colour exactly as it is through every roll"
          onClicked: forge.togglePin(editor.selectedKey)
          tint: forge.surface
          fillAlpha: forge.surfaceAlpha
        }
      }

      Row {
        width: parent.width
        spacing: Style.spacing.controlGap

        // The swatch is the way into the wheel. It is the biggest, most
        // colour-shaped thing on the page, so it is what a hand reaches for.
        Rectangle {
          width: Style.space(34)
          height: Style.space(30)
          radius: Style.space(8)
          antialiasing: true
          color: editor.selectedHex
          border.width: 1
          border.color: swatchHover.containsMouse ? forge.colors.accent : forge.hairline

          MouseArea {
            id: swatchHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: forge.wheelOpen = true
          }

          Text {
            anchors.centerIn: parent
            visible: swatchHover.containsMouse
            text: "\u25c9"
            textFormat: Text.PlainText
            color: Palette.luminance(editor.selectedHex) > 0.4 ? "#000000" : "#ffffff"
            font.pixelSize: Style.font.subtitle
          }
        }

        RiceField {
          id: hexField
          width: Style.space(104)
          text: editor.selectedHex
          foreground: forge.ink
          accent: forge.colors.accent
          font.family: forge.monoFont
          onAccepted: {
            var value = Palette.normHex(text)
            if (value === "") { text = editor.selectedHex; return }
            forge.setColor(editor.selectedKey, value)
          }
          tint: forge.surface
          fillAlpha: forge.surfaceAlpha
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: {
            if (editor.selectedKey === "background") return "this is the ground"
            var ratio = Palette.contrast(editor.selectedHex, editor.colors.background)
            return ratio.toFixed(1) + ":1 on the ground"
          }
          textFormat: Text.PlainText
          color: forge.dim
          font.family: forge.uiFont
          font.pixelSize: Style.font.caption
        }
      }

      SliderRow {
        width: parent.width
        forge: editor.forge
        label: "HUE"
        value: editor.selectedHsl.h
        minimum: 0
        maximum: 360
        readout: Math.round(editor.selectedHsl.h) + "°"
        onMovedTo: function (v) { editor.applyHsl(v, editor.selectedHsl.s, editor.selectedHsl.l) }
      }

      SliderRow {
        width: parent.width
        forge: editor.forge
        label: "SAT"
        value: editor.selectedHsl.s
        minimum: 0
        maximum: 1
        readout: Math.round(editor.selectedHsl.s * 100) + "%"
        onMovedTo: function (v) { editor.applyHsl(editor.selectedHsl.h, v, editor.selectedHsl.l) }
      }

      SliderRow {
        width: parent.width
        forge: editor.forge
        label: "LIGHT"
        value: editor.selectedHsl.l
        minimum: 0
        maximum: 1
        readout: Math.round(editor.selectedHsl.l * 100) + "%"
        onMovedTo: function (v) { editor.applyHsl(editor.selectedHsl.h, editor.selectedHsl.s, v) }
      }

      SliderRow {
        width: parent.width
        forge: editor.forge
        label: "CHROMA"
        value: editor.spec.chroma
        minimum: 0
        maximum: 100
        readout: editor.spec.chroma + "%"
        hint: "how colourful the terminal's sixteen colours are"
        onMovedTo: function (v) { forge.setChroma(v) }
      }

      Rectangle { width: parent.width; height: 1; color: forge.hairline }

      // ----------------------------------------------------------- the palette

      Row {
        width: parent.width

        Text {
          text: "THE TWENTY-SIX"
          textFormat: Text.PlainText
          color: forge.faint
          font.family: forge.uiFont
          font.pixelSize: Style.font.caption
          font.letterSpacing: 2
          font.bold: true
        }

        Item { width: Style.space(8); height: 1 }

        Text {
          text: "click to edit \u00b7 dot to lock"
          textFormat: Text.PlainText
          color: forge.faint
          font.family: forge.uiFont
          font.pixelSize: Style.font.caption
        }
      }

      Grid {
        width: parent.width
        columns: 2
        columnSpacing: Style.spacing.md
        rowSpacing: Style.space(3)

        Repeater {
          model: forge.contrastRows

          delegate: Rectangle {
            required property var modelData
            readonly property bool active: modelData.key === editor.selectedKey
            // Lit while the pointer is over this key in the preview, so the
            // grid answers "which one is that?" without a click.
            readonly property bool hovered: modelData.key === forge.hoverKey

            width: (flick.width - Style.spacing.md) / 2
            height: Style.space(21)
            radius: Style.cornerRadius
            color: active ? Qt.rgba(forge.ink.r, forge.ink.g, forge.ink.b, 0.10)
                 : hovered ? Qt.rgba(forge.ink.r, forge.ink.g, forge.ink.b, 0.05) : "transparent"
            border.width: hovered ? 1 : 0
            border.color: forge.colors.accent

            MouseArea {
              id: rowHover
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: function (mouse) {
                if (mouse.button === Qt.RightButton) forge.togglePin(modelData.key)
                else forge.selectedKey = modelData.key
              }
            }

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(13)
                height: Style.space(13)
                radius: 2
                color: modelData.hex
                border.width: 1
                border.color: forge.hairline
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Style.space(13) - Style.space(56) - Style.space(18)
                text: modelData.key
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: modelData.ok ? forge.dim : forge.colors.red
                font.family: forge.monoFont
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(38)
                horizontalAlignment: Text.AlignRight
                // Chrome sits behind or beside content rather than on it, so its
                // ratio is reported and not graded -- the same exemption the Tron
                // theme's contrast checker makes, for the same reason.
                text: modelData.exempt ? "--" : modelData.ratio.toFixed(1)
                textFormat: Text.PlainText
                color: modelData.exempt ? forge.faint : (modelData.ok ? forge.dim : forge.colors.red)
                font.family: forge.monoFont
                font.pixelSize: Style.font.caption
              }

              // The lock. A filled dot when locked; a hollow one appears under
              // the pointer so the affordance is discoverable without a label.
              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(10)
                text: forge.isPinned(modelData.key) ? "\u25cf" : (rowHover.containsMouse || lockHover.containsMouse ? "\u25cb" : "")
                textFormat: Text.PlainText
                color: forge.colors.yellow
                font.family: forge.monoFont
                font.pixelSize: Style.font.caption

                MouseArea {
                  id: lockHover
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: forge.togglePin(modelData.key)
                }
              }
            }
          }
        }
      }

      Item { width: 1; height: Style.space(6) }
    }
  }
}
