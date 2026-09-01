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
  readonly property var selectedHsl: Palette.hexToHsl(selectedHex)

  function applyHsl(hue, sat, light) {
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

      TextField {
        id: nameField
        width: parent.width
        placeholderText: "lowercase-name"
        text: forge.themeName
        foreground: forge.ink
        accent: forge.colors.accent
        font.family: forge.monoFont
        onTextChanged: forge.themeName = text
        onAccepted: forge.save(false)
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

      // Themes already on disk, to open and keep working on. Stock themes are
      // listed too -- opening one is a good way to start from something known --
      // but saving always goes to a new name, because the helper refuses to write
      // over anything Omarchy ships.
      Flow {
        width: parent.width
        spacing: Style.spacing.sm
        visible: repeater.count > 0

        Text {
          text: "OPEN"
          textFormat: Text.PlainText
          color: forge.faint
          font.family: forge.uiFont
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }

        Repeater {
          id: repeater
          model: forge.userThemes
          delegate: Button {
            required property string modelData
            text: modelData
            bordered: true
            fontSize: Style.font.caption
            verticalPadding: Style.space(2)
            horizontalPadding: Style.space(6)
            foreground: forge.dim
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

        // qs.Ui's own segmented control, so the mode switch looks and behaves
        // like every other one in the shell rather than like a pair of buttons
        // that happen to sit next to each other.
        ButtonGroup {
          anchors.verticalCenter: parent.verticalCenter
          options: ["dark", "light"]
          value: editor.spec.mode
          foreground: forge.ink
          background: forge.surface
          accent: forge.colors.accent
          fontFamily: forge.uiFont
          fontSize: Style.font.caption
          onChanged: function (value) { forge.setMode(value) }
        }

        Item { width: Style.space(4); height: 1 }

        TextField {
          id: seedField
          width: Style.space(84)
          text: String(editor.spec.seed)
          foreground: forge.ink
          accent: forge.colors.accent
          font.family: forge.monoFont
          onAccepted: forge.rollSeed(text)
        }

        Button {
          text: "Roll"
          bordered: true
          foreground: forge.colors.accent
          accent: forge.colors.accent
          tooltipText: "A new random colors that passes its own contrast bands"
          onClicked: forge.roll()
        }
      }

      // --------------------------------------------------------- the image

      Row {
        width: parent.width
        spacing: Style.spacing.controlGap

        Button {
          text: forge.sourceImage === "" ? "Use an image" : "Change image"
          bordered: true
          foreground: forge.ink
          enabled: !forge.busy && forge.imagesUsable()
          opacity: enabled ? 1 : 0.4
          tooltipText: forge.imagesUsable()
            ? "Seed the colors from a picture, and use it as the background"
            : forge.imageBlockedReason()
          onClicked: forge.pickImage()
        }

        Button {
          visible: forge.sourceImage !== ""
          text: "Drop it"
          bordered: true
          foreground: forge.dim
          enabled: !forge.busy
          tooltipText: "Go back to a background drawn from the colors"
          onClicked: forge.clearImage()
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
          text: "PINNED"
          textFormat: Text.PlainText
          color: forge.colors.yellow
          font.family: forge.uiFont
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }

        Button {
          anchors.verticalCenter: parent.verticalCenter
          visible: forge.isPinned(editor.selectedKey)
          text: "unpin"
          fontSize: Style.font.caption
          verticalPadding: Style.space(1)
          horizontalPadding: Style.space(5)
          bordered: true
          foreground: forge.dim
          tooltipText: "Let this colour be derived again"
          onClicked: forge.clearPin(editor.selectedKey)
        }
      }

      Row {
        width: parent.width
        spacing: Style.spacing.controlGap

        Rectangle {
          width: Style.space(34)
          height: Style.space(30)
          radius: Style.cornerRadius
          color: editor.selectedHex
          border.width: 1
          border.color: forge.hairline
        }

        TextField {
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
          text: "click to edit"
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

            width: (flick.width - Style.spacing.md) / 2
            height: Style.space(21)
            radius: Style.cornerRadius
            color: active ? Qt.rgba(forge.ink.r, forge.ink.g, forge.ink.b, 0.10) : "transparent"

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onClicked: forge.selectedKey = modelData.key
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

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(10)
                text: forge.isPinned(modelData.key) ? "•" : ""
                textFormat: Text.PlainText
                color: forge.colors.yellow
                font.family: forge.monoFont
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }

      Item { width: 1; height: Style.space(6) }
    }
  }
}
